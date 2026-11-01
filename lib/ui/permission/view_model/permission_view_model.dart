import 'dart:async';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../config/providers.dart';
import '../../../data/services/android/storage_permission_service.dart';

part 'permission_view_model.freezed.dart';
part 'permission_view_model.g.dart';

/// The Android first-run screen for "All files access" (D-13).
@freezed
abstract class PermissionState with _$PermissionState {
  const factory PermissionState({
    /// Null while checking, and on desktop.
    StorageAccess? access,

    /// The user went past the screen once, granted or not.
    @Default(false) bool promptDone,
  }) = _PermissionState;

  const PermissionState._();

  /// Whether the first-run screen still has to be shown.
  bool get showPrompt =>
      !promptDone && access != null && access != StorageAccess.granted;
}

@Riverpod(keepAlive: true)
class PermissionViewModel extends _$PermissionViewModel {
  @override
  PermissionState build() {
    if (ref.watch(storagePermissionServiceProvider) == null) {
      return const PermissionState(promptDone: true);
    }
    unawaited(refresh());
    return PermissionState(
      promptDone: ref.read(settingsRepositoryProvider).permissionPromptDone,
    );
  }

  /// Re-reads the access, for example after the user returns from system
  /// settings. Granting it ends the first-run screen.
  Future<void> refresh() async {
    final storage = ref.read(storagePermissionServiceProvider);
    if (storage == null) return;
    final access = await storage.status();
    if (!ref.mounted) return;
    state = state.copyWith(access: access);
    if (access == StorageAccess.granted) await _done();
  }

  /// Asks for access, or opens the app settings when Android will no
  /// longer show the request.
  Future<void> grant() async {
    final storage = ref.read(storagePermissionServiceProvider);
    if (storage == null) return;
    final access = await storage.request();
    if (!ref.mounted) return;
    state = state.copyWith(access: access);
    if (access == StorageAccess.granted) {
      await _done();
    } else if (access == StorageAccess.permanentlyDenied) {
      await storage.openSettings();
    }
  }

  /// Skips the screen. Downloads stay blocked until access is granted.
  Future<void> later() => _done();

  Future<void> _done() async {
    if (state.promptDone) return;
    await ref.read(settingsRepositoryProvider).markPermissionPromptDone();
    if (ref.mounted) state = state.copyWith(promptDone: true);
  }
}
