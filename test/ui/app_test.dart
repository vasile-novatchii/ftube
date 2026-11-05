import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/config/providers.dart';
import 'package:ftube/data/repositories/settings_repository.dart';
import 'package:ftube/data/services/android/storage_permission_service.dart';
import 'package:ftube/data/services/binary_service.dart';
import 'package:ftube/domain/models/app_settings.dart';
import 'package:ftube/ui/app.dart';
import 'package:ftube/ui/library/widgets/library_view.dart';
import 'package:ftube/ui/permission/widgets/permission_view.dart';
import 'package:ftube/ui/settings/widgets/settings_view.dart';
import 'package:ftube/ui/setup/widgets/setup_view.dart';
import 'package:ftube/ui/shell/app_shell.dart';
import 'package:mocktail/mocktail.dart';

import 'helpers.dart';

void main() {
  late TestEnv env;
  late ProviderContainer container;

  Future<void> pump(
    WidgetTester tester, [
    Map<String, Object> prefs = const {},
  ]) async {
    container = await env.container(prefs);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const FtubeApp()),
    );
    await tester.pumpAndSettle();
  }

  MaterialApp app(WidgetTester tester) =>
      tester.widget<MaterialApp>(find.byType(MaterialApp));

  group('desktop', () {
    setUp(() => env = TestEnv.desktop());

    testWidgets('starts in English and follows the system theme', (
      tester,
    ) async {
      await pump(tester);
      expect(app(tester).themeMode, ThemeMode.system);
      expect(app(tester).locale, const Locale('en'));
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('Paste a video link to get started.'), findsOneWidget);
    });

    testWidgets('navigates between the three screens', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Library').first);
      await tester.pumpAndSettle();
      expect(find.byType(LibraryView), findsOneWidget);
      expect(find.text('Your downloads will appear here.'), findsOneWidget);
      await tester.tap(find.text('Settings').first);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsView), findsOneWidget);
    });

    testWidgets('applies saved theme and language at once', (tester) async {
      await pump(tester, {
        SettingsRepository.themeKey: 'dark',
        SettingsRepository.languageKey: 'ro',
      });
      expect(app(tester).themeMode, ThemeMode.dark);
      expect(find.text('Acasă'), findsWidgets);

      await container
          .read(settingsRepositoryProvider)
          .update(
            (s) => s.copyWith(
              theme: ThemePreference.light,
              language: AppLanguage.en,
            ),
          );
      await tester.pumpAndSettle();
      expect(app(tester).themeMode, ThemeMode.light);
      expect(find.text('Home'), findsWidgets);
    });

    testWidgets('blocks on setup until the tools are installed', (
      tester,
    ) async {
      when(() => env.installer.missing())
          .thenAnswer((_) async => [entry(Binary.ytDlp, 10)]);
      await pump(tester);
      expect(find.byType(SetupView), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });
  });

  group('android', () {
    setUp(() => env = TestEnv.android());

    testWidgets('uses a bottom navigation bar on a portrait phone', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(360, 640)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pump(tester);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('asks for storage access on first run', (tester) async {
      when(() => env.storage.status())
          .thenAnswer((_) async => StorageAccess.denied);
      await pump(tester);
      expect(find.byType(PermissionView), findsOneWidget);
      await tester.tap(find.byKey(const Key('permission.later')));
      await tester.pumpAndSettle();
      expect(find.byType(AppShell), findsOneWidget);
    });
  });
}
