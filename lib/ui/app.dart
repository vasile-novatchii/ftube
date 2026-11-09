import 'dart:async';

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
import 'share/view_model/share_view_model.dart';
import 'share/widgets/share_view.dart';
import 'shell/app_shell.dart';

/// Root widget: theme and language come from the saved settings.
class FtubeApp extends ConsumerWidget {
  const FtubeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    // Android: started once, lives as long as the engine (spec-v0.4).
    ref.watch(backgroundDownloadsProvider);
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
      home: const AppRoot(),
    );
  }
}

/// The app, or the share popup in its place (spec-v0.4-share D-50). The
/// app stays mounted while the popup is shown, so its state survives.
class AppRoot extends ConsumerWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final share = ref.watch(shareSessionProvider);
    ref.listen(shareSessionProvider, (_, next) {
      // App dialogs and sheets would cover the popup.
      if (next != null) Navigator.of(context).popUntil((r) => r.isFirst);
    });
    return PopScope(
      canPop: share == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(ref.read(shareSessionProvider.notifier).close());
      },
      child: Stack(
        children: [
          TickerMode(
            enabled: share == null,
            child: Offstage(offstage: share != null, child: const AppGate()),
          ),
          if (share != null) const ShareView(),
        ],
      ),
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
