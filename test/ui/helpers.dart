import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:ftube/config/providers.dart';
import 'package:ftube/data/services/android/ffmpeg_kit_runner.dart';
import 'package:ftube/data/services/android/storage_permission_service.dart';
import 'package:ftube/data/services/binaries/binary_catalog.dart';
import 'package:ftube/data/services/binaries/binary_installer.dart';
import 'package:ftube/data/services/binary_service.dart';
import 'package:ftube/data/services/prefs_service.dart';
import 'package:ftube/ui/core/l10n.dart';
import 'package:ftube/ui/core/theme.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockBinaryService extends Mock implements BinaryService {}

class MockBinaryInstaller extends Mock implements BinaryInstaller {}

class MockStorage extends Mock implements StoragePermissionService {}

class MockFfmpegRunner extends Mock implements FfmpegRunner {}

/// Prefs backed by an in-memory map.
Future<PrefsService> testPrefs([Map<String, Object> values = const {}]) {
  SharedPreferences.setMockInitialValues(values);
  return PrefsService.load();
}

CatalogEntry entry(Binary binary, int size) => CatalogEntry(
  binary: binary,
  os: DesktopOs.macos,
  arch: CpuArch.arm64,
  url: Uri.parse('https://example.com/${binary.label}.gz'),
  sha256: 'x' * 64,
  size: size,
);

/// Desktop or Android fakes, with every service answering by default.
class TestEnv {
  TestEnv.desktop() : platform = AppPlatform.desktop {
    when(() => binaries.version(Binary.ytDlp)).thenAnswer((_) async => '1.0');
    when(() => binaries.version(Binary.ffmpeg)).thenAnswer((_) async => '9.0');
    when(() => installer.missing()).thenAnswer((_) async => []);
  }

  TestEnv.android() : platform = AppPlatform.android {
    when(() => ffmpeg.version()).thenAnswer((_) async => '7.1');
    when(() => storage.status()).thenAnswer((_) async => StorageAccess.granted);
    when(() => storage.openSettings()).thenAnswer((_) async => true);
  }

  final AppPlatform platform;
  final binaries = MockBinaryService();
  final installer = MockBinaryInstaller();
  final storage = MockStorage();
  final ffmpeg = MockFfmpegRunner();
  final pickedDirs = <String?>[];
  final pickerCalls = <String?>[];
  Completer<String?>? defaultDir;

  /// Makes the default folder and app version lookups fail.
  bool failLookups = false;

  List<Override> overrides(PrefsService prefs) => [
    appPlatformProvider.overrideWithValue(platform),
    prefsServiceProvider.overrideWithValue(prefs),
    appDirsProvider.overrideWithValue(
      AppDirs(support: Directory('/support'), temp: Directory('/tmp/ftube')),
    ),
    binaryServiceProvider.overrideWithValue(
      platform.isDesktop ? binaries : null,
    ),
    binaryInstallerProvider.overrideWithValue(
      platform.isDesktop ? installer : null,
    ),
    storagePermissionServiceProvider.overrideWithValue(
      platform.isDesktop ? null : storage,
    ),
    ffmpegRunnerProvider.overrideWithValue(ffmpeg),
    defaultDownloadDirProvider.overrideWith((ref) async {
      if (failLookups) throw StateError('no downloads folder');
      return defaultDir?.future ?? '/home/me/Downloads/Ftube';
    }),
    appVersionProvider.overrideWith((ref) async {
      if (failLookups) throw StateError('no package info');
      return '0.1.0';
    }),
    directoryPickerProvider.overrideWithValue(({initialDirectory}) async {
      pickerCalls.add(initialDirectory);
      return pickedDirs.isEmpty ? null : pickedDirs.removeAt(0);
    }),
  ];

  Future<ProviderContainer> container([
    Map<String, Object> prefs = const {},
  ]) async =>
      ProviderContainer.test(overrides: overrides(await testPrefs(prefs)));
}

/// Wraps [child] in a localized, themed MaterialApp.
Widget localized(
  Widget child, {
  Locale locale = const Locale('en'),
  ThemeMode themeMode = ThemeMode.light,
}) => MaterialApp(
  theme: AppTheme.light(),
  darkTheme: AppTheme.dark(),
  themeMode: themeMode,
  locale: locale,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: child,
);

/// Loads [PrefsService] again without resetting the mock values, as a new
/// app start would.
Future<PrefsService> reloadPrefs() => PrefsService.load();
