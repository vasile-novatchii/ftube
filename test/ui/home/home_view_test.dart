import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/config/providers.dart';
import 'package:ftube/data/services/android/storage_permission_service.dart';
import 'package:ftube/domain/exceptions/ftube_exception.dart';
import 'package:ftube/domain/models/models.dart';
import 'package:ftube/ui/home/view_model/home_view_model.dart';
import 'package:ftube/ui/home/widgets/home_view.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers.dart';

const url = 'https://youtu.be/abc';

const info = MediaInfo(
  url: url,
  title: 'Song',
  uploader: 'Band',
  duration: Duration(minutes: 3, seconds: 42),
  formats: [
    MediaFormat(
      id: '137',
      container: 'mp4',
      kind: FormatKind.videoOnly,
      resolution: '1080p',
      height: 1080,
    ),
    MediaFormat(
      id: '140',
      container: 'm4a',
      kind: FormatKind.audioOnly,
      bitrateKbps: 128,
    ),
  ],
);

void main() {
  late TestEnv env;
  late ProviderContainer container;

  Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    ThemeMode themeMode = ThemeMode.light,
    bool settle = true,
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
          const HomeView(),
          locale: locale,
          themeMode: themeMode,
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  Future<void> enterAndFetch(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('home.url')), url);
    await tester.pump();
    await tester.tap(find.byKey(const Key('home.fetch')));
    await tester.pumpAndSettle();
  }

  Finder text(String key) => find.byKey(Key(key));

  HomeState home() => container.read(homeViewModelProvider);

  group('desktop', () {
    testWidgets('the clear button shows only with text and empties the field', (
      tester,
    ) async {
      await pump(tester);
      expect(text('home.clear'), findsNothing);

      await tester.enterText(text('home.url'), url);
      await tester.pump();
      expect(text('home.clear'), findsOneWidget);

      await tester.tap(text('home.clear'));
      await tester.pump();
      expect(home().url, isEmpty);
      expect(
        tester.widget<TextField>(text('home.url')).controller!.text,
        isEmpty,
      );
      expect(text('home.clear'), findsNothing);
    });

    setUp(() {
      env = TestEnv.desktop();
      env.media.onFetch = (_) async => info;
    });

    for (final (locale, themeMode, hint, empty, queue) in [
      (
        const Locale('en'),
        ThemeMode.light,
        'Paste a YouTube link',
        'Paste a YouTube link to get started.',
        'Queue (0)',
      ),
      (
        const Locale('ro'),
        ThemeMode.dark,
        'Lipește un link YouTube',
        'Lipește un link YouTube pentru a începe.',
        'Coadă (0)',
      ),
    ]) {
      testWidgets('starts empty (${locale.languageCode}, ${themeMode.name})', (
        tester,
      ) async {
        await pump(tester, locale: locale, themeMode: themeMode);
        expect(find.text(hint), findsOneWidget);
        expect(find.text(empty), findsOneWidget);
        expect(find.text(queue), findsOneWidget);
        final fetch = tester.widget<FilledButton>(text('home.fetch'));
        expect(fetch.onPressed, isNull);
        expect(text('home.download'), findsNothing);
      });
    }

    testWidgets('fetches a link and shows its info', (tester) async {
      final pending = Completer<MediaInfo>();
      env.media.onFetch = (_) => pending.future;
      await pump(tester);
      await tester.enterText(text('home.url'), url);
      await tester.pump();
      await tester.tap(text('home.fetch'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      pending.complete(info);
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Song'), findsOneWidget);
      expect(find.text('Band · 3:42'), findsOneWidget);
      expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
      final best = tester.widget<ChoiceChip>(text('home.preset.best'));
      expect(best.selected, isTrue);
    });

    testWidgets('submitting the field fetches too', (tester) async {
      await pump(tester);
      await tester.enterText(text('home.url'), url);
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pumpAndSettle();
      expect(text('home.title'), findsOneWidget);
    });

    testWidgets('shows a fetch error', (tester) async {
      await pump(tester);
      await tester.enterText(text('home.url'), 'not a link');
      await tester.pump();
      await tester.tap(text('home.fetch'));
      await tester.pumpAndSettle();
      expect(text('home.error'), findsOneWidget);
      expect(find.text('Paste a YouTube link to get started.'), findsNothing);
    });

    testWidgets('picks a preset and downloads', (tester) async {
      await pump(tester);
      await enterAndFetch(tester);
      await tester.tap(text('home.preset.audioMp3'));
      await tester.pumpAndSettle();
      expect(home().preset, QualityPreset.audioMp3);

      await tester.tap(text('home.download'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Added to the queue.'), findsOneWidget);
      final job = container.read(downloadRepositoryProvider).jobs.single;
      expect(job.request.preset, QualityPreset.audioMp3);
      expect(find.text('Queue (1)'), findsOneWidget);
      expect(find.text('Song · MP3'), findsOneWidget);
    });

    testWidgets('picks a format from the list', (tester) async {
      await pump(tester);
      await enterAndFetch(tester);
      await tester.tap(text('home.formats'));
      await tester.pumpAndSettle();
      expect(text('format.140'), findsOneWidget);
      await tester.tap(text('format.137'));
      await tester.pumpAndSettle();
      expect(home().formatId, '137');
      final chip = tester.widget<ChoiceChip>(text('home.formats'));
      expect(chip.selected, isTrue);
      expect(find.textContaining('1080p'), findsWidgets);
    });

    testWidgets('closing the format list keeps the preset', (tester) async {
      await pump(tester);
      await enterAndFetch(tester);
      await tester.tap(text('home.formats'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(home().preset, QualityPreset.best);
    });

    testWidgets('a missing download folder is reported', (tester) async {
      env.failLookups = true;
      await pump(tester);
      await enterAndFetch(tester);
      await tester.tap(text('home.download'));
      await tester.pumpAndSettle();
      expect(
        find.text('The download folder is not available.'),
        findsOneWidget,
      );
    });

    testWidgets('paste fills the field and fetches', (tester) async {
      await pump(tester);
      env.clipboard = url;
      await tester.tap(text('home.paste'));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(text('home.url'));
      expect(field.controller!.text, url);
      expect(text('home.title'), findsOneWidget);
    });

    testWidgets('offers a link from the clipboard on start', (tester) async {
      env.clipboard = url;
      await pump(tester);
      expect(find.text('Use the link on the clipboard?\n$url'), findsOneWidget);
      await tester.tap(text('home.clipboard.use'));
      await tester.pumpAndSettle();
      expect(text('home.clipboard.use'), findsNothing);
      expect(text('home.title'), findsOneWidget);
    });

    testWidgets('the clipboard offer can be dismissed', (tester) async {
      env.clipboard = url;
      await pump(tester);
      await tester.tap(text('home.clipboard.dismiss'));
      await tester.pumpAndSettle();
      expect(text('home.clipboard.use'), findsNothing);
    });

    testWidgets('checks the clipboard again on resume', (tester) async {
      await pump(tester);
      env.clipboard = url;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(text('home.clipboard.use'), findsOneWidget);
    });

    testWidgets('keeps the video when the view is rebuilt', (tester) async {
      await pump(tester);
      await enterAndFetch(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: localized(const HomeView()),
        ),
      );
      await tester.pumpAndSettle();
      expect(text('home.title'), findsOneWidget);
      final field = tester.widget<TextField>(text('home.url'));
      expect(field.controller!.text, url);
    });
  });

  group('android', () {
    setUp(() {
      env = TestEnv.android();
      env.media.onFetch = (_) async => info;
    });

    testWidgets('blocked storage shows a grant banner', (tester) async {
      when(() => env.storage.status())
          .thenAnswer((_) async => StorageAccess.denied);
      when(() => env.storage.request())
          .thenAnswer((_) async => StorageAccess.granted);
      await pump(tester);
      await enterAndFetch(tester);
      await tester.tap(text('home.download'));
      await tester.pumpAndSettle();
      expect(
        find.text('All files access is needed to save downloads.'),
        findsOneWidget,
      );
      final download = tester.widget<ButtonStyleButton>(text('home.download'));
      expect(download.onPressed, isNull);

      await tester.tap(text('home.grant'));
      await tester.pumpAndSettle();
      expect(text('home.grant'), findsNothing);
    });

    testWidgets('rechecks storage access on resume', (tester) async {
      when(() => env.storage.status())
          .thenAnswer((_) async => StorageAccess.denied);
      await pump(tester);
      await enterAndFetch(tester);
      await tester.tap(text('home.download'));
      await tester.pumpAndSettle();
      expect(text('home.grant'), findsOneWidget);

      when(() => env.storage.status())
          .thenAnswer((_) async => StorageAccess.granted);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(text('home.grant'), findsNothing);
    });
  });

  test('NoDownloadFolder is an exception', () {
    expect(const NoDownloadFolder(), isA<Exception>());
    expect(const FileError(), isA<FtubeException>());
  });
}
