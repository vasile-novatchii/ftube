import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/config/providers.dart';
import 'package:ftube/data/services/android/storage_permission_service.dart';
import 'package:ftube/data/services/binary_service.dart';
import 'package:ftube/domain/exceptions/ftube_exception.dart';
import 'package:ftube/domain/models/app_settings.dart';
import 'package:ftube/domain/models/quality_preset.dart';
import 'package:ftube/ui/settings/view_model/settings_view_model.dart';
import 'package:ftube/ui/settings/widgets/settings_view.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers.dart';

void main() {
  setUpAll(() => registerFallbackValue(Binary.ytDlp));

  late TestEnv env;
  late ProviderContainer container;

  Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    ThemeMode themeMode = ThemeMode.light,
  }) async {
    tester.view
      ..physicalSize = const Size(1200, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    container = await env.container();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: localized(
          const SettingsView(),
          locale: locale,
          themeMode: themeMode,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  AppSettings saved() => container.read(settingsRepositoryProvider).current;

  Future<void> choose(WidgetTester tester, String key, String item) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item).last);
    await tester.pumpAndSettle();
  }

  group('desktop', () {
    setUp(() => env = TestEnv.desktop());

    testWidgets('clear app data asks first, then confirms with a SnackBar', (
      tester,
    ) async {
      await pump(tester);
      final tile = find.byKey(const Key('settings.clearData'));
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(find.text('Clear app data?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      verifyNever(() => env.files.emptyDir(any()));

      await tester.tap(tile);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings.confirmClearData')));
      await tester.pumpAndSettle();
      verify(() => env.files.emptyDir(any())).called(1);
      expect(find.text('App data cleared.'), findsOneWidget);
      expect(
        container.read(settingsViewModelProvider).clearData,
        UpdateStatus.done,
      );
    });

    testWidgets('clear app data is disabled while a download runs', (
      tester,
    ) async {
      await pump(tester);
      container
          .read(downloadRepositoryProvider)
          .enqueue(
            url: 'https://youtu.be/abc',
            title: 'Song',
            preset: QualityPreset.best,
            outDir: Directory('/out'),
          );
      await tester.pumpAndSettle();
      final tile = find.byKey(const Key('settings.clearData'));
      expect(tester.widget<ListTile>(tile).enabled, isFalse);
      expect(
        find.text('Not available while a download is running.'),
        findsOneWidget,
      );
    });

    testWidgets('a failed clear shows the error', (tester) async {
      when(() => env.files.emptyDir(any())).thenThrow(const FileError('busy'));
      await pump(tester);
      final tile = find.byKey(const Key('settings.clearData'));
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings.confirmClearData')));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
    });

    for (final (locale, title, theme) in [
      (const Locale('en'), 'Settings', 'System default'),
      (const Locale('ro'), 'Setări', 'Implicită sistemului'),
      (const Locale('ar'), 'الإعدادات', 'حسب النظام'),
    ]) {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        testWidgets('renders in ${locale.languageCode} ${mode.name}', (
          tester,
        ) async {
          await pump(tester, locale: locale, themeMode: mode);
          expect(find.text(title), findsOneWidget);
          expect(find.text(theme), findsOneWidget);
          expect(find.text('/home/me/Downloads/Ftube'), findsOneWidget);
          expect(find.text('1.0'), findsOneWidget);
          expect(find.text('9.0'), findsOneWidget);
          expect(find.text('0.1.0'), findsOneWidget);
          expect(find.byKey(const Key('settings.updateYtDlp')), findsOneWidget);
          expect(find.byKey(const Key('settings.storage')), findsNothing);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('changes theme, language, preset and concurrency', (
      tester,
    ) async {
      await pump(tester);
      await choose(tester, 'settings.theme', 'Dark');
      await choose(tester, 'settings.preset', 'MP3');
      await tester.tap(find.text('3'));
      await tester.pumpAndSettle();
      await choose(tester, 'settings.language', 'Română');
      expect(saved().theme, ThemePreference.dark);
      expect(saved().defaultPreset, QualityPreset.audioMp3);
      expect(saved().concurrentDownloads, 3);
      expect(saved().language, AppLanguage.ro);
    });

    testWidgets('changes and resets the download folder', (tester) async {
      await pump(tester);
      expect(find.byKey(const Key('settings.folder.reset')), findsNothing);
      env.pickedDirs.add('/videos');
      await tester.tap(find.byKey(const Key('settings.folder.change')));
      await tester.pumpAndSettle();
      expect(find.text('/videos'), findsOneWidget);

      await tester.tap(find.byKey(const Key('settings.folder.reset')));
      await tester.pumpAndSettle();
      expect(find.text('/home/me/Downloads/Ftube'), findsOneWidget);
    });

    testWidgets('shows the yt-dlp update result', (tester) async {
      when(() => env.binaries.updateYtDlp()).thenAnswer((_) async => '2.0');
      await pump(tester);
      await tester.tap(find.byKey(const Key('settings.updateYtDlp')));
      await tester.pump();
      await tester.pump();
      expect(find.text('yt-dlp is up to date (2.0).'), findsOneWidget);

      when(() => env.binaries.updateYtDlp())
          .thenThrow(const Network('offline'));
      await tester.tap(find.byKey(const Key('settings.updateYtDlp')));
      await tester.pump();
      await tester.pump();
      expect(
        find.text('Could not reach the server. Check your connection.'),
        findsOneWidget,
      );
    });

    testWidgets('shows a spinner while updating', (tester) async {
      when(() => env.binaries.updateYtDlp()).thenAnswer(
        (_) => Future.delayed(const Duration(seconds: 1), () => '2.0'),
      );
      await pump(tester);
      await tester.tap(find.byKey(const Key('settings.updateYtDlp')));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows missing tools and opens the licenses', (tester) async {
      when(() => env.binaries.version(any())).thenAnswer((_) async => null);
      await pump(tester);
      expect(find.text('Not installed'), findsNWidgets(2));
      await tester.tap(find.byKey(const Key('settings.licenses')));
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsOneWidget);
    });
  });

  group('android', () {
    setUp(() => env = TestEnv.android());

    testWidgets('shows storage access and no desktop tools', (tester) async {
      when(() => env.storage.status())
          .thenAnswer((_) async => StorageAccess.denied);
      when(() => env.storage.request())
          .thenAnswer((_) async => StorageAccess.granted);
      await pump(tester, themeMode: ThemeMode.dark);
      expect(find.byKey(const Key('settings.updateYtDlp')), findsNothing);
      expect(find.byKey(const Key('settings.folder.change')), findsNothing);
      expect(find.text('7.1'), findsOneWidget);
      expect(
        find.text('All files access is needed to save downloads.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Grant access'));
      await tester.pumpAndSettle();
      expect(find.text('All files access is granted.'), findsOneWidget);
    });

    testWidgets('refreshes storage access on resume', (tester) async {
      await pump(tester, locale: const Locale('ro'));
      expect(
        find.text('Accesul la toate fișierele este acordat.'),
        findsOneWidget,
      );
      when(() => env.storage.status())
          .thenAnswer((_) async => StorageAccess.denied);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Acordă acces'), findsOneWidget);
    });
  });
}
