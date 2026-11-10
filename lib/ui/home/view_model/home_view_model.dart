import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../config/providers.dart';
import '../../../data/repositories/download_starter.dart';
import '../../../data/services/android/share_link_service.dart';
import '../../../data/services/android/storage_permission_service.dart';
import '../../../domain/exceptions/ftube_exception.dart';
import '../../../domain/models/models.dart';

export '../../../data/repositories/download_starter.dart' show NoDownloadFolder;

part 'home_view_model.freezed.dart';
part 'home_view_model.g.dart';

@freezed
abstract class HomeState with _$HomeState {
  const factory HomeState({
    required QualityPreset preset,
    @Default('') String url,
    @Default(false) bool fetching,

    /// The fetched video or playlist.
    FetchResult? info,

    /// Indexes of the playlist entries to download (spec-v0.5 D-57).
    @Default(<int>{}) Set<int> selected,

    /// Counts links opened from elsewhere, such as the share popup, so the
    /// shell can switch to Home (spec-v0.5 D-79).
    @Default(0) int linkOpened,

    /// The last fetch or download error, cleared by the next action.
    Object? error,

    /// Set with [QualityPreset.custom].
    String? formatId,

    /// A link found on the clipboard, offered once.
    String? clipboardUrl,

    /// Android: storage access is missing, so downloads are blocked.
    @Default(false) bool storageBlocked,

    /// The status of each video with a queued, running or paused job, by
    /// [videoKey] (spec-v0.5 D-83).
    @Default(<String, JobStatus>{}) Map<String, JobStatus> active,

    /// Whether the playlist's video list is expanded (spec-v0.5 D-84).
    @Default(false) bool listOpen,

    /// Earlier screens to go back to, last on top (spec-v0.5 D-85).
    @Default(<HomeStep>[]) List<HomeStep> back,
  }) = _HomeState;

  const HomeState._();

  /// The job status of the video at [url] while it is queued, running or
  /// paused.
  JobStatus? activeStatus(String url) => active[videoKey(url)];

  /// Whether the playlist entry at [index] can be ticked: available and not
  /// in the queue already.
  bool selectable(int index) {
    final entry = playlist?.entries.elementAtOrNull(index);
    return entry != null &&
        entry.downloadable &&
        activeStatus(entry.url) == null;
  }

  /// The fetched video is already in the queue.
  bool get videoActive => switch (video) {
    final v? => activeStatus(v.url) != null,
    null => false,
  };

  /// The fetched video, if [info] is one.
  MediaInfo? get video => switch (info) {
    final MediaInfo v => v,
    _ => null,
  };

  /// The fetched playlist, if [info] is one.
  PlaylistInfo? get playlist => switch (info) {
    final PlaylistInfo p => p,
    _ => null,
  };

  bool get canFetch => url.trim().isNotEmpty && !fetching;

  bool get canDownload =>
      !fetching &&
      !storageBlocked &&
      switch (info) {
        MediaInfo() =>
          !videoActive && (preset != QualityPreset.custom || formatId != null),
        PlaylistInfo() => selectedEntries.isNotEmpty,
        null => false,
      };

  MediaFormat? get selectedFormat => preset == QualityPreset.custom
      ? video?.formats.where((f) => f.id == formatId).firstOrNull
      : null;

  /// A video link that names a playlist too (`watch?v=…&list=…`), so Home
  /// offers "Show playlist" (spec-v0.5 D-55).
  bool get offersPlaylist =>
      video != null &&
      (Uri.tryParse(url)?.queryParameters.containsKey('list') ?? false);

  /// The playlist entries chosen for download, in playlist order, leaving
  /// out any that got queued meanwhile.
  List<PlaylistEntry> get selectedEntries {
    final entries = playlist?.entries ?? const <PlaylistEntry>[];
    return [
      for (var i = 0; i < entries.length; i++)
        if (selected.contains(i) && selectable(i)) entries[i],
    ];
  }

  /// Indexes of the entries that can be ticked.
  Set<int> get selectableEntries => {
    for (var i = 0; i < (playlist?.entries.length ?? 0); i++)
      if (selectable(i)) i,
  };
}

/// A screen Home can go back to (spec-v0.5 D-85).
@freezed
abstract class HomeStep with _$HomeStep {
  const factory HomeStep({
    required String url,
    required FetchResult info,
    @Default(<int>{}) Set<int> selected,
    @Default(false) bool listOpen,
  }) = _HomeStep;
}

/// The status of each video with a queued, running or paused job.
Map<String, JobStatus> _activeVideos(Iterable<DownloadJob> jobs) => {
  for (final j in jobs)
    if (j.status.isActive || j.status == JobStatus.paused)
      videoKey(j.request.url): j.status,
};

