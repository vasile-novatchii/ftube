import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/config/providers.dart';
import 'package:ftube/data/services/android/storage_permission_service.dart';
import 'package:ftube/domain/exceptions/ftube_exception.dart';
import 'package:ftube/domain/models/models.dart';
import 'package:ftube/ui/app.dart';
import 'package:ftube/ui/share/widgets/share_view.dart';
import 'package:ftube/ui/shell/app_shell.dart';
import 'package:mocktail/mocktail.dart';

import '../../data/services/android/share_host.dart';
import '../helpers.dart';

const url = 'https://youtu.be/abc';

const info = MediaInfo(
  url: url,
  title: 'Song',
  uploader: 'Band',
  formats: [
    MediaFormat(
      id: '137',
      container: 'mp4',
      kind: FormatKind.videoOnly,
      resolution: '1080p',
      height: 1080,
    ),
    MediaFormat(id: '140', container: 'm4a', kind: FormatKind.audioOnly),
  ],
);

void main() {
  late TestEnv env;
  late ShareHost host;
  late ProviderContainer container;

  List<DownloadJob> jobs() => container.read(downloadRepositoryProvider).jobs;
  Iterable<String> hostCalls() => host.calls.map((c) => c.method);

  /// [pending] is shared before the app starts.
  Future<void> start([String? pending]) async {
    host = ShareHost(pending: pending)..install();
    env = TestEnv.android()
      ..share = host.service
      ..media.onFetch = (_) async => info;
    await host.service.start();
    container = await env.container();
  }

  tearDown(() async {
    container.dispose();
    host.uninstall();
    await host.service.dispose();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const FtubeApp()),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> share(WidgetTester tester, String? text) async {
    await host.show(text);
    await tester.pump();
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pump();
    await tester.pump();
  }

  /// Finishes the queued job, so the Android notification throttle
  /// (BackgroundDownloads) has no timer left.
  Future<void> flush(WidgetTester tester) async {
    await tester.pump();
    env.media.finish(jobs().single.request.jobId);
    await tester.pump(const Duration(seconds: 2));
  }

  group('a share before start', () {
    setUp(() => start('Look https://youtu.be/abc'));

    testWidgets('shows only the popup, then the app once closed', (
      tester,
    ) async {
      await pump(tester);
      expect(find.byType(ShareView), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
      expect(find.byType(AppShell, skipOffstage: false), findsOneWidget);
      expect(find.byKey(const Key('share.title')), findsOneWidget);
      expect(find.text('Song'), findsOneWidget);

      await tap(tester, 'share.close');
      expect(hostCalls(), contains('close'));
      expect(find.byType(ShareView), findsNothing);
      expect(find.byType(AppShell), findsOneWidget);
    });

    testWidgets('queues the best quality by default', (tester) async {
      await pump(tester);
      await tap(tester, 'share.download');
      expect(jobs().single.request.preset, QualityPreset.best);
      expect(host.calls.last.arguments, {'toast': 'Download started'});
      expect(find.byType(ShareView), findsNothing);
      await flush(tester);
    });

    testWidgets('queues audio from the Audio tab', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Audio'));
      await tester.pump();
      expect(find.byKey(const Key('share.preset.best')), findsNothing);
      await tap(tester, 'share.preset.audioOgg');
      await tap(tester, 'share.download');
      expect(jobs().single.request.preset, QualityPreset.audioOgg);
      await flush(tester);
    });

    testWidgets('offers only the chips the video has', (tester) async {
      await pump(tester);
      expect(find.byKey(const Key('share.format')), findsNothing);
      expect(find.byKey(const Key('share.preset.p720')), findsNothing);
      await tap(tester, 'share.preset.p1080');
      final chip = tester.widget<ChoiceChip>(
        find.byKey(const Key('share.preset.best')),
      );
      expect(chip.selected, isFalse);
      await tap(tester, 'share.download');
      expect(jobs().single.request.preset, QualityPreset.p1080);
      await flush(tester);
    });

    testWidgets('tapping outside or Back closes it', (tester) async {
      host.dismissOnClose = false;
      await pump(tester);
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
      expect(hostCalls().where((m) => m == 'close'), hasLength(1));

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(hostCalls().where((m) => m == 'close'), hasLength(2));
      expect(find.byType(ShareView), findsOneWidget);
    });
  });

  group('while the app runs', () {
    setUp(start);

    testWidgets('keeps the app state behind the popup', (tester) async {
      await pump(tester);
      expect(find.byType(ShareView), findsNothing);
      await tester.enterText(find.byKey(const Key('home.url')), 'typed');
      await share(tester, url);
      expect(find.byType(ShareView), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);

      await host.dismissed();
      await tester.pump();
      expect(find.byType(ShareView), findsNothing);
      expect(find.text('typed'), findsOneWidget);
    });

    testWidgets('a share closes app dialogs first', (tester) async {
      await pump(tester);
      final context = tester.element(find.byType(AppShell));
      unawaited(
        showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(title: Text('App dialog')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('App dialog'), findsOneWidget);
      await share(tester, url);
      await tester.pumpAndSettle();
      expect(find.text('App dialog'), findsNothing);
      expect(find.byType(ShareView), findsOneWidget);
    });

    testWidgets('a text without a link offers to open the app', (tester) async {
      await pump(tester);
      await share(tester, 'no link');
      expect(find.text('The shared text has no link.'), findsOneWidget);
      await tap(tester, 'share.openApp');
      expect(hostCalls().last, 'openApp');
      expect(find.byType(ShareView), findsNothing);
    });

    testWidgets('missing storage access offers to open the app', (
      tester,
    ) async {
      when(() => env.storage.status())
          .thenAnswer((_) async => StorageAccess.denied);
      await pump(tester);
      await share(tester, url);
      expect(find.byKey(const Key('share.message')), findsOneWidget);
      expect(find.byKey(const Key('share.openApp')), findsOneWidget);
      expect(env.media.fetched, isEmpty);
    });

    testWidgets('shows the whole popup while loading and errors with Retry', (
      tester,
    ) async {
      final pending = Completer<MediaInfo>();
      env.media.onFetch = (_) => pending.future;
      await pump(tester);
      await host.send('show', {'text': url, 'subject': 'Shared title'});
      await tester.pump();
      expect(find.text('Shared title'), findsOneWidget);
      expect(find.byKey(const Key('share.tabs')), findsOneWidget);
      expect(find.byKey(const Key('share.preset.best')), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byKey(const Key('share.format')), findsNothing);
      final download = tester.widget<ButtonStyleButton>(
        find.byKey(const Key('share.download')),
      );
      expect(download.onPressed, isNotNull);
      pending.completeError(const Network());
      await tester.pump();
      expect(find.byKey(const Key('share.error')), findsOneWidget);
      expect(find.text('Shared title'), findsOneWidget);
      expect(
        tester
            .widget<ButtonStyleButton>(find.byKey(const Key('share.download')))
            .onPressed,
        isNull,
      );

      env.media.onFetch = (_) async => info;
      await tap(tester, 'share.retry');
      expect(find.text('Song'), findsOneWidget);
    });

    testWidgets('a missing folder shows its own message', (tester) async {
      env.failLookups = true;
      await pump(tester);
      await share(tester, url);
      await tap(tester, 'share.download');
      expect(
        find.text('The download folder is not available.'),
        findsOneWidget,
      );
    });
  });
}
