import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/config/providers.dart';
import 'package:ftube/data/repositories/settings_repository.dart';
import 'package:ftube/data/services/android/storage_permission_service.dart';
import 'package:ftube/data/services/binary_service.dart';
import 'package:ftube/domain/exceptions/ftube_exception.dart';
import 'package:ftube/domain/models/app_settings.dart';
import 'package:ftube/domain/models/quality_preset.dart';
import 'package:ftube/ui/library/view_model/library_view_model.dart';
import 'package:ftube/ui/settings/view_model/settings_view_model.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers.dart';
import '../library/library_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestEnv env;
  late ProviderContainer container;

  Future<SettingsViewModel> start([
    Map<String, Object> prefs = const {},
  ]) async {
    container = await env.container(prefs);
    container.listen(settingsViewModelProvider, (_, _) {});
    await pumpEventQueue();
    return container.read(settingsViewModelProvider.notifier);
  }

  SettingsState state() => container.read(settingsViewModelProvider);
  AppSettings saved() => container.read(settingsRepositoryProvider).current;

  group('desktop', () {
    setUp(() => env = TestEnv.desktop());

    test('loads the versions, folder and app version', () async {
      env.defaultDir = Completer();
      container = await env.container();
      container.listen(settingsViewModelProvider, (_, _) {});
      expect(state().loadingVersions, isTrue);
      expect(state().downloadDir, isNull);

      env.defaultDir!.complete('/home/me/Downloads/Ftube');
      await pumpEventQueue();
      expect(state().isDesktop, isTrue);
      expect(state().loadingVersions, isFalse);
      expect((state().ytDlpVersion, state().ffmpegVersion), ('1.0', '9.0'));
      expect(state().downloadDir, '/home/me/Downloads/Ftube');
      expect(state().usesDefaultDir, isTrue);
      expect(state().appVersion, '0.1.0');
      expect(state().storageAccess, isNull);
      expect(state().canChangeDownloadDir, isTrue);
    });

    test('a missing default folder or app version leaves them null', () async {
      env.failLookups = true;
      await start();
      expect(state().defaultDownloadDir, isNull);
      expect(state().appVersion, isNull);
      expect(state().loadingVersions, isFalse);
    });

    test('setters save and the state follows the repository', () async {
      final vm = await start();
      await vm.setTheme(ThemePreference.dark);
      await vm.setLanguage(AppLanguage.ro);
      await vm.setDefaultPreset(QualityPreset.p720);
      await vm.setConcurrentDownloads(3);
      const expected = AppSettings(
        theme: ThemePreference.dark,
        language: AppLanguage.ro,
        defaultPreset: QualityPreset.p720,
        concurrentDownloads: 3,
      );
      expect(saved(), expected);
      expect(state().settings, expected);
      expect(container.read(currentSettingsProvider), expected);
    });

    test('concurrent downloads are clamped to 1..3', () async {
      final vm = await start();
      await vm.setConcurrentDownloads(0);
      expect(saved().concurrentDownloads, 1);
      await vm.setConcurrentDownloads(8);
      expect(saved().concurrentDownloads, 3);
    });

    test('custom is not a default preset', () async {
      final vm = await start();
      expect(
        () => vm.setDefaultPreset(QualityPreset.custom),
        throwsArgumentError,
      );
    });

    test('picks a folder, keeps it on cancel, and resets it', () async {
      final vm = await start();
      env.pickedDirs.addAll(['/videos', null, '  ']);
      await vm.pickDownloadDir();
      expect(state().downloadDir, '/videos');
      expect(state().usesDefaultDir, isFalse);
      await vm.pickDownloadDir();
      await vm.pickDownloadDir();
      expect(saved().downloadDir, '/videos');
      expect(env.pickerCalls, [
        '/home/me/Downloads/Ftube',
        '/videos',
        '/videos',
      ]);

      await vm.resetDownloadDir();
      expect(saved().downloadDir, isNull);
      expect(state().downloadDir, '/home/me/Downloads/Ftube');
    });

    test('updateYtDlp reports the new version', () async {
      final done = Completer<String?>();
      when(() => env.binaries.updateYtDlp()).thenAnswer((_) => done.future);
      final vm = await start();
      final first = vm.updateYtDlp();
      expect(state().ytDlpUpdate, UpdateStatus.running);
      await vm.updateYtDlp(); // ignored while running
      done.complete('2.0');
      await first;
      expect(state().ytDlpUpdate, UpdateStatus.done);
      expect(state().ytDlpVersion, '2.0');
      verify(() => env.binaries.updateYtDlp()).called(1);
    });

    test(
      'versions are read once per session and again after an update',
      () async {
        when(() => env.binaries.updateYtDlp()).thenAnswer((_) async => '2.0');
        container = await env.container();
        Future<void> visit() async {
          final sub = container.listen(settingsViewModelProvider, (_, _) {});
          await pumpEventQueue();
          sub.close();
          await pumpEventQueue();
        }

        await visit();
        await visit();
        verify(() => env.binaries.version(Binary.ytDlp)).called(1);
        verify(() => env.binaries.version(Binary.ffmpeg)).called(1);

        final sub = container.listen(settingsViewModelProvider, (_, _) {});
        await container.read(settingsViewModelProvider.notifier).updateYtDlp();
        sub.close();
        await pumpEventQueue();
        await visit();
        verify(() => env.binaries.version(Binary.ytDlp)).called(1);
      },
    );

    test('a failed version lookup is retried on the next visit', () async {
      var calls = 0;
      when(() => env.binaries.version(Binary.ytDlp)).thenAnswer((_) async {
        if (calls++ == 0) throw const ProcessFailed(1, 'boom');
        return '1.0';
      });
      container = await env.container();
      final first = container.listen(settingsViewModelProvider, (_, _) {});
      await pumpEventQueue();
      expect(state().loadingVersions, isFalse);
      expect(state().ytDlpVersion, isNull);
      first.close();
      await pumpEventQueue();

      container.listen(settingsViewModelProvider, (_, _) {});
      await pumpEventQueue();
      expect(state().ytDlpVersion, '1.0');
    });

    test('updateYtDlp keeps the old version when none is reported', () async {
      when(() => env.binaries.updateYtDlp()).thenAnswer((_) async => null);
      final vm = await start();
      await vm.updateYtDlp();
      expect(state().ytDlpVersion, '1.0');
    });

    test('updateYtDlp reports failures', () async {
      when(() => env.binaries.updateYtDlp())
          .thenThrow(const ProcessFailed(1, 'boom'));
      final vm = await start();
      await vm.updateYtDlp();
      expect(state().ytDlpUpdate, UpdateStatus.failed);
      expect(state().ytDlpUpdateError, isA<ProcessFailed>());
    });

    group('clearAppData', () {
      test(
        'empties the cache and the library, keeps files and settings',
        () async {
          final disk = Disk(env.files);
          final vm = await start({SettingsRepository.themeKey: 'dark'});
          container.listen(libraryViewModelProvider, (_, _) {});
          await pumpEventQueue();
          expect(container.read(libraryViewModelProvider).items, hasLength(3));

          await vm.clearAppData();
          expect(state().clearData, UpdateStatus.done);
          verify(() => env.files.emptyDir(dirAt('/tmp/ftube'))).called(1);
          expect(container.read(libraryViewModelProvider).items, isEmpty);
          expect(disk.items, hasLength(3), reason: 'files stay on disk');
          expect(saved().theme, ThemePreference.dark);
          verifyNever(() => env.files.trash(any()));

          // A new download still shows.
          disk.add('d.mp4', 5, DateTime(2026, 2));
          await container.read(libraryViewModelProvider.notifier).load();
          expect(
            container.read(libraryViewModelProvider).items.single.name,
            'd.mp4',
          );
        },
      );

      test('is blocked while a download is queued or running', () async {
        final vm = await start();
        expect(state().canClearData, isTrue);
        container
            .read(downloadRepositoryProvider)
            .enqueue(
              url: 'https://youtu.be/abc',
              title: 'Song',
              preset: QualityPreset.best,
              outDir: Directory('/out'),
            );
        expect(state().downloading, isTrue);
        expect(state().canClearData, isFalse);
        await vm.clearAppData();
        expect(state().clearData, UpdateStatus.idle);
        verifyNever(() => env.files.emptyDir(any()));
      });

      test('reports a failure', () async {
        when(() => env.files.emptyDir(any()))
            .thenThrow(const FileError('busy'));
        final vm = await start();
        await vm.clearAppData();
        expect(state().clearData, UpdateStatus.failed);
        expect(state().clearDataError, isA<FileError>());
        expect(state().canClearData, isTrue);
      });
    });

    test('storage commands do nothing on desktop', () async {
      final vm = await start();
      await vm.refreshStorageAccess();
      await vm.requestStorageAccess();
      expect(state().storageAccess, isNull);
    });

    test('loads stored settings', () async {
      await start({SettingsRepository.themeKey: 'light'});
      expect(state().settings.theme, ThemePreference.light);
    });
  });

  group('android', () {
    setUp(() => env = TestEnv.android());

    test('shows yt-dlp, the bundled ffmpeg and the storage access', () async {
      await start();
      expect(state().isDesktop, isFalse);
      expect(state().ytDlpVersion, '2026.10.26');
      expect(state().ffmpegVersion, '7.1');
      expect(state().storageAccess, StorageAccess.granted);
      expect(state().canChangeDownloadDir, isFalse);
    });

    test('pickDownloadDir does nothing', () async {
      final vm = await start();
      await vm.pickDownloadDir();
      expect(env.pickerCalls, isEmpty);
    });

    test('updateYtDlp updates through the bridge', () async {
      final vm = await start();
      await vm.updateYtDlp();
      verify(() => env.ytDlp.update()).called(1);
      expect(state().ytDlpUpdate, UpdateStatus.done);
      expect(state().ytDlpVersion, '2026.11.01');
    });

    test('updateYtDlp reports a bridge failure', () async {
      when(() => env.ytDlp.update()).thenThrow(const Network('offline'));
      final vm = await start();
      await vm.updateYtDlp();
      expect(state().ytDlpUpdate, UpdateStatus.failed);
    });

    test('an unreadable yt-dlp version shows as unknown', () async {
      when(() => env.ytDlp.version()).thenThrow(const Unexpected('boom'));
      await start();
      expect(state().ytDlpVersion, isNull);
    });

    test('refreshStorageAccess re-reads the status', () async {
      final vm = await start();
      when(() => env.storage.status())
          .thenAnswer((_) async => StorageAccess.denied);
      await vm.refreshStorageAccess();
      expect(state().storageAccess, StorageAccess.denied);
    });

    test('requestStorageAccess asks for access', () async {
      when(() => env.storage.status())
          .thenAnswer((_) async => StorageAccess.denied);
      when(() => env.storage.request())
          .thenAnswer((_) async => StorageAccess.granted);
      final vm = await start();
      await vm.requestStorageAccess();
      expect(state().storageAccess, StorageAccess.granted);
      verifyNever(() => env.storage.openSettings());
    });

    test('requestStorageAccess opens settings when blocked', () async {
      when(() => env.storage.status())
          .thenAnswer((_) async => StorageAccess.permanentlyDenied);
      when(() => env.storage.request())
          .thenAnswer((_) async => StorageAccess.permanentlyDenied);
      final vm = await start();
      await vm.requestStorageAccess();
      verify(() => env.storage.openSettings()).called(1);
      expect(state().storageAccess, StorageAccess.permanentlyDenied);
    });
  });
}
