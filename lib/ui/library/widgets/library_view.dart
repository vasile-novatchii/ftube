import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../../domain/models/models.dart';
import '../../core/l10n.dart';
import '../../home/view_model/home_view_model.dart' show NoDownloadFolder;
import '../view_model/library_view_model.dart';

/// The files in the download folder: search, filter, sort, open, share or
/// reveal, convert, rename and delete.
class LibraryView extends ConsumerStatefulWidget {
  const LibraryView({super.key});

  @override
  ConsumerState<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends ConsumerState<LibraryView> {
  final _search = TextEditingController();
  late final AppLifecycleListener _lifecycle;

  LibraryViewModel get _vm => ref.read(libraryViewModelProvider.notifier);

  @override
  void initState() {
    super.initState();
    _search.text = ref.read(libraryViewModelProvider).query;
    // Files may have changed, or access been granted, while away.
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_vm.load()));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _search.dispose();
    super.dispose();
  }

  void _showNotice(LibraryNotice notice) {
    final l10n = context.l10n;
    final snackBar = switch (notice) {
      LibraryDeleted(:final count) => SnackBar(
        content: Row(
          children: [
            const UndoCountdown(duration: LibraryViewModel.undoWindow),
            const SizedBox(width: 16),
            Expanded(child: Text(l10n.libraryDeleted(count))),
          ],
        ),
        duration: LibraryViewModel.undoWindow,
        // A SnackBar with an action stays until dismissed by default.
        persist: false,
        action: SnackBarAction(label: l10n.undo, onPressed: _vm.undoDelete),
      ),
      LibraryConverted(:final name) => SnackBar(
        content: Text(l10n.libraryConverted(name)),
      ),
      LibraryFailed(:final error) => SnackBar(
        content: Text(l10n.errorMessage(error)),
      ),
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(snackBar);
  }

  /// Asks before deleting [items]; deletes them when confirmed.
  Future<void> _confirmDelete(List<LibraryItem> items) async {
    if (items.isEmpty) return;
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          items.length == 1
              ? l10n.libraryDeleteNamed(items.single.name)
              : l10n.libraryDeleteCount(items.length),
        ),
        content: Text(l10n.libraryDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('library.confirmDelete'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.libraryDelete),
          ),
        ],
      ),
    );
    if (ok ?? false) await _vm.delete(items);
  }

  Future<void> _rename(LibraryItem item) => showDialog<void>(
    context: context,
    builder: (context) => _RenameDialog(item: item, onRename: _vm.rename),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(libraryViewModelProvider);
    ref.listen(libraryViewModelProvider.select((s) => s.notice), (_, notice) {
      if (notice != null) _showNotice(notice);
    });
    final visible = state.visible;

    final appBar = state.selecting
        ? AppBar(
            leading: IconButton(
              key: const Key('library.clearSelection'),
              tooltip: l10n.libraryClearSelection,
              icon: const Icon(Icons.close),
              onPressed: _vm.clearSelection,
            ),
            title: Text(l10n.librarySelected(state.selected.length)),
            actions: [
              IconButton(
                key: const Key('library.selectAll'),
                tooltip: l10n.librarySelectAll,
                icon: const Icon(Icons.select_all),
                onPressed: _vm.selectAll,
              ),
              IconButton(
                key: const Key('library.deleteSelected'),
                tooltip: l10n.libraryDelete,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _confirmDelete(_vm.selectedItems),
              ),
            ],
          )
        : AppBar(
            title: Text(l10n.navLibrary),
            actions: [
              IconButton(
                key: const Key('library.refresh'),
                tooltip: l10n.libraryRefresh,
                icon: const Icon(Icons.refresh),
                onPressed: _vm.load,
              ),
              PopupMenuButton<LibrarySort>(
                key: const Key('library.sort'),
                tooltip: l10n.librarySort,
                icon: const Icon(Icons.sort),
                initialValue: state.sort,
                onSelected: _vm.setSort,
                itemBuilder: (_) => [
                  for (final sort in LibrarySort.values)
                    CheckedPopupMenuItem(
                      key: Key('library.sort.${sort.name}'),
                      value: sort,
                      checked: sort == state.sort,
                      child: Text(_sortLabel(l10n, sort)),
                    ),
                ],
              ),
              if (visible.isNotEmpty)
                PopupMenuButton<void>(
                  key: const Key('library.menu'),
                  tooltip: l10n.libraryMore,
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      key: const Key('library.deleteAll'),
                      onTap: () => _confirmDelete(visible),
                      child: Text(l10n.libraryDeleteAll),
                    ),
                  ],
                ),
            ],
          );

    return Scaffold(
      appBar: appBar,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: TextField(
                    key: const Key('library.search'),
                    controller: _search,
                    onChanged: _vm.search,
                    decoration: InputDecoration(
                      hintText: l10n.librarySearchHint,
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                SegmentedButton<LibraryFilter>(
                  key: const Key('library.filter'),
                  showSelectedIcon: false,
                  segments: [
                    for (final f in LibraryFilter.values)
                      ButtonSegment(
                        value: f,
                        label: Text(
                          _filterLabel(l10n, f),
                          key: Key('library.filter.${f.name}'),
                        ),
                      ),
                  ],
                  selected: {state.filter},
                  onSelectionChanged: (s) => _vm.setFilter(s.single),
                ),
              ],
            ),
          ),
          Expanded(child: _body(context, state, visible)),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    LibraryState state,
    List<LibraryItem> visible,
  ) {
    final l10n = context.l10n;
    if (state.loading && state.items.isEmpty && state.error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error case final error?) {
      return _Message(
        text: error is NoDownloadFolder
            ? l10n.homeNoFolder
            : l10n.errorMessage(error),
        action: state.storageBlocked
            ? FilledButton(
                key: const Key('library.grant'),
                onPressed: _vm.grantStorageAccess,
                child: Text(l10n.storageGrant),
              )
            : OutlinedButton(
                key: const Key('library.retry'),
                onPressed: _vm.load,
                child: Text(l10n.retry),
              ),
      );
    }
    if (state.isEmpty) return _Message(text: l10n.libraryEmpty);
    if (visible.isEmpty) return _Message(text: l10n.libraryNoMatches);
    return RefreshIndicator(
      onRefresh: _vm.load,
      child: ListView.builder(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: visible.length,
        itemBuilder: (context, i) {
          final item = visible[i];
          return _ItemRow(
            key: ValueKey(item.path),
            item: item,
            state: state,
            onDelete: () => _confirmDelete([item]),
            onRename: () => _rename(item),
          );
        },
      ),
    );
  }

  static String _filterLabel(AppLocalizations l10n, LibraryFilter f) =>
      switch (f) {
        LibraryFilter.all => l10n.libraryFilterAll,
        LibraryFilter.video => l10n.libraryFilterVideo,
        LibraryFilter.audio => l10n.libraryFilterAudio,
      };

  static String _sortLabel(AppLocalizations l10n, LibrarySort s) => switch (s) {
    LibrarySort.date => l10n.librarySortDate,
    LibrarySort.name => l10n.librarySortName,
    LibrarySort.size => l10n.librarySortSize,
  };
}

