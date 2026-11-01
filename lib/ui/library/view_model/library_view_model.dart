import 'dart:async';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../config/providers.dart';
import '../../../data/repositories/library_repository.dart';
import '../../../data/services/android/storage_permission_service.dart';
import '../../../domain/exceptions/ftube_exception.dart';
import '../../../domain/models/models.dart';
import '../../home/view_model/home_view_model.dart' show NoDownloadFolder;

part 'library_view_model.freezed.dart';
part 'library_view_model.g.dart';

enum LibraryFilter { all, video, audio }

/// Newest first, A to Z, or largest first.
enum LibrarySort { date, name, size }

/// A one-off message for the View, shown as a snackbar. Each instance is
/// new, so the same message twice is still shown twice.
sealed class LibraryNotice {
  const LibraryNotice();
}

/// [count] files are hidden and will be deleted unless the user undoes it.
final class LibraryDeleted extends LibraryNotice {
  const LibraryDeleted(this.count);

  final int count;
}

/// A conversion finished as [name].
final class LibraryConverted extends LibraryNotice {
  const LibraryConverted(this.name);

  final String name;
}

/// An action failed with [error].
final class LibraryFailed extends LibraryNotice {
  const LibraryFailed(this.error);

  final Object error;
}

@freezed
abstract class LibraryState with _$LibraryState {
  const factory LibraryState({
    /// Every file in the download folder, newest first.
    @Default(<LibraryItem>[]) List<LibraryItem> items,
    @Default(true) bool loading,

    /// Why the folder could not be listed.
    Object? error,
    @Default('') String query,
    @Default(LibraryFilter.all) LibraryFilter filter,
    @Default(LibrarySort.date) LibrarySort sort,

    /// Paths of the selected files.
    @Default(<String>{}) Set<String> selected,

    /// Paths hidden while their delete can still be undone.
    @Default(<String>{}) Set<String> pendingDelete,

    /// Paths being converted, with the progress when known.
    @Default(<String, double?>{}) Map<String, double?> converting,
    @Default(false) bool canOpen,
    @Default(false) bool canReveal,
    @Default(false) bool canShare,
    LibraryNotice? notice,
  }) = _LibraryState;

  const LibraryState._();

  /// The files to show: not pending delete, matching the filter and the
  /// search, in the chosen order.
  List<LibraryItem> get visible {
    final q = query.trim().toLowerCase();
    final shown = items.where(
      (i) =>
          !pendingDelete.contains(i.path) &&
          switch (filter) {
            LibraryFilter.all => true,
            LibraryFilter.video => i.kind == LibraryKind.video,
            LibraryFilter.audio => i.kind == LibraryKind.audio,
          } &&
          (q.isEmpty || i.name.toLowerCase().contains(q)),
    );
    return shown.toList()..sort(switch (sort) {
      LibrarySort.date => (a, b) => b.modified.compareTo(a.modified),
      LibrarySort.name => (a, b) => a.name.toLowerCase().compareTo(
        b.name.toLowerCase(),
      ),
      LibrarySort.size => (a, b) => b.sizeBytes.compareTo(a.sizeBytes),
    });
  }

  /// Whether the folder holds any file at all, before searching.
  bool get isEmpty => items.every((i) => pendingDelete.contains(i.path));

  bool get selecting => selected.isNotEmpty;

  bool get storageBlocked => error is StoragePermission;

  /// Whether [item] can be converted to [target] now.
  bool canConvert(LibraryItem item, AudioTarget target) =>
      item.kind != LibraryKind.other &&
      p.extension(item.name).toLowerCase() != '.${target.extension}' &&
      !converting.containsKey(item.path);
}

/// Library screen: the files in the download folder and what can be done
/// with them. Kept alive so search, sort and running conversions survive
/// switching tabs.
@Riverpod(keepAlive: true)
class LibraryViewModel extends _$LibraryViewModel {
  /// How long a delete can be undone.
  static const undoWindow = Duration(seconds: 5);

  var _loadSeq = 0;
  var _convertSeq = 0;
  Timer? _deleteTimer;
  List<LibraryItem> _toDelete = const [];

  /// Running conversions: item path to job id and subscription.
  final _conversions =
      <String, (String jobId, StreamSubscription<JobProgress> sub)>{};

