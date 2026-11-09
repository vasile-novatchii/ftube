import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/repositories/download_repository.dart';
import '../data/repositories/library_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/services/android/android_file_launcher.dart';
import '../data/services/android/android_media_service.dart';
import '../data/services/android/background_downloads.dart';
import '../data/services/android/ffmpeg_kit_runner.dart';
import '../data/services/android/notification_permission.dart';
import '../data/services/android/storage_permission_service.dart';
import '../data/services/android/yt_dlp_bridge.dart';
import '../data/services/binaries/binary_catalog.dart';
import '../data/services/binaries/binary_installer.dart';
import '../data/services/binary_service.dart';
import '../data/services/desktop/desktop_media_service.dart';
import '../data/services/file_system_service.dart';
import '../data/services/media_service.dart';
import '../data/services/prefs_service.dart';
import '../data/services/process_runner.dart';
import '../data/services/removed_items_store.dart';
import '../domain/models/app_settings.dart';
import '../l10n/generated/app_localizations.dart';

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

/// yt-dlp through youtubedl-android (spec-v0.3 D-33). Null on desktop.
@Riverpod(keepAlive: true)
YtDlpBridge? ytDlpBridge(Ref ref) =>
    ref.watch(appPlatformProvider).isDesktop ? null : ChannelYtDlpBridge();

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
  return AndroidMediaService(
    ytDlp: ref.watch(ytDlpBridgeProvider)!,
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

/// The folder downloads go to: the one chosen in Settings, else the
/// default. Null when neither is known.
@Riverpod(keepAlive: true)
Future<Directory?> downloadDirectory(Ref ref) async {
  final custom = ref.watch(
    currentSettingsProvider.select((s) => s.downloadDir),
  );
  final path = custom ?? await ref.watch(defaultDownloadDirProvider.future);
  return path == null ? null : Directory(path);
}

@Riverpod(keepAlive: true)
FileSystemService fileSystemService(Ref ref) {
  final desktop = ref.watch(appPlatformProvider).isDesktop;
  return FileSystemService(
    runner: ref.watch(processRunnerProvider),
    os: desktop ? DesktopOs.current : null,
    android: desktop ? null : const AndroidFileLauncher(),
  );
}

/// The download queue. Its concurrency follows Settings.
@Riverpod(keepAlive: true)
DownloadRepository downloadRepository(Ref ref) {
  final repo = DownloadRepository(
    ref.watch(mediaServiceProvider),
    maxConcurrent: ref.read(currentSettingsProvider).concurrentDownloads,
  );
  ref
    ..listen(
      currentSettingsProvider.select((s) => s.concurrentDownloads),
      (_, n) => repo.maxConcurrent = n,
    )
    ..onDispose(repo.dispose);
  return repo;
}

/// Null on desktop.
@Riverpod(keepAlive: true)
NotificationPermission? notificationPermission(Ref ref) =>
    ref.watch(appPlatformProvider).isDesktop
    ? null
    : NotificationPermission(ref.watch(prefsServiceProvider));

/// Keeps Android's download service in step with the queue (spec-v0.4
/// D-40). Null on desktop, where downloads stop with the window (D-48).
@Riverpod(keepAlive: true)
BackgroundDownloads? backgroundDownloads(Ref ref) {
  if (ref.watch(appPlatformProvider).isDesktop) return null;
  final service = BackgroundDownloads(
    repository: ref.watch(downloadRepositoryProvider),
    l10n: () => lookupAppLocalizations(
      Locale(ref.read(currentSettingsProvider).language.code),
    ),
    notifications: ref.watch(notificationPermissionProvider),
  )..start();
  ref.onDispose(service.dispose);
  return service;
}

@Riverpod(keepAlive: true)
LibraryRepository libraryRepository(Ref ref) => LibraryRepository(
  files: ref.watch(fileSystemServiceProvider),
  media: ref.watch(mediaServiceProvider),
  removed: ref.watch(removedItemsStoreProvider),
  storage: ref.watch(storagePermissionServiceProvider),
);

@Riverpod(keepAlive: true)
RemovedItemsStore removedItemsStore(Ref ref) =>
    RemovedItemsStore(ref.watch(prefsServiceProvider));

@Riverpod(keepAlive: true)
Future<String> appVersion(Ref ref) async =>
    (await PackageInfo.fromPlatform()).version;

/// Asks the user for a folder. Returns null when they cancel.
typedef DirectoryPicker = Future<String?> Function({String? initialDirectory});

@Riverpod(keepAlive: true)
DirectoryPicker directoryPicker(Ref ref) =>
    ({initialDirectory}) =>
        getDirectoryPath(initialDirectory: initialDirectory);

/// Reads plain text from the clipboard, or null when there is none.
typedef ClipboardReader = Future<String?> Function();

@Riverpod(keepAlive: true)
ClipboardReader clipboardReader(Ref ref) =>
    () async => (await Clipboard.getData(Clipboard.kTextPlain))?.text;
