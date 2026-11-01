import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/models.dart';
import '../../core/l10n.dart';
import '../view_model/queue_view_model.dart';

/// The download queue, shown below the Home form.
class QueueView extends ConsumerWidget {
  const QueueView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(queueViewModelProvider);
    final vm = ref.read(queueViewModelProvider.notifier);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.queueTitle(state.jobs.length),
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (state.hasCompleted)
              TextButton(
                key: const Key('queue.clear'),
                onPressed: vm.clearFinished,
                child: Text(l10n.queueClearDone),
              ),
          ],
        ),
        if (state.jobs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              l10n.queueEmpty,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final job in state.jobs.reversed)
          _JobRow(key: ValueKey(job.id), job: job, canOpen: state.canOpen),
      ],
    );
  }
}

class _JobRow extends ConsumerWidget {
  const _JobRow({required this.job, required this.canOpen, super.key});

  final DownloadJob job;
  final bool canOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final vm = ref.read(queueViewModelProvider.notifier);
    final progress = job.progress;
    final running = job.status == JobStatus.running;
    final failed = job.status == JobStatus.failed;
    final id = job.id;

    final details = [
      l10n.jobStatusLabel(job),
      if (running && progress != null) ...[
        if (progress.fraction case final f?) '${(f * 100).floor()}%',
        if (progress.speedBps case final speed? when speed > 0)
          l10n.speedPerSecond(formatBytes(speed.round())),
        if (progress.eta case final eta?) formatDuration(eta),
      ],
    ].join(' · ');

    Future<void> open() async {
      final messenger = ScaffoldMessenger.of(context);
      final error = await vm.open(job);
      if (error != null) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.errorMessage(error))),
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${job.title} · ${_quality(l10n, job.request)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge,
                ),
                if (running) ...[
                  const SizedBox(height: 4),
                  LinearProgressIndicator(value: progress?.fraction),
                ],
                const SizedBox(height: 2),
                Text(
                  details,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: failed
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (job.status == JobStatus.completed &&
              canOpen &&
              job.outputPath != null)
            IconButton(
              key: Key('queue.open.$id'),
              tooltip: l10n.queueOpen,
              icon: const Icon(Icons.open_in_new),
              onPressed: open,
            ),
          if (job.status.canRetry)
            IconButton(
              key: Key('queue.retry.$id'),
              tooltip: l10n.queueRetry,
              icon: const Icon(Icons.refresh),
              onPressed: () => vm.retry(id),
            ),
          if (job.status.canCancel)
            IconButton(
              key: Key('queue.cancel.$id'),
              tooltip: l10n.queueCancel,
              icon: const Icon(Icons.close),
              onPressed: () => vm.cancel(id),
            )
          else
            IconButton(
              key: Key('queue.remove.$id'),
              tooltip: l10n.queueRemove,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => vm.remove(id),
            ),
        ],
      ),
    );
  }

  static String _quality(AppLocalizations l10n, DownloadRequest req) =>
      req.preset == QualityPreset.custom && req.formatId != null
      ? req.formatId!
      : l10n.presetLabel(req.preset);
}