  /// Completed downloads seen so far, to reload when one more finishes.
  var _completed = <String>{};

  /// The folder the list was last requested for.
  String? _listedDir;

  LibraryRepository get _repo => ref.read(libraryRepositoryProvider);

  @override
  LibraryState build() {
    final repo = ref.watch(libraryRepositoryProvider);
    final downloads = ref.watch(downloadRepositoryProvider);
    _completed = _completedIds(downloads.jobs);
    var listed = false;
    final sub = downloads.changes.listen((jobs) {
      final completed = _completedIds(jobs);
      final added = completed.difference(_completed).isNotEmpty;
      _completed = completed;
      if (added) unawaited(load());
    });
    ref
      ..listen(downloadDirectoryProvider, (_, next) {
        // Lists once the folder is known, and again when it changes.
        if (next.isLoading) return;
        final path = next.value?.path;
        if (listed && path == _listedDir && !next.hasError) return;
        listed = true;
        _listedDir = path;
        unawaited(Future.microtask(load));
      }, fireImmediately: true)
      ..onDispose(() {
        unawaited(sub.cancel());
        _deleteTimer?.cancel();
        if (_toDelete.isNotEmpty) unawaited(_deleteQuietly(repo, _toDelete));
        for (final (jobId, s) in _conversions.values) {
          unawaited(s.cancel());
          unawaited(repo.cancelConversion(jobId));
        }
        _conversions.clear();
      });
    return LibraryState(
      canOpen: repo.canOpen,
      canReveal: repo.canReveal,
      canShare: repo.canShare,
    );
  }

  /// Lists the download folder again.
  Future<void> load() async {
    if (!ref.mounted) return;
    final seq = ++_loadSeq;
    state = state.copyWith(loading: true);
    try {
      final dir = await ref.read(downloadDirectoryProvider.future);
      if (dir == null) throw const NoDownloadFolder();
      final items = await _repo.list(dir);
      if (!ref.mounted || seq != _loadSeq) return;
      final paths = {for (final i in items) i.path};
      state = state.copyWith(
        items: items,
        loading: false,
        error: null,
        selected: state.selected.intersection(paths),
      );
    } on Object catch (e) {
      if (!ref.mounted || seq != _loadSeq) return;
      state = state.copyWith(
        items: const [],
        loading: false,
        error: e,
        selected: const {},
      );
    }
  }

  void search(String query) => state = state.copyWith(query: query);

  void setFilter(LibraryFilter filter) =>
      state = state.copyWith(filter: filter, selected: const {});

  void setSort(LibrarySort sort) => state = state.copyWith(sort: sort);

  void toggleSelected(LibraryItem item) {
    final selected = {...state.selected};
    if (!selected.remove(item.path)) selected.add(item.path);
    state = state.copyWith(selected: selected);
  }

  void selectAll() =>
      state = state.copyWith(selected: {for (final i in state.visible) i.path});

  void clearSelection() => state = state.copyWith(selected: const {});

  /// The selected files, in display order.
  List<LibraryItem> get selectedItems =>
      state.visible.where((i) => state.selected.contains(i.path)).toList();

  /// Hides [items] at once and deletes them after [undoWindow], unless
  /// [undoDelete] is called first. A delete still pending is carried out
  /// right away.
  Future<void> delete(List<LibraryItem> items) async {
    if (items.isEmpty) return;
    await _commitDelete();
    if (!ref.mounted) return;
    final paths = {for (final i in items) i.path};
    _toDelete = items;
    state = state.copyWith(
      pendingDelete: paths,
      selected: state.selected.difference(paths),
      notice: LibraryDeleted(items.length),
    );
    _deleteTimer = Timer(undoWindow, () => unawaited(_commitDelete()));
  }

  Future<void> deleteSelected() => delete(selectedItems);

  /// Deletes every file shown with the current filter and search.
  Future<void> deleteAll() => delete(state.visible);

  /// Brings back the files of the pending delete.
  void undoDelete() {
    _deleteTimer?.cancel();
    _deleteTimer = null;
    _toDelete = const [];
    state = state.copyWith(pendingDelete: const {});
  }

