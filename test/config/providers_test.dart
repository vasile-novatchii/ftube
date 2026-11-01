import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/config/providers.dart';
import 'package:ftube/data/services/android/android_media_service.dart';
import 'package:ftube/data/services/binaries/binary_catalog.dart';
import 'package:ftube/data/services/desktop/desktop_media_service.dart';
import 'package:path/path.dart' as p;

import '../ui/helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> container(AppPlatform platform) async =>
      ProviderContainer.test(
        overrides: [
          appPlatformProvider.overrideWithValue(platform),
          prefsServiceProvider.overrideWithValue(await testPrefs()),
          appDirsProvider.overrideWithValue(
            AppDirs(support: Directory('/support'), temp: Directory('/tmp/x')),
          ),
          binaryCatalogProvider.overrideWithValue(
            const BinaryCatalog(release: 'binaries-r1', entries: []),
          ),
        ],
      );

  test('desktop wires the binaries and the desktop media service', () async {
    final c = await container(AppPlatform.desktop);
    final binaries = c.read(binaryServiceProvider)!;
    expect(
      binaries.binDir.path,
      Platform.environment['FTUBE_BIN_DIR'] ?? p.join('/support', 'bin'),
    );
    expect(c.read(binaryInstallerProvider)!.binDir, binaries.binDir);
    expect(c.read(storagePermissionServiceProvider), isNull);
    expect(c.read(mediaServiceProvider), isA<DesktopMediaService>());
  });

  test('android wires storage and the android media service', () async {
    final c = await container(AppPlatform.android);
    expect(c.read(binaryServiceProvider), isNull);
    expect(c.read(binaryInstallerProvider), isNull);
    expect(c.read(storagePermissionServiceProvider), isNotNull);
    expect(c.read(mediaServiceProvider), isA<AndroidMediaService>());
  });

  test('current settings follow the repository', () async {
    final c = await container(AppPlatform.desktop);
    expect(c.read(currentSettingsProvider).concurrentDownloads, 2);
    await c
        .read(settingsRepositoryProvider)
        .update((s) => s.copyWith(concurrentDownloads: 1));
    expect(c.read(currentSettingsProvider).concurrentDownloads, 1);
  });

  test('the queue follows the concurrency setting', () async {
    final c = await container(AppPlatform.desktop);
    final queue = c.read(downloadRepositoryProvider);
    expect(queue.maxConcurrent, 2);
    await c
        .read(settingsRepositoryProvider)
        .update((s) => s.copyWith(concurrentDownloads: 3));
    expect(queue.maxConcurrent, 3);
  });

  test('the download folder is the custom one, else the default', () async {
    final c = await TestEnv.desktop().container();
    Future<String?> path() async =>
        (await c.read(downloadDirectoryProvider.future))?.path;
    expect(await path(), '/home/me/Downloads/Ftube');
    await c
        .read(settingsRepositoryProvider)
        .update((s) => s.copyWith(downloadDir: '/music'));
    expect(await path(), '/music');

    final env = TestEnv.desktop()..defaultDir = (Completer()..complete(null));
    final none = await env.container();
    expect(await none.read(downloadDirectoryProvider.future), isNull);
  });

  test('library and file system use the platform', () async {
    final desktop = await container(AppPlatform.desktop);
    expect(desktop.read(fileSystemServiceProvider).canReveal, isTrue);
    expect(desktop.read(libraryRepositoryProvider).canReveal, isTrue);
    final android = await container(AppPlatform.android);
    expect(android.read(fileSystemServiceProvider).canReveal, isFalse);
  });

  test('prefs, folders and catalog must be overridden', () {
    final c = ProviderContainer.test();
    expect(() => c.read(prefsServiceProvider), throwsA(anything));
    expect(() => c.read(appDirsProvider), throwsA(anything));
    expect(() => c.read(binaryCatalogProvider), throwsA(anything));
  });

  test('AppPlatform.current is desktop on the test host', () {
    expect(AppPlatform.current, AppPlatform.desktop);
  });
}
