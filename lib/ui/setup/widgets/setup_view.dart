import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/services/binaries/binary_installer.dart';
import '../../core/l10n.dart';
import '../view_model/setup_view_model.dart';

/// Blocks the desktop app until the binaries are installed (D-18).
class SetupView extends ConsumerWidget {
  const SetupView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(setupViewModelProvider);
    final vm = ref.read(setupViewModelProvider.notifier);
    final theme = Theme.of(context);

    final List<Widget> body = switch (state) {
      SetupChecking() || SetupReady() => [
        const LinearProgressIndicator(),
        const SizedBox(height: 16),
        Text(l10n.setupChecking),
      ],
      SetupNeeded(:final totalBytes) => [
        Text(l10n.setupNeeded(formatBytes(totalBytes))),
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('setup.install'),
          onPressed: vm.install,
          child: Text(l10n.setupInstall),
        ),
      ],
      SetupInstalling(:final progress) => [
        LinearProgressIndicator(value: progress?.fraction),
        const SizedBox(height: 16),
        if (progress != null) ...[
          Text(switch (progress.phase) {
            InstallPhase.downloading => l10n.setupInstalling(
              progress.binary.label,
            ),
            InstallPhase.unpacking => l10n.setupUnpacking(
              progress.binary.label,
            ),
          }),
          Text(
            l10n.setupProgress(
              formatBytes(progress.receivedBytes),
              formatBytes(progress.totalBytes),
            ),
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 24),
        OutlinedButton(
          key: const Key('setup.cancel'),
          onPressed: vm.cancel,
          child: Text(l10n.cancel),
        ),
      ],
      SetupFailed(:final error) => [
        Icon(Icons.error_outline, color: theme.colorScheme.error, size: 40),
        const SizedBox(height: 8),
        Text(l10n.setupFailed, style: theme.textTheme.titleMedium),
        Text(l10n.errorMessage(error)),
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('setup.retry'),
          onPressed: vm.check,
          child: Text(l10n.retry),
        ),
      ],
    };

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.setupTitle, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 24),
                ...body,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
