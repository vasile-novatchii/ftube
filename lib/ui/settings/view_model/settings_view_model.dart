import 'dart:async';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../config/providers.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../data/services/android/storage_permission_service.dart';
import '../../../data/services/binary_service.dart';
import '../../../domain/models/app_settings.dart';
import '../../../domain/models/quality_preset.dart';
import '../../library/view_model/library_view_model.dart';

part 'settings_view_model.freezed.dart';
part 'settings_view_model.g.dart';

enum UpdateStatus { idle, running, done, failed }

@freezed
abstract class SettingsState with _$SettingsState {
  const factory SettingsState({
    required AppSettings settings,
    required bool isDesktop,

    /// `Downloads/Ftube` for this platform, once resolved.
    String? defaultDownloadDir,
    String? appVersion,
    @Default(true) bool loadingVersions,

    /// Null when not installed or unknown.
    String? ytDlpVersion,
    String? ffmpegVersion,
    @Default(UpdateStatus.idle) UpdateStatus ytDlpUpdate,
    Object? ytDlpUpdateError,

    /// Android only. Null until checked, and always null on desktop.
    StorageAccess? storageAccess,

    /// Whether a download is queued or running; app data can't be cleared
    /// then.
    @Default(false) bool downloading,
    @Default(UpdateStatus.idle) UpdateStatus clearData,
    Object? clearDataError,
  }) = _SettingsState;

  const SettingsState._();

  /// The folder downloads go to, or null while the default is unknown.
  // `this.` because the provider function of the same name is in scope.
  String? get downloadDir => settings.downloadDir ?? this.defaultDownloadDir;

  bool get usesDefaultDir => settings.downloadDir == null;

  bool get canClearData => !downloading && clearData != UpdateStatus.running;

  /// Android stores files through plain paths in the public Downloads
  /// folder (D-13), and its folder picker returns content URIs instead.
  bool get canChangeDownloadDir => isDesktop;
}

/// Presets offered as the default quality. `custom` needs a format picked
/// per video, so it is not one of them.
const defaultPresetChoices = [
  QualityPreset.best,
  QualityPreset.p1080,
  QualityPreset.p720,
  QualityPreset.p480,
  QualityPreset.audioMp3,
  QualityPreset.audioOgg,
];

/// Installed tool versions, null when unknown.
typedef ToolVersions = ({String? ytDlp, String? ffmpeg});

/// Runs the version commands once per app launch (D-19). Settings is
/// auto-dispose, so reading the versions there re-ran them on every visit.
@Riverpod(keepAlive: true)
Future<ToolVersions> toolVersions(Ref ref) async {
  final binaries = ref.read(binaryServiceProvider);
  if (binaries == null) {
    return (
      ytDlp: null,
      ffmpeg: await ref.read(ffmpegRunnerProvider).version(),
    );
  }
  final (ytDlp, ffmpeg) = await (
    binaries.version(Binary.ytDlp),
    binaries.version(Binary.ffmpeg),
  ).wait;
  return (ytDlp: ytDlp, ffmpeg: ffmpeg);
}

@riverpod
class SettingsViewModel extends _$SettingsViewModel {
  SettingsRepository get _repo => ref.read(settingsRepositoryProvider);

  @override
  SettingsState build() {
    ref.listen(
      currentSettingsProvider,
      (_, settings) => state = state.copyWith(settings: settings),
    );
    final downloads = ref.read(downloadRepositoryProvider);
    final sub = downloads.changes.listen(
      (_) => state = state.copyWith(downloading: downloads.activeCount > 0),
    );
    ref.onDispose(sub.cancel);
    unawaited(_load());
    return SettingsState(
      settings: ref.read(currentSettingsProvider),
      isDesktop: ref.read(appPlatformProvider).isDesktop,
      downloading: downloads.activeCount > 0,
    );
  }

  Future<void> _load() async {
    await Future.wait([
      _loadVersions(),
      refreshStorageAccess(),
      ref.read(defaultDownloadDirProvider.future).then((dir) {
        if (ref.mounted) state = state.copyWith(defaultDownloadDir: dir);
      }, onError: (_) {}),
      ref.read(appVersionProvider.future).then((v) {
        if (ref.mounted) state = state.copyWith(appVersion: v);
      }, onError: (_) {}),
    ]);
  }

