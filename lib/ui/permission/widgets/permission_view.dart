import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/services/android/storage_permission_service.dart';
import '../../core/l10n.dart';
import '../view_model/permission_view_model.dart';

/// Android first run: explains and asks for "All files access" (D-13).
class PermissionView extends ConsumerStatefulWidget {
  const PermissionView({super.key});

  @override
  ConsumerState<PermissionView> createState() => _PermissionViewState();
}

class _PermissionViewState extends ConsumerState<PermissionView> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(permissionViewModelProvider.notifier).refresh(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final state = ref.watch(permissionViewModelProvider);
    final vm = ref.read(permissionViewModelProvider.notifier);
    final blocked = state.access == StorageAccess.permanentlyDenied;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.folder_open,
                  size: 56,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.permissionTitle,
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(l10n.permissionBody, textAlign: TextAlign.center),
                if (blocked) ...[
                  const SizedBox(height: 12),
                  Text(
                    l10n.permissionBlocked,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  key: const Key('permission.grant'),
                  onPressed: vm.grant,
                  child: Text(
                    blocked ? l10n.permissionOpenSettings : l10n.storageGrant,
                  ),
                ),
                TextButton(
                  key: const Key('permission.later'),
                  onPressed: vm.later,
                  child: Text(l10n.permissionLater),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