/// Presets offered as chips, for a video and a playlist (spec-v0.5 D-77,
/// D-78); [QualityPreset.custom] is picked through the format list instead.
const homePresets = [
  QualityPreset.best,
  QualityPreset.p1080,
  QualityPreset.p720,
  QualityPreset.p480,
  QualityPreset.p360,
  QualityPreset.audioMp3,
  QualityPreset.audioM4a,
  QualityPreset.audioOgg,
];

/// Whether [text] is an http(s) link.
bool isWebUrl(String text) {
  final uri = Uri.tryParse(text.trim());
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

/// Home screen: paste a link, read its info, pick a quality, download.
/// Kept alive so a fetched video survives switching tabs.
@Riverpod(keepAlive: true)
class HomeViewModel extends _$HomeViewModel {
  /// Guards against an older fetch overwriting a newer one.
  var _fetchSeq = 0;

  /// The last clipboard link offered, so it is offered only once.
  String? _offered;

  @override
  HomeState build() {
    ref.listen(currentSettingsProvider.select((s) => s.defaultPreset), (
      _,
      preset,
    ) {
      if (state.info == null) state = state.copyWith(preset: preset);
    });
    final repo = ref.watch(downloadRepositoryProvider);
    final sub = repo.changes.listen(
      (jobs) => state = state.copyWith(active: _activeVideos(jobs)),
    );
    ref.onDispose(sub.cancel);
    return HomeState(
      preset: ref.read(currentSettingsProvider).defaultPreset,
      active: _activeVideos(repo.jobs),
    );
  }

  void setUrl(String url) => state = state.copyWith(url: url, error: null);

  /// Reads info for the current link.
  Future<void> fetch() async {
    if (state.fetching) return;
    state = state.copyWith(back: const []);
    await _fetch();
  }

  /// Reads the playlist of a `watch?v=…&list=…` link (spec-v0.5 D-55).
  Future<void> showPlaylist() async {
    if (state.fetching || !state.offersPlaylist) return;
    _pushBack();
    await _fetch(playlist: true);
  }

  /// Puts [url] in the link field and fetches it, from the share popup
  /// (spec-v0.5 D-79).
  Future<void> openLink(String url) async {
    state = state.copyWith(
      url: url,
      clipboardUrl: null,
      error: null,
      linkOpened: state.linkOpened + 1,
      back: const [],
    );
    await _fetch();
  }

  Future<void> _fetch({bool playlist = false}) async {
    final url = state.url.trim();
    if (url.isEmpty) return;
    final seq = ++_fetchSeq;
    if (!isWebUrl(url)) {
      state = state.copyWith(
        fetching: false,
        info: null,
        error: const InvalidUrl(),
      );
      return;
    }
    state = state.copyWith(
      url: url,
      fetching: true,
      info: null,
      error: null,
      formatId: null,
      selected: const {},
      preset: state.preset == QualityPreset.custom
          ? ref.read(currentSettingsProvider).defaultPreset
          : state.preset,
    );
    try {
      final info = await ref
          .read(mediaServiceProvider)
          .fetchInfo(url, playlist: playlist);
      if (!ref.mounted || seq != _fetchSeq) return;
      state = state.copyWith(fetching: false, info: info);
      state = state.copyWith(
        selected: state.selectableEntries,
        listOpen: info is PlaylistInfo && info.entries.any((e) => e.isList),
      );
    } on Object catch (e) {
      if (!ref.mounted || seq != _fetchSeq) return;
      state = state.copyWith(fetching: false, error: e);
    }
  }

  /// Pastes the clipboard into the link field and fetches it.
  Future<void> paste() async {
    final text = (await _readClipboard())?.trim();
    if (text == null || text.isEmpty || !ref.mounted) return;
    _offered = text;
    state = state.copyWith(url: text, clipboardUrl: null, error: null);
    await fetch();
  }

  /// Offers a link found on the clipboard, unless it is already in the
  /// field or was offered before.
  Future<void> checkClipboard() async {
    final text = (await _readClipboard())?.trim();
    if (text == null || !ref.mounted) return;
    if (!isWebUrl(text) || text == state.url.trim() || text == _offered) {
      return;
    }
    _offered = text;
    state = state.copyWith(clipboardUrl: text);
  }

  Future<void> useClipboard() async {
    final url = state.clipboardUrl;
    if (url == null) return;
    state = state.copyWith(url: url, clipboardUrl: null, error: null);
    await fetch();
  }

  void dismissClipboard() => state = state.copyWith(clipboardUrl: null);

  void selectPreset(QualityPreset preset) {
    if (preset == QualityPreset.custom) {
      throw ArgumentError.value(preset, 'preset', 'use selectFormat');
    }
    state = state.copyWith(preset: preset, formatId: null);
  }

  void selectFormat(String formatId) {
    if (state.video == null) return;
    state = state.copyWith(preset: QualityPreset.custom, formatId: formatId);
  }

  /// Selects or unselects a playlist entry that can be downloaded.
  void toggleEntry(int index) {
    if (!state.selectable(index)) return;
    final selected = {...state.selected};
    if (!selected.remove(index)) selected.add(index);
    state = state.copyWith(selected: selected);
  }

  void selectAll() => state = state.copyWith(selected: state.selectableEntries);

  void selectNone() => state = state.copyWith(selected: const {});

  /// Opens an entry that is a list itself, such as a channel tab, like a
  /// new link (spec-v0.5 section 2).
  Future<void> openEntry(int index) async {
    final entry = state.playlist?.entries.elementAtOrNull(index);
    if (entry == null || !entry.isList) return;
    _pushBack();
    state = state.copyWith(url: entry.url, error: null);
    await _fetch();
  }

  /// Queues the fetched video with the chosen quality. Returns the job, or
  /// null when it could not be queued; [HomeState.error] or
  /// [HomeState.storageBlocked] then says why.
  Future<DownloadJob?> download() async {
    final info = state.video;
    if (info == null || !state.canDownload) return null;
    return _start(
      () => ref
          .read(downloadStarterProvider)
          .start(info, state.preset, format: state.selectedFormat),
    );
  }

  /// Queues the selected playlist entries with the chosen preset
  /// (spec-v0.5 D-58). Returns the jobs, or null as [download] does.
  Future<List<DownloadJob>?> downloadPlaylist() async {
    if (state.playlist == null || !state.canDownload) return null;
    final preset = state.preset == QualityPreset.custom
        ? QualityPreset.best
        : state.preset;
    final jobs = await _start(
      () => ref
          .read(downloadStarterProvider)
          .startAll(state.selectedEntries, preset),
    );
    if (jobs != null && ref.mounted) {
      state = state.copyWith(selected: const {});
    }
    return jobs;
  }

  /// Expands or collapses the playlist's video list (spec-v0.5 D-84).
  void toggleList() => state = state.copyWith(listOpen: !state.listOpen);

  /// Returns to the screen before a tab or "Show playlist" was opened,
  /// without a fetch (spec-v0.5 D-85). False when there is none.
  bool goBack() {
    if (state.back.isEmpty) return false;
    final step = state.back.last;
    _fetchSeq++;
    state = state.copyWith(
      url: step.url,
      info: step.info,
      selected: step.selected,
      listOpen: step.listOpen,
      back: state.back.sublist(0, state.back.length - 1),
      fetching: false,
      error: null,
    );
    return true;
  }

  /// Keeps the current screen so [goBack] can return to it.
  void _pushBack() {
    final info = state.info;
    if (info == null) return;
    state = state.copyWith(
      back: [
        ...state.back,
        HomeStep(
          url: state.url,
          info: info,
          selected: state.selected,
          listOpen: state.listOpen,
        ),
      ],
    );
  }

  Future<T?> _start<T>(Future<T> Function() start) async {
    try {
      final result = await start();
      if (ref.mounted) state = state.copyWith(error: null);
      return result;
    } on StorageBlocked {
      if (ref.mounted) state = state.copyWith(storageBlocked: true);
    } on NoDownloadFolder catch (e) {
      if (ref.mounted) state = state.copyWith(error: e);
    }
    return null;
  }

  /// Android: asks for storage access, or opens the app settings when
  /// Android will not ask again.
  Future<void> grantStorageAccess() async {
    final storage = ref.read(storagePermissionServiceProvider);
    if (storage == null) return;
    var access = await storage.request();
    if (access == StorageAccess.permanentlyDenied) {
      await storage.openSettings();
      access = await storage.status();
    }
    if (ref.mounted) {
      state = state.copyWith(storageBlocked: access != StorageAccess.granted);
    }
  }

  /// Android: re-checks a blocked storage access, for example when the user
  /// comes back from system settings.
  Future<void> refreshStorageAccess() async {
    final storage = ref.read(storagePermissionServiceProvider);
    if (storage == null || !state.storageBlocked) return;
    final access = await storage.status();
    if (ref.mounted && access == StorageAccess.granted) {
      state = state.copyWith(storageBlocked: false);
    }
  }

  Future<String?> _readClipboard() async {
    try {
      return await ref.read(clipboardReaderProvider)();
    } on Object {
      return null;
    }
  }
}
