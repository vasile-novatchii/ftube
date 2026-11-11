import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/app_update.dart';
import '../../core/l10n.dart';
import '../../core/markdown_view.dart';
import '../view_model/app_update_view_model.dart';

/// Opens the release page, with a snack bar when no browser could.
Future<void> downloadRelease(
  BuildContext context,
  WidgetRef ref,
  AppRelease release,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final failed = context.l10n.updateOpenFailed;
  final ok = await ref
      .read(appUpdateViewModelProvider.notifier)
      .download(release);
  if (!ok) messenger?.showSnackBar(SnackBar(content: Text(failed)));
}

/// The release notes of [release] with a Download button (D-97).
Future<void> showReleaseNotes(
  BuildContext context,
  WidgetRef ref,
  AppRelease release,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheetContext) => ReleaseNotesSheet(
    release: release,
    onDownload: () => downloadRelease(context, ref, release),
  ),
);

class ReleaseNotesSheet extends StatelessWidget {
  const ReleaseNotesSheet({
    required this.release,
    required this.onDownload,
    super.key,
  });

  final AppRelease release;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final date = release.publishedAt;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (context, controller) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.updateAvailable(release.version),
                        style: theme.textTheme.titleMedium,
                      ),
                      if (date != null)
                        Text(
                          DateFormat.yMMMd(
                            Localizations.localeOf(context).toLanguageTag(),
                          ).format(date.toLocal()),
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                FilledButton(
                  key: const Key('update.notes.download'),
                  onPressed: onDownload,
                  child: Text(l10n.updateDownload),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.all(16),
              children: [
                if (release.notes.isEmpty)
                  Text(l10n.updateNoNotes)
                else
                  MarkdownView(release.notes),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The Settings "Check for updates" tile (D-92).
class UpdateCheckTile extends ConsumerWidget {
  const UpdateCheckTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(appUpdateViewModelProvider);
    final vm = ref.read(appUpdateViewModelProvider.notifier);
    final result = state.manual;
    final subtitle = state.checking
        ? l10n.updateChecking
        : switch (result) {
            null => null,
            UpToDate() => l10n.updateUpToDate,
            UpdateAvailable(:final release) => l10n.updateAvailable(
              release.version,
            ),
            CheckFailed() => l10n.updateCheckFailed,
          };
    final available = switch (result) {
      UpdateAvailable(:final release) when !state.checking => release,
      _ => null,
    };
    return ListTile(
      key: const Key('settings.checkUpdate'),
      enabled: !state.checking,
      title: Text(l10n.updateCheck),
      subtitle: switch ((subtitle, available)) {
        (null, _) => null,
        (final text?, null) => Text(text),
        (final text?, final release?) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  key: const Key('settings.update.notes'),
                  onPressed: () => showReleaseNotes(context, ref, release),
                  child: Text(l10n.updateWhatsNew),
                ),
                FilledButton(
                  key: const Key('settings.update.download'),
                  onPressed: () => downloadRelease(context, ref, release),
                  child: Text(l10n.updateDownload),
                ),
              ],
            ),
          ],
        ),
      },
      onTap: vm.checkNow,
      trailing: state.checking
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
    );
  }
}
