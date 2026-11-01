import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/providers.dart';
import 'core/l10n.dart';
import 'core/theme.dart';
import 'permission/view_model/permission_view_model.dart';
import 'permission/widgets/permission_view.dart';
import 'setup/view_model/setup_view_model.dart';
import 'setup/widgets/setup_view.dart';
import 'shell/app_shell.dart';

/// Root widget: theme and language come from the saved settings.
class FtubeApp extends ConsumerWidget {
  const FtubeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    return MaterialApp(
      onGenerateTitle: (context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      themeMode: AppTheme.mode(settings.theme),
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      locale: Locale(settings.language.code),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AppGate(),
    );
  }
}

/// Shows the desktop setup or the Android permission screen before the
/// shell when needed.
class AppGate extends ConsumerWidget {
  const AppGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(setupViewModelProvider) is! SetupReady) {
      return const SetupView();
    }
    if (ref.watch(permissionViewModelProvider).showPrompt) {
      return const PermissionView();
    }
    return const AppShell();
  }
}