  Future<void> _loadVersions() async {
    ToolVersions? versions;
    try {
      versions = await ref.read(toolVersionsProvider.future);
    } on Object {
      // Retry on the next visit instead of caching the failure.
      ref.invalidate(toolVersionsProvider);
    }
    if (!ref.mounted) return;
    state = state.copyWith(
      loadingVersions: false,
      ytDlpVersion: versions?.ytDlp,
      ffmpegVersion: versions?.ffmpeg,
    );
  }

  Future<void> setTheme(ThemePreference theme) =>
      _repo.update((s) => s.copyWith(theme: theme));

  Future<void> setLanguage(AppLanguage language) =>
      _repo.update((s) => s.copyWith(language: language));

  Future<void> setDefaultPreset(QualityPreset preset) {
    if (!defaultPresetChoices.contains(preset)) {
      throw ArgumentError.value(preset, 'preset', 'not a default preset');
    }
    return _repo.update((s) => s.copyWith(defaultPreset: preset));
  }

  Future<void> setConcurrentDownloads(int count) => _repo.update(
    (s) => s.copyWith(
      concurrentDownloads: count.clamp(
        AppSettings.minConcurrent,
        AppSettings.maxConcurrent,
      ),
    ),
  );

  /// Lets the user pick a folder. Does nothing when they cancel.
  Future<void> pickDownloadDir() async {
    if (!state.canChangeDownloadDir) return;
    final dir = await ref.read(directoryPickerProvider)(
      initialDirectory: state.downloadDir,
    );
    if (dir == null || dir.trim().isEmpty) return;
    await _repo.update((s) => s.copyWith(downloadDir: dir));
  }

  Future<void> resetDownloadDir() =>
      _repo.update((s) => s.copyWith(downloadDir: null));

  /// Runs `yt-dlp -U` (desktop). [SettingsState.ytDlpUpdate] reports the
  /// outcome.
  Future<void> updateYtDlp() async {
    final binaries = ref.read(binaryServiceProvider);
    if (binaries == null || state.ytDlpUpdate == UpdateStatus.running) return;
    state = state.copyWith(
      ytDlpUpdate: UpdateStatus.running,
      ytDlpUpdateError: null,
    );
    try {
      final version = await binaries.updateYtDlp();
      // The next visit reads the updated version.
      ref.invalidate(toolVersionsProvider);
      if (!ref.mounted) return;
      state = state.copyWith(
        ytDlpUpdate: UpdateStatus.done,
        ytDlpVersion: version ?? state.ytDlpVersion,
      );
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        ytDlpUpdate: UpdateStatus.failed,
        ytDlpUpdateError: e,
      );
    }
  }

  /// Empties the cache and removes every library item for good, keeping
  /// the files, the settings and the desktop tools (D-26). Not allowed
  /// while a download is running. [SettingsState.clearData] reports the
  /// outcome.
  Future<void> clearAppData() async {
    if (!state.canClearData) return;
    state = state.copyWith(
      clearData: UpdateStatus.running,
      clearDataError: null,
    );
    try {
      await ref
          .read(fileSystemServiceProvider)
          .emptyDir(ref.read(appDirsProvider).temp);
      final dir = await ref.read(downloadDirectoryProvider.future);
      if (dir != null) await ref.read(libraryRepositoryProvider).removeAll(dir);
      if (ref.exists(libraryViewModelProvider)) {
        await ref.read(libraryViewModelProvider.notifier).load();
      }
      if (ref.mounted) state = state.copyWith(clearData: UpdateStatus.done);
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(clearData: UpdateStatus.failed, clearDataError: e);
    }
  }

  /// Re-reads the Android storage access, for example when the user comes
  /// back from system settings.
  Future<void> refreshStorageAccess() async {
    final storage = ref.read(storagePermissionServiceProvider);
    if (storage == null) return;
    final access = await storage.status();
    if (ref.mounted) state = state.copyWith(storageAccess: access);
  }

  /// Asks for "All files access", or opens the app settings when Android
  /// will no longer show the request.
  Future<void> requestStorageAccess() async {
    final storage = ref.read(storagePermissionServiceProvider);
    if (storage == null) return;
    var access = await storage.request();
    if (access == StorageAccess.permanentlyDenied) {
      await storage.openSettings();
      access = await storage.status();
    }
    if (ref.mounted) state = state.copyWith(storageAccess: access);
  }
}
