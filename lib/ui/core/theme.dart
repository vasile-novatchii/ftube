import 'package:flutter/material.dart';

import '../../domain/models/app_settings.dart';

/// Material 3 themes from one seed color (D-7).
abstract final class AppTheme {
  static const seed = Color(0xFFD32F2F);

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: brightness),
    visualDensity: VisualDensity.adaptivePlatformDensity,
  );

  static ThemeMode mode(ThemePreference preference) => switch (preference) {
    ThemePreference.system => ThemeMode.system,
    ThemePreference.light => ThemeMode.light,
    ThemePreference.dark => ThemeMode.dark,
  };
}
