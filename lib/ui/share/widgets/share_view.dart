import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/download_starter.dart';
import '../../core/l10n.dart';
import '../../core/media_info_card.dart';
import '../view_model/share_view_model.dart';

/// The share popup over the sharing app (spec-v0.4-share D-53). Tapping
/// outside it closes it.
class ShareView extends ConsumerWidget {
  const ShareView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Stack(
    children: [
      Positioned.fill(
        child: GestureDetector(
          key: const Key('share.scrim'),
          behavior: HitTestBehavior.opaque,
          onTap: () =>
              unawaited(ref.read(shareSessionProvider.notifier).close()),
          child: const ColoredBox(color: Colors.black54),
        ),
      ),
      Center(
        child: Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: const SingleChildScrollView(
              padding: EdgeInsets.all(20),
              child: _Content(),
            ),
          ),
        ),
      ),
    ],
  );
}

class _Content extends ConsumerWidget {
  const _Content();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final state = ref.watch(shareViewModelProvider);
    final vm = ref.read(shareViewModelProvider.notifier);
    final session = ref.read(shareSessionProvider.notifier);

    Widget close(String label) => TextButton(
      key: const Key('share.close'),
      onPressed: () => unawaited(session.close()),
      child: Text(label),
    );
    final openApp = FilledButton(
      key: const Key('share.openApp'),
      onPressed: () => unawaited(session.openApp()),
      child: Text(l10n.shareOpenApp),
    );

    if (state.url == null || state.noAccess) {
      return _Layout(
        body: Text(
          state.url == null ? l10n.shareNoLink : l10n.shareNoAccess,
          key: const Key('share.message'),
        ),
        actions: [close(l10n.shareClose), openApp],
      );
    }
    final error = state.error;
    return _Layout(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MediaInfoCard(info: state.shown!, titleKey: const Key('share.title')),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            key: const Key('share.tabs'),
            segments: [
              ButtonSegment(
                value: false,
                icon: const Icon(Icons.movie_outlined),
                label: Text(l10n.shareVideo),
              ),
              ButtonSegment(
                value: true,
                icon: const Icon(Icons.music_note_outlined),
                label: Text(l10n.shareAudio),
              ),
            ],
            selected: {state.audio},
            onSelectionChanged: (s) => vm.selectTab(audio: s.single),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in state.presets)
                ChoiceChip(
                  key: Key('share.preset.${preset.name}'),
                  label: Text(l10n.presetLabel(preset)),
                  selected: state.formatId == null && state.preset == preset,
                  onSelected: (_) => vm.selectPreset(preset),
                ),
            ],
          ),
          if (state.fetching) ...[
            const SizedBox(height: 12),
            Text(
              l10n.shareLoadingFormats,
              key: const Key('share.loading'),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            const LinearProgressIndicator(),
          ] else if (state.formats.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(l10n.shareFormat, style: theme.textTheme.titleSmall),
            DropdownButton<String?>(
              key: const Key('share.format'),
              value: state.selectedFormat?.id,
              isExpanded: true,
              items: [
                DropdownMenuItem(child: Text(l10n.shareFormatAuto)),
                for (final f in state.formats)
                  DropdownMenuItem(
                    value: f.id,
                    child: Text(
                      l10n.formatLabel(f),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: vm.selectFormat,
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(
              error is NoDownloadFolder
                  ? l10n.homeNoFolder
                  : l10n.errorMessage(error),
              key: const Key('share.error'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        close(l10n.cancel),
        if (error != null)
          OutlinedButton(
            key: const Key('share.retry'),
            onPressed: () => unawaited(vm.retry()),
            child: Text(l10n.retry),
          ),
        FilledButton.icon(
          key: const Key('share.download'),
          onPressed: state.canDownload
              ? () => unawaited(vm.download(toast: l10n.shareStarted))
              : null,
          icon: state.queuing
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download),
          label: Text(l10n.homeDownload),
        ),
      ],
    );
  }
}

class _Layout extends StatelessWidget {
  const _Layout({required this.body, required this.actions});

  final Widget body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      body,
      const SizedBox(height: 16),
      Wrap(alignment: WrapAlignment.end, spacing: 8, children: actions),
    ],
  );
}
