import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/config/providers.dart';
import 'package:ftube/data/repositories/settings_repository.dart';
import 'package:ftube/data/services/android/storage_permission_service.dart';
import 'package:ftube/ui/permission/view_model/permission_view_model.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestEnv env;
  late ProviderContainer container;

  PermissionState state() => container.read(permissionViewModelProvider);
  PermissionViewModel vm() =>
      container.read(permissionViewModelProvider.notifier);
  bool storedDone() =>
      container.read(settingsRepositoryProvider).permissionPromptDone;

  Future<void> start([Map<String, Object> prefs = const {}]) async {
    container = await env.container(prefs);
    container.read(permissionViewModelProvider);
    await pumpEventQueue();
  }

  void access(StorageAccess status, {StorageAccess? request}) {
    when(() => env.storage.status()).thenAnswer((_) async => status);
    when(() => env.storage.request())
        .thenAnswer((_) async => request ?? status);
  }

  test('never shows on desktop', () async {
    env = TestEnv.desktop();
    await start();
    expect(state().showPrompt, isFalse);
    await vm().refresh();
    await vm().grant();
    expect(state().access, isNull);
  });

  group('android', () {
    setUp(() => env = TestEnv.android());

    test('is not shown while checking', () {
      expect(const PermissionState().showPrompt, isFalse);
    });

    test('granted access skips the screen for good', () async {
      access(StorageAccess.granted);
      await start();
      expect(state().showPrompt, isFalse);
      expect(storedDone(), isTrue);
    });

    test('shows when access is missing on first run', () async {
      access(StorageAccess.denied);
      await start();
      expect(state().access, StorageAccess.denied);
      expect(state().showPrompt, isTrue);
    });

    test('is not shown again after the first run', () async {
      access(StorageAccess.denied);
      await start({SettingsRepository.permissionPromptKey: true});
      expect(state().showPrompt, isFalse);
    });

    test('grant asks and ends the screen when granted', () async {
      access(StorageAccess.denied, request: StorageAccess.granted);
      await start();
      await vm().grant();
      expect(state().showPrompt, isFalse);
      expect(storedDone(), isTrue);
    });

    test('grant keeps the screen when denied', () async {
      access(StorageAccess.denied);
      await start();
      await vm().grant();
      expect(state().showPrompt, isTrue);
      verifyNever(() => env.storage.openSettings());
    });

    test('grant opens settings when Android blocks the request', () async {
      access(StorageAccess.permanentlyDenied);
      await start();
      await vm().grant();
      verify(() => env.storage.openSettings()).called(1);
      expect(state().showPrompt, isTrue);

      // Back from settings with access on.
      access(StorageAccess.granted);
      await vm().refresh();
      expect(state().showPrompt, isFalse);
    });

    test('later skips the screen', () async {
      access(StorageAccess.denied);
      await start();
      await vm().later();
      expect(state().showPrompt, isFalse);
      expect(storedDone(), isTrue);
    });
  });
}
