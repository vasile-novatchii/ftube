import 'package:flutter/material.dart';

import '../../../domain/models/models.dart';
import '../../core/l10n.dart';

/// A fetched playlist as a checklist (spec-v0.5 section 3). Private and
/// deleted videos are greyed out; a channel tab opens like a new link.
/// The list folds away (D-84), and videos already in the queue show their
/// status instead of a checkbox (D-83).
class PlaylistPanel extends StatelessWidget {
  const PlaylistPanel({
    required this.playlist,
    required this.selected,
    required this.statusOf,
    required this.open,
    required this.onToggleList,
    required this.onToggle,
    required this.onOpen,
    required this.onSelectAll,
    required this.onSelectNone,
    super.key,
  });

  final PlaylistInfo playlist;
  final Set<int> selected;

  /// The queue status of a video link, or null when it isn't queued.
  final JobStatus? Function(String url) statusOf;

  /// Whether the rows are shown.
  final bool open;
  final VoidCallback onToggleList;
  final ValueChanged<int> onToggle;
  final ValueChanged<int> onOpen;
  final VoidCallback onSelectAll;
  final VoidCallback onSelectNone;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    final entries = playlist.entries;
    final hasVideos = entries.any((e) => e.downloadable);
    final total = playlist.totalCount;
    final picked = [
      for (var i = 0; i < entries.length; i++)
        if (selected.contains(i) &&
            entries[i].downloadable &&
            statusOf(entries[i].url) == null)
          i,
    ].length;
    final subtitle = [
      ?playlist.uploader,
      if (total != null || !playlist.truncated)
        l10n.playlistVideos(total ?? entries.length),
      if (hasVideos) l10n.playlistSelected(picked),
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          playlist.title,
          key: const Key('playlist.title'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium,
        ),
        if (subtitle.isNotEmpty)
          Text(subtitle, style: theme.textTheme.bodySmall?.merge(muted)),
        if (playlist.truncated)
          Text(
            total == null
                ? l10n.playlistShowingFirst(entries.length)
                : l10n.playlistShowing(entries.length, total),
            key: const Key('playlist.truncated'),
            style: theme.textTheme.bodySmall?.merge(muted),
          ),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              key: const Key('playlist.toggle'),
              onPressed: onToggleList,
              icon: Icon(open ? Icons.expand_less : Icons.expand_more),
              label: Text(
                open ? l10n.playlistHideVideos : l10n.playlistShowVideos,
              ),
            ),
            if (open && hasVideos) ...[
              TextButton(
                key: const Key('playlist.all'),
                onPressed: onSelectAll,
                child: Text(l10n.playlistSelectAll),
              ),
              TextButton(
                key: const Key('playlist.none'),
                onPressed: onSelectNone,
                child: Text(l10n.playlistSelectNone),
              ),
            ],
          ],
        ),
        if (open)
          for (var i = 0; i < entries.length; i++)
            _row(context, i, entries[i], muted),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    int i,
    PlaylistEntry entry,
    TextStyle muted,
  ) {
    final title = Text(
      entry.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
    final duration = switch (entry.duration) {
      final d? => Text(formatDuration(d), style: muted),
      null => null,
    };
    if (entry.isList) {
      return ListTile(
        key: Key('playlist.entry.$i'),
        contentPadding: EdgeInsets.zero,
        dense: true,
        leading: const Icon(Icons.playlist_play),
        title: title,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => onOpen(i),
      );
    }
    if (entry.unavailable) {
      return ListTile(
        key: Key('playlist.entry.$i'),
        contentPadding: EdgeInsets.zero,
        dense: true,
        enabled: false,
        leading: const Icon(Icons.block),
        title: title,
        subtitle: Text(context.l10n.playlistUnavailable),
      );
    }
    if (statusOf(entry.url) case final status?) {
      return CheckboxListTile(
        key: Key('playlist.entry.$i'),
        contentPadding: EdgeInsets.zero,
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        value: true,
        onChanged: null,
        title: title,
        subtitle: Text(context.l10n.activeLabel(status), style: muted),
      );
    }
    return CheckboxListTile(
      key: Key('playlist.entry.$i'),
      contentPadding: EdgeInsets.zero,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      value: selected.contains(i),
      onChanged: (_) => onToggle(i),
      title: title,
      subtitle: duration,
    );
  }
}