  /// Renames [item]. Returns the error to show next to the name, or null
  /// when it worked.
  Future<Object?> rename(LibraryItem item, String newName) async {
    try {
      final renamed = await _repo.rename(item, newName);
      if (!ref.mounted) return null;
      state = state.copyWith(
        items: [for (final i in state.items) i.path == item.path ? renamed : i],
        selected: {
          for (final s in state.selected) s == item.path ? renamed.path : s,
        },
      );
      return null;
    } on Object catch (e) {
      return e;
    }
  }

  /// Converts [item] to [target] next to the original.
  void convert(LibraryItem item, AudioTarget target) {
    if (!state.canConvert(item, target)) return;
    final path = item.path;
    final jobId =
        'convert-${DateTime.now().microsecondsSinceEpoch}-${_convertSeq++}';
    String? output;
    state = state.copyWith(converting: {...state.converting, path: null});
    void end(LibraryNotice? notice) {
      if (_conversions.remove(path) == null || !ref.mounted) return;
      state = state.copyWith(
        converting: {...state.converting}..remove(path),
        notice: notice ?? state.notice,
      );
      if (output != null) unawaited(load());
    }

    // Cancelled in cancelConversion and on dispose.
    // ignore: cancel_subscriptions
    final sub = _repo
        .convert(item, target, jobId: jobId)
        .listen(
          (progress) {
            if (!ref.mounted || !_conversions.containsKey(path)) return;
            if (progress.phase == JobPhase.finished) {
              output = progress.outputPath;
            }
            state = state.copyWith(
              converting: {...state.converting, path: progress.fraction},
            );
          },
          onError: (Object e) => end(e is Cancelled ? null : LibraryFailed(e)),
          onDone: () => end(
            output == null
                ? const LibraryFailed(
                    Unexpected('conversion ended without a result'),
                  )
                : LibraryConverted(p.basename(output!)),
          ),
          cancelOnError: true,
        );
    _conversions[path] = (jobId, sub);
  }

  /// Stops the conversion of [item]; its partial output is removed by the
  /// media service.
  Future<void> cancelConversion(LibraryItem item) async {
    final run = _conversions.remove(item.path);
    if (run == null) return;
    state = state.copyWith(
      converting: {...state.converting}..remove(item.path),
    );
    final (jobId, sub) = run;
    await _repo.cancelConversion(jobId);
    await sub.cancel();
  }

  Future<void> open(LibraryItem item) =>
      _run(() => _repo.open(item), when: state.canOpen);

  Future<void> reveal(LibraryItem item) =>
      _run(() => _repo.reveal(item), when: state.canReveal);

  Future<void> share(LibraryItem item) =>
      _run(() => _repo.share(item), when: state.canShare);

  /// Android: asks for storage access, or opens the app settings when
  /// Android will not ask again, then lists the folder.
  Future<void> grantStorageAccess() async {
    final storage = ref.read(storagePermissionServiceProvider);
    if (storage == null) return;
    var access = await storage.request();
    if (access == StorageAccess.permanentlyDenied) {
      await storage.openSettings();
      access = await storage.status();
    }
    if (access == StorageAccess.granted) await load();
  }

  Future<void> _run(
    Future<void> Function() action, {
    required bool when,
  }) async {
    if (!when) return;
    try {
      await action();
    } on Object catch (e) {
      if (ref.mounted) state = state.copyWith(notice: LibraryFailed(e));
    }
  }

  Future<void> _commitDelete() async {
    _deleteTimer?.cancel();
    _deleteTimer = null;
    final items = _toDelete;
    if (items.isEmpty) return;
    _toDelete = const [];
    Object? error;
    try {
      await _repo.delete(items);
    } on Object catch (e) {
      error = e;
    }
    if (!ref.mounted) return;
    final gone = {for (final i in items) i.path};
    state = state.copyWith(
      pendingDelete: state.pendingDelete.difference(gone),
      notice: error == null ? state.notice : LibraryFailed(error),
    );
    await load();
  }

  static Future<void> _deleteQuietly(
    LibraryRepository repo,
    List<LibraryItem> items,
  ) async {
    try {
      await repo.delete(items);
    } on Object {
      // Disposed; nobody is left to tell.
    }
  }

  static Set<String> _completedIds(List<DownloadJob> jobs) => {
    for (final j in jobs)
      if (j.status == JobStatus.completed) j.id,
  };
}
