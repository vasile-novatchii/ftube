import 'package:flutter/widgets.dart';

import '../../domain/exceptions/ftube_exception.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/quality_preset.dart';
import '../../l10n/generated/app_localizations.dart';

export '../../l10n/generated/app_localizations.dart';

extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

extension AppLocalizationsLabels on AppLocalizations {
  String themeLabel(ThemePreference theme) => switch (theme) {
    ThemePreference.system => themeSystem,
    ThemePreference.light => themeLight,
    ThemePreference.dark => themeDark,
  };

  String languageLabel(AppLanguage language) => switch (language) {
    AppLanguage.en => languageEn,
    AppLanguage.ro => languageRo,
  };

  String presetLabel(QualityPreset preset) => switch (preset) {
    QualityPreset.best => presetBest,
    QualityPreset.p1080 => presetP1080,
    QualityPreset.p720 => presetP720,
    QualityPreset.p480 => presetP480,
    QualityPreset.audioMp3 => presetAudioMp3,
    QualityPreset.audioOgg => presetAudioOgg,
    QualityPreset.custom => presetCustom,
  };

  /// A user-facing message for [error]. Technical details stay in logs.
  String errorMessage(Object error) => switch (error) {
    InvalidUrl() => errorInvalidUrl,
    Unsupported() => errorUnsupported,
    Network() => errorNetwork,
    BinaryMissing(:final binary) => errorBinaryMissing(binary),
    ChecksumMismatch(:final binary) => errorChecksum(binary),
    ProcessFailed(:final exitCode) => errorProcessFailed(exitCode),
    StoragePermission() => errorStoragePermission,
    Cancelled() => errorCancelled,
    _ => errorUnknown,
  };
}

/// Human-readable size, for example `12.3 MB`.
String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 || value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}
