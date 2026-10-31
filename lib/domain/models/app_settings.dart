import 'package:freezed_annotation/freezed_annotation.dart';

import 'quality_preset.dart';

part 'app_settings.freezed.dart';

/// Theme choice. `system` follows the OS and is the default.
enum ThemePreference { system, light, dark }

/// UI language. English is the default and the fallback.
enum AppLanguage {
  en('en'),
  ro('ro');

  const AppLanguage(this.code);

  final String code;
}

/// User settings persisted by `SettingsRepository`.
@freezed
abstract class AppSettings with _$AppSettings {
  @Assert(
    'concurrentDownloads >= AppSettings.minConcurrent && '
        'concurrentDownloads <= AppSettings.maxConcurrent',
    'concurrentDownloads must be within 1..3',
  )
  const factory AppSettings({
    @Default(ThemePreference.system) ThemePreference theme,
    @Default(AppLanguage.en) AppLanguage language,

    /// Custom download folder, or null for the default `Downloads/Ftube`.
    String? downloadDir,
    @Default(QualityPreset.best) QualityPreset defaultPreset,
    @Default(2) int concurrentDownloads,
  }) = _AppSettings;

  static const minConcurrent = 1;
  static const maxConcurrent = 3;
}
