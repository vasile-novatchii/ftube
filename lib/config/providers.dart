import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/repositories/settings_repository.dart';
import '../data/services/android/android_media_service.dart';
import '../data/services/android/ffmpeg_kit_runner.dart';
import '../data/services/android/storage_permission_service.dart';
import '../data/services/android/youtube_source.dart';
import '../data/services/binaries/binary_catalog.dart';
import '../data/services/binaries/binary_installer.dart';
import '../data/services/binary_service.dart';
import '../data/services/desktop/desktop_media_service.dart';
import '../data/services/media_service.dart';
import '../data/services/prefs_service.dart';
import '../data/services/process_runner.dart';
import '../domain/models/app_settings.dart';

part 'providers.g.dart';

/// The two app flavours. Desktop runs binaries, Android uses libraries.
enum AppPlatform {
  android,
  desktop;

  static AppPlatform get current =>
      Platform.isAndroid ? AppPlatform.android : AppPlatform.desktop;

  bool get isDesktop => this == desktop;
}

/// Folders resolved once at startup.
final class AppDirs {
  const AppDirs({required this.support, required this.temp});

  static Future<AppDirs> resolve() async => AppDirs(
    support: await getApplicationSupportDirectory(),
    temp: Directory(p.join((await getTemporaryDirectory()).path, 'ftube')),
  );

  final Directory support;

  /// Parent of the per-job temp folders.
  final Directory temp;
}

/// Name of the folder created inside the user's Downloads (D-9).
const downloadsFolderName = 'Ftube';

@Riverpod(keepAlive: true)
AppPlatform appPlatform(Ref ref) => AppPlatform.current;

/// Overridden in `main` with the loaded prefs.
@Riverpod(keepAlive: true)
PrefsService prefsService(Ref ref) =>
    throw UnimplementedError('prefsServiceProvider must be overridden');

/// Overridden in `main` with the resolved folders.
@Riverpod(keepAlive: true)
AppDirs appDirs(Ref ref) =>
    throw UnimplementedError('appDirsProvider must be overridden');

/// The desktop binaries catalog. Overridden in `main` on desktop.
@Riverpod(keepAlive: true)
BinaryCatalog binaryCatalog(Ref ref) =>
    throw UnimplementedError('binaryCatalogProvider must be overridden');

@Riverpod(keepAlive: true)
SettingsRepository settingsRepository(Ref ref) {
  final repo = SettingsRepository(ref.watch(prefsServiceProvider));
  ref.onDispose(repo.dispose);
  return repo;
}

/// The saved settings, updated whenever [SettingsRepository] saves.
@Riverpod(keepAlive: true)
class CurrentSettings extends _$CurrentSettings {
  @override
  AppSettings build() {
    final repo = ref.watch(settingsRepositoryProvider);
    final sub = repo.changes.listen((s) => state = s);
    ref.onDispose(sub.cancel);
    return repo.current;
  }
}

@Riverpod(keepAlive: true)
ProcessRunner processRunner(Ref ref) => const SystemProcessRunner();

/// Null on Android.
@Riverpod(keepAlive: true)
BinaryService? binaryService(Ref ref) {
  final os = DesktopOs.current;
  if (os == null || !ref.watch(appPlatformProvider).isDesktop) return null;
  return BinaryService(
    os: os,
    binDir: BinaryService.binDirFor(
      ref.watch(appDirsProvider).support,
      environment: Platform.environment,
    ),
    runner: ref.watch(processRunnerProvider),
  );
}

/// Null on Android.
@Riverpod(keepAlive: true)
BinaryInstaller? binaryInstaller(Ref ref) {
  final binaries = ref.watch(binaryServiceProvider);
  if (binaries == null) return null;
  return BinaryInstaller(
    catalog: ref.watch(binaryCatalogProvider),
    os: binaries.os,
    arch: CpuArch.current,
    binDir: binaries.binDir,
    runner: ref.watch(processRunnerProvider),
  );
}

/// Null on desktop.
@Riverpod(keepAlive: true)
StoragePermissionService? storagePermissionService(Ref ref) =>
    ref.watch(appPlatformProvider).isDesktop
    ? null
    : const StoragePermissionService();

@Riverpod(keepAlive: true)
FfmpegRunner ffmpegRunner(Ref ref) => const KitFfmpegRunner();

@Riverpod(keepAlive: true)
MediaService mediaService(Ref ref) {
  final temp = ref.watch(appDirsProvider).temp;
  final binaries = ref.watch(binaryServiceProvider);
  if (binaries != null) {
    return DesktopMediaService(
      binaries: binaries,
      runner: ref.watch(processRunnerProvider),
      tempRoot: temp,
    );
  }
  final source = ExplodeYoutubeSource();
  ref.onDispose(source.close);
  return AndroidMediaService(
    source: source,
    ffmpeg: ref.watch(ffmpegRunnerProvider),
    tempRoot: temp,
    storage: ref.watch(storagePermissionServiceProvider),
  );
}

/// `Downloads/Ftube` for this platform (D-9), or null when unknown.
@Riverpod(keepAlive: true)
Future<String?> defaultDownloadDir(Ref ref) async {
  final storage = ref.watch(storagePermissionServiceProvider);
  try {
    if (storage != null) return (await storage.downloadsDir()).path;
    final downloads = await getDownloadsDirectory();
    return downloads == null
        ? null
        : p.join(downloads.path, downloadsFolderName);
  } on Object {
    return null;
  }
}

@Riverpod(keepAlive: true)
Future<String> appVersion(Ref ref) async =>
    (await PackageInfo.fromPlatform()).version;

/// Asks the user for a folder. Returns null when they cancel.
typedef DirectoryPicker = Future<String?> Function({String? initialDirectory});

@Riverpod(keepAlive: true)
DirectoryPicker directoryPicker(Ref ref) =>
    ({initialDirectory}) =>
        getDirectoryPath(initialDirectory: initialDirectory);