enum _Action { open, reveal, share, mp3, ogg, rename, delete }

class _ItemRow extends ConsumerWidget {
  const _ItemRow({
    required this.item,
    required this.state,
    required this.onDelete,
    required this.onRename,
    super.key,
  });

  final LibraryItem item;
  final LibraryState state;
  final VoidCallback onDelete;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final vm = ref.read(libraryViewModelProvider.notifier);
    final path = item.path;
    final selected = state.selected.contains(path);
    final converting = state.converting.containsKey(path);
    final date = DateFormat.yMMMd(l10n.localeName)
        .add_Hm()
        .format(item.modified);

    void onAction(_Action action) => switch (action) {
      _Action.open => unawaited(vm.open(item)),
      _Action.reveal => unawaited(vm.reveal(item)),
      _Action.share => unawaited(vm.share(item)),
      _Action.mp3 => vm.convert(item, AudioTarget.mp3),
      _Action.ogg => vm.convert(item, AudioTarget.ogg),
      _Action.rename => onRename(),
      _Action.delete => onDelete(),
    };

    PopupMenuItem<_Action> entry(_Action action, String label) => PopupMenuItem(
      key: Key('library.${action.name}.$path'),
      value: action,
      child: Text(label),
    );

    return ListTile(
      selected: selected,
      leading: state.selecting
          ? Checkbox(
              key: Key('library.check.$path'),
              value: selected,
              onChanged: (_) => vm.toggleSelected(item),
            )
          : Icon(switch (item.kind) {
              LibraryKind.video => Icons.movie_outlined,
              LibraryKind.audio => Icons.music_note_outlined,
              LibraryKind.other => Icons.insert_drive_file_outlined,
            }),
      title: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: converting
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                LinearProgressIndicator(value: state.converting[path]),
                const SizedBox(height: 2),
                Text(l10n.phaseConverting),
              ],
            )
          : Text(
              '${formatBytes(item.sizeBytes)} · $date',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
      onTap: state.selecting
          ? () => vm.toggleSelected(item)
          : state.canOpen
          ? () => unawaited(vm.open(item))
          : null,
      onLongPress: () => vm.toggleSelected(item),
      trailing: state.selecting
          ? null
          : converting
          ? IconButton(
              key: Key('library.stop.$path'),
              tooltip: l10n.libraryStopConverting,
              icon: const Icon(Icons.stop_circle_outlined),
              onPressed: () => unawaited(vm.cancelConversion(item)),
            )
          : PopupMenuButton<_Action>(
              key: Key('library.actions.$path'),
              tooltip: l10n.libraryMore,
              onSelected: onAction,
              itemBuilder: (_) => [
                if (state.canOpen) entry(_Action.open, l10n.libraryOpen),
                if (state.canReveal) entry(_Action.reveal, l10n.libraryReveal),
                if (state.canShare) entry(_Action.share, l10n.libraryShare),
                if (state.canConvert(item, AudioTarget.mp3))
                  entry(_Action.mp3, l10n.libraryConvertMp3),
                if (state.canConvert(item, AudioTarget.ogg))
                  entry(_Action.ogg, l10n.libraryConvertOgg),
                entry(_Action.rename, l10n.libraryRename),
                entry(_Action.delete, l10n.libraryDelete),
              ],
            ),
    );
  }
}

