import 'dart:async';

import '../../domain/models/app_settings.dart';
import '../../domain/models/quality_preset.dart';
import '../services/prefs_service.dart';

/// Source of truth for [AppSettings], persisted through [PrefsService].
///
/// Unknown or out-of-range stored values fall back to the defaults, so an
/// older or newer app version never fails to start because of its prefs.
class SettingsRepository {
  SettingsRepository(this._prefs) : _current = _read(_prefs);

  final PrefsService _prefs;
  AppSettings _current;
  final _changes = StreamController<AppSettings>.broadcast(sync: true);

  static const themeKey = 'settings.theme';
  static const languageKey = 'settings.language';
  static const downloadDirKey = 'settings.downloadDir';
  static const presetKey = 'settings.defaultPreset';
  static const concurrentKey = 'settings.concurrentDownloads';
  static const permissionPromptKey = 'onboarding.permissionPromptDone';

  AppSettings get current => _current;

  /// Emits every saved value after [current].
  Stream<AppSettings> get changes => _changes.stream;

  /// Persists [settings] and notifies [changes]. A [AppSettings.downloadDir]
  /// that is null or blank means the default folder.
  Future<void> save(AppSettings settings) async {
    final dir = settings.downloadDir?.trim();
    final next = settings.copyWith(
      downloadDir: dir == null || dir.isEmpty ? null : dir,
    );
    await _prefs.setString(themeKey, next.theme.name);
    await _prefs.setString(languageKey, next.language.code);
    await _prefs.setString(presetKey, next.defaultPreset.name);
    await _prefs.setInt(concurrentKey, next.concurrentDownloads);
    final nextDir = next.downloadDir;
    if (nextDir == null) {
      await _prefs.remove(downloadDirKey);
    } else {
      await _prefs.setString(downloadDirKey, nextDir);
    }
    if (next == _current) return;
    _current = next;
    _changes.add(next);
  }

  /// Applies [change] to [current] and saves the result.
  Future<void> update(AppSettings Function(AppSettings) change) =>
      save(change(_current));

  /// Whether the Android first-run permission screen was already shown.
  bool get permissionPromptDone => _prefs.getBool(permissionPromptKey) ?? false;

  Future<void> markPermissionPromptDone() =>
      _prefs.setBool(permissionPromptKey, value: true);

  Future<void> dispose() => _changes.close();

  static AppSettings _read(PrefsService prefs) {
    const defaults = AppSettings();
    T byName<T extends Enum>(List<T> values, String key, T fallback) {
      final name = prefs.getString(key);
      return values.where((v) => v.name == name).firstOrNull ?? fallback;
    }

    final code = prefs.getString(languageKey);
    final concurrent = prefs.getInt(concurrentKey);
    final dir = prefs.getString(downloadDirKey);
    return AppSettings(
      theme: byName(ThemePreference.values, themeKey, defaults.theme),
      language:
          AppLanguage.values.where((l) => l.code == code).firstOrNull ??
          defaults.language,
      downloadDir: dir == null || dir.trim().isEmpty ? null : dir,
      defaultPreset: byName(
        // `custom` needs a format picked per video, so it is never a default.
        QualityPreset.values.where((p) => p != QualityPreset.custom).toList(),
        presetKey,
        defaults.defaultPreset,
      ),
      concurrentDownloads:
          concurrent != null &&
              concurrent >= AppSettings.minConcurrent &&
              concurrent <= AppSettings.maxConcurrent
          ? concurrent
          : defaults.concurrentDownloads,
    );
  }
}
