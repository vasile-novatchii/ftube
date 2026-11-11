import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/config/providers.dart';
import 'package:ftube/data/repositories/app_update_repository.dart';
import 'package:ftube/data/services/android/android_update_notifier.dart';
import 'package:ftube/domain/exceptions/ftube_exception.dart';
import 'package:ftube/domain/models/app_update.dart';
import 'package:ftube/ui/home/widgets/home_view.dart';
import 'package:ftube/ui/settings/widgets/settings_view.dart';
import 'package:ftube/ui/update/view_model/app_update_view_model.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers.dart';

class _MockNotifier extends Mock implements AndroidUpdateNotifier {}

final _release = AppRelease(
  version: '0.6.0',
  tag: 'v0.6.0',
  pageUrl: Uri.parse('https://github.com/o/r/releases/tag/v0.6.0'),
  publishedAt: DateTime.utc(2026, 11, 20),
  notes: '## Added\n\n- **Update** notice',
);

void main() {
  setUpAll(() => registerFallbackValue(_release));

  late TestEnv env;
  late ProviderContainer container;

  AppUpdateViewModel vm() =>
      container.read(appUpdateViewModelProvider.notifier);
  AppUpdateState state() => container.read(appUpdateViewModelProvider);

  void online([AppRelease? release]) =>
      when(env.updates.latestRelease)
          .thenAnswer((_) async => release ?? _release);

  group('view model', () {
    setUp(() async {
      env = TestEnv.desktop();
      container = await env.container();
      addTearDown(container.dispose);
    });

    test('a newer release shows the banner', () async {
      online();
      await vm().checkOnStartup();
      expect(state().banner?.version, '0.6.0');
    });

    test('the startup check runs once per launch', () async {
      online();
      await vm().checkOnStartup();
      vm().later();
      await vm().checkOnStartup();
      expect(state().banner, isNull);
      verify(env.updates.latestRelease).called(1);
    });

    test('offline, up to date or skipped shows nothing', () async {
      await vm().checkOnStartup();
      expect(state().banner, isNull);

      final skipped = await env.container({
        AppUpdateRepository.skippedKey: '0.6.0',
      });
      addTearDown(skipped.dispose);
      online();
      await skipped.read(appUpdateViewModelProvider.notifier).checkOnStartup();
      expect(skipped.read(appUpdateViewModelProvider).banner, isNull);
    });

    test('Skip hides the banner and saves the version', () async {
      online();
      await vm().checkOnStartup();
      await vm().skip();
      expect(state().banner, isNull);
      expect(container.read(appUpdateRepositoryProvider).skipped, '0.6.0');
    });

    test('the Settings check ignores the skipped version', () async {
      online();
      await container.read(appUpdateRepositoryProvider).skip('0.6.0');
      await vm().checkNow();
      expect(state().manual, isA<UpdateAvailable>());
      expect(state().checking, isFalse);
    });

    test('the Settings check reports failures', () async {
      await vm().checkNow();
      expect(state().manual, isA<CheckFailed>());
    });

    test('download opens the release page', () async {
      expect(await vm().download(_release), isTrue);
      verify(() => env.files.openUrl(_release.pageUrl)).called(1);
      when(() => env.files.openUrl(any())).thenThrow(const Unsupported('x'));
      expect(await vm().download(_release), isFalse);
    });
  });

  group('Android notification (D-93)', () {
    late _MockNotifier notice;

    Future<void> start([Map<String, Object> prefs = const {}]) async {
      env = TestEnv.android();
      notice = _MockNotifier();
      env.notice = notice;
      when(
        () => notice.notify(
          any(),
          title: any(named: 'title'),
          text: any(named: 'text'),
          channelName: any(named: 'channelName'),
        ),
      ).thenAnswer((_) async => true);
      container = await env.container(prefs);
      addTearDown(container.dispose);
      online();
    }

    test('posts once per version', () async {
      await start();
      await vm().checkOnStartup();
      verify(
        () => notice.notify(
          _release,
          title: 'Ftube 0.6.0 is available',
          text: any(named: 'text'),
          channelName: 'App updates',
        ),
      ).called(1);
      expect(
        container.read(appUpdateRepositoryProvider).wasNotified('0.6.0'),
        isTrue,
      );
    });

    test('an already notified version and manual checks post none', () async {
      await start({AppUpdateRepository.notifiedKey: '0.6.0'});
      await vm().checkOnStartup();
      await vm().checkNow();
      expect(state().banner, isNotNull);
      verifyNever(
        () => notice.notify(
          any(),
          title: any(named: 'title'),
          text: any(named: 'text'),
          channelName: any(named: 'channelName'),
        ),
      );
    });

    test('notifications off: tried again next launch', () async {
      await start();
      when(
        () => notice.notify(
          any(),
          title: any(named: 'title'),
          text: any(named: 'text'),
          channelName: any(named: 'channelName'),
        ),
      ).thenAnswer((_) async => false);
      await vm().checkOnStartup();
      expect(
        container.read(appUpdateRepositoryProvider).wasNotified('0.6.0'),
        isFalse,
      );
    });
  });

  group('widgets', () {
    Future<void> pump(WidgetTester tester, Widget child) async {
      tester.view
        ..physicalSize = const Size(1200, 2400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      container = await env.container();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: localized(child),
        ),
      );
      await tester.pumpAndSettle();
    }

    setUp(() => env = TestEnv.desktop());

    testWidgets('Home banner: Download, Later and Skip', (tester) async {
      online();
      await pump(tester, const HomeView());
      expect(find.byKey(const Key('home.update')), findsNothing);
      await tester.runAsync(vm().checkOnStartup);
      await tester.pumpAndSettle();
      expect(find.text('Ftube 0.6.0 is available'), findsOneWidget);

      await tester.tap(find.byKey(const Key('home.update.download')));
      await tester.pumpAndSettle();
      verify(() => env.files.openUrl(_release.pageUrl)).called(1);
      expect(find.byKey(const Key('home.update')), findsOneWidget);

      await tester.tap(find.byKey(const Key('home.update.later')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home.update')), findsNothing);
    });

    testWidgets('Home banner: Skip saves the version', (tester) async {
      online();
      await pump(tester, const HomeView());
      await tester.runAsync(vm().checkOnStartup);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home.update.skip')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home.update')), findsNothing);
      expect(container.read(appUpdateRepositoryProvider).skipped, '0.6.0');
    });

    testWidgets('What\'s new renders the notes as Markdown', (tester) async {
      online();
      await pump(tester, const HomeView());
      await tester.runAsync(vm().checkOnStartup);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home.update.notes')));
      await tester.pumpAndSettle();
      expect(find.text('Added'), findsOneWidget);
      expect(find.textContaining('**'), findsNothing);
      expect(
        find.textContaining('Update notice', findRichText: true),
        findsOne,
      );
      await tester.tap(find.byKey(const Key('update.notes.download')));
      await tester.pumpAndSettle();
      verify(() => env.files.openUrl(_release.pageUrl)).called(1);
    });

    testWidgets('a failed Download shows a SnackBar', (tester) async {
      online();
      when(() => env.files.openUrl(any())).thenThrow(const Unsupported('x'));
      await pump(tester, const HomeView());
      await tester.runAsync(vm().checkOnStartup);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home.update.download')));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't open the browser."), findsOneWidget);
    });

    testWidgets('Settings check: up to date, available, failed', (
      tester,
    ) async {
      await pump(tester, const SettingsView());
      final tile = find.byKey(const Key('settings.checkUpdate'));
      await tester.ensureVisible(tile);

      await tester.tap(tile);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't check for updates"), findsOneWidget);

      online(
        AppRelease(
          version: '0.1.0',
          tag: 'v0.1.0',
          pageUrl: _release.pageUrl,
          notes: '',
        ),
      );
      await tester.tap(tile);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.text('Up to date'), findsOneWidget);

      online();
      await tester.tap(tile);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.text('Ftube 0.6.0 is available'), findsOneWidget);
      await tester.tap(find.byKey(const Key('settings.update.download')));
      await tester.pumpAndSettle();
      verify(() => env.files.openUrl(_release.pageUrl)).called(1);
    });
  });
}