/// Asks for a new name and shows why a rename failed.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.item, required this.onRename});

  final LibraryItem item;
  final Future<Object?> Function(LibraryItem item, String name) onRename;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _name = TextEditingController(
    text: p.basenameWithoutExtension(widget.item.name),
  );
  Object? _error;
  var _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final error = await widget.onRename(widget.item, _name.text);
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context);
    } else {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ext = p.extension(widget.item.name);
    return AlertDialog(
      title: Text(l10n.libraryRenameTitle),
      content: TextField(
        key: const Key('library.renameField'),
        controller: _name,
        autofocus: true,
        onSubmitted: (_) => _save(),
        decoration: InputDecoration(
          labelText: l10n.libraryRenameLabel,
          suffixText: ext.isEmpty ? null : ext,
          errorText: switch (_error) {
            null => null,
            final e => l10n.errorMessage(e),
          },
          errorMaxLines: 3,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('library.renameSave'),
          onPressed: _busy ? null : _save,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, textAlign: TextAlign.center),
          if (action case final action?) ...[
            const SizedBox(height: 16),
            action,
          ],
        ],
      ),
    ),
  );
}

/// A ring that empties over [duration] around the seconds left, as in
/// Telegram's undo bar (docs/spec-v0.2.md D-24).
class UndoCountdown extends StatelessWidget {
  const UndoCountdown({required this.duration, super.key});

  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onInverseSurface;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: 0),
      duration: duration,
      builder: (context, left, _) {
        final seconds = (left * duration.inMilliseconds / 1000).ceil();
        return SizedBox.square(
          dimension: 28,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: left,
                  strokeWidth: 2.5,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.2),
                ),
              ),
              Text(
                '$seconds',
                key: const Key('library.undoSeconds'),
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      },
    );
  }
}
