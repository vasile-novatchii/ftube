import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/data/services/binaries/binary_installer.dart';
import 'package:ftube/data/services/binary_service.dart';
import 'package:ftube/domain/exceptions/ftube_exception.dart';
import 'package:ftube/ui/setup/widgets/setup_view.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers.dart';

void main() {
  late TestEnv env;
  late StreamController<InstallProgress> events;

  setUp(() {
    env = TestEnv.desktop();
    events = StreamController();
    // close() waits for a listener, which some tests never add.
    addTearDown(() => unawaited(events.close()));
    when(() => env.installer.missing()).thenAnswer(
      (_) async => [entry(Binary.ffmpeg, 3 << 20), entry(Binary.deno, 1 << 20)],
    );
    when(() => env.installer.install()).thenAnswer((_) => events.stream);
  });

  Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    ThemeMode themeMode = ThemeMode.light,
  }) async {
    final container = await env.container();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: localized(
          const SetupView(),
          locale: locale,
          themeMode: themeMode,
        ),
      ),
    );
    await tester.pump();
  }

  for (final (locale, button) in [
    (const Locale('en'), 'Download tools'),
    (const Locale('ro'), 'Descarcă instrumentele'),
    (const Locale('ar'), 'تنزيل الأدوات'),
  ]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('offers the install in ${locale.languageCode} ${mode.name}', (
        tester,
      ) async {
        await pump(tester, locale: locale, themeMode: mode);
        expect(find.text(button), findsOneWidget);
        expect(find.textContaining('4.0 MB'), findsOneWidget);
      });
    }
  }

  testWidgets('shows the checking state first', (tester) async {
    final missing = Completer<List<Never>>();
    when(() => env.installer.missing()).thenAnswer((_) => missing.future);
    await pump(tester);
    expect(find.text('Checking the download tools...'), findsOneWidget);
    missing.complete([]);
  });

  testWidgets('installs with progress and can cancel', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('setup.install')));
    await tester.pump();
    expect(find.byKey(const Key('setup.cancel')), findsOneWidget);

    events.add(
      const InstallProgress(
        binary: Binary.ffmpeg,
        phase: InstallPhase.downloading,
        receivedBytes: 1 << 20,
        totalBytes: 4 << 20,
      ),
    );
    await tester.pump();
    expect(find.text('Downloading ffmpeg...'), findsOneWidget);
    expect(find.text('1.0 MB of 4.0 MB'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, 0.25);

    events.add(
      const InstallProgress(
        binary: Binary.ffmpeg,
        phase: InstallPhase.unpacking,
        receivedBytes: 3 << 20,
        totalBytes: 4 << 20,
      ),
    );
    await tester.pump();
    expect(find.text('Unpacking ffmpeg...'), findsOneWidget);

    await tester.tap(find.byKey(const Key('setup.cancel')));
    // A cancelled subscription completes in the root zone, outside the
    // fake clock.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('setup.install')), findsOneWidget);
  });

  testWidgets('shows failures with Retry', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('setup.install')));
    await tester.pump();
    events.addError(const Network('offline'));
    await tester.pump();
    expect(find.text('Setup did not finish.'), findsOneWidget);
    expect(
      find.text('Could not reach the server. Check your connection.'),
      findsOneWidget,
    );

    when(() => env.installer.missing()).thenAnswer((_) async => []);
    await tester.tap(find.byKey(const Key('setup.retry')));
    await tester.pump();
    verify(() => env.installer.missing()).called(2);
  });
}
