import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/config/providers.dart';
import 'package:ftube/data/repositories/download_repository.dart';
import 'package:ftube/domain/exceptions/ftube_exception.dart';
import 'package:ftube/domain/models/models.dart';
import 'package:ftube/ui/queue/widgets/queue_view.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers.dart';

void main() {
  late TestEnv env;
  late ProviderContainer container;

  DownloadRepository repo() => container.read(downloadRepositoryProvider);

  DownloadJob add(
    String title, {
    QualityPreset preset = QualityPreset.best,
    String? formatId,
  }) => repo().enqueue(
    url: 'https://youtu.be/$title',
    title: title,
    preset: preset,
    formatId: formatId,
    outDir: Directory('/out'),
  );

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
          const Scaffold(body: QueueView()),
          locale: locale,
          themeMode: themeMode,
        ),
      ),
    );
    await tester.pump();
  }

  void progress(
    DownloadJob job, {
    JobPhase phase = JobPhase.downloadingVideo,
    double? fraction,
    double? speed,
    Duration? eta,
  }) => env.media.runs[job.id]!.add(
    JobProgress(
      jobId: job.id,
      phase: phase,
      fraction: fraction,
      speedBps: speed,
      eta: eta,
    ),
  );

  Finder key(String k) => find.byKey(Key(k));

  group('desktop', () {
    setUp(() => env = TestEnv.desktop());

    for (final (locale, themeMode, title, empty) in [
      (const Locale('en'), ThemeMode.light, 'Queue (0)', 'No downloads yet.'),
      (
        const Locale('ro'),
        ThemeMode.dark,
        'Coadă (0)',
        'Nicio descărcare încă.',
      ),
      (
        const Locale('ar'),
        ThemeMode.light,
        'قائمة الانتظار (0)',
        'لا توجد تنزيلات بعد.',
      ),
    ]) {
      testWidgets('empty (${locale.languageCode}, ${themeMode.name})', (
        tester,
      ) async {
        await pump(tester, locale: locale, themeMode: themeMode);
        expect(find.text(title), findsOneWidget);
        expect(find.text(empty), findsOneWidget);
        expect(key('queue.clear'), findsNothing);
      });
    }

    testWidgets('lists jobs newest first with their state', (tester) async {
      await pump(tester);
      final a = add('a');
      add('b', preset: QualityPreset.custom, formatId: '137+ba');
      add('c', preset: QualityPreset.audioMp3);
      await tester.pump();
      expect(find.text('Queue (3)'), findsOneWidget);
      expect(find.text('a · Best'), findsOneWidget);
      expect(find.text('b · 137+ba'), findsOneWidget);
      expect(find.text('c · MP3'), findsOneWidget);
      final titles = tester
          .widgetList<Text>(find.textContaining(' · '))
          .map((t) => t.data!.split(' ').first)
          .where((t) => t.length == 1)
          .toList();
      expect(titles, ['c', 'b', 'a']);
      expect(find.text('Waiting...'), findsOneWidget);
      expect(find.text('Starting...'), findsNWidgets(2));

      progress(
        a,
        fraction: 0.425,
        speed: 2 * 1024 * 1024,
        eta: const Duration(seconds: 75),
      );
      await tester.pump();
      expect(find.textContaining('Downloading video · 42% · '), findsOneWidget);
      expect(find.textContaining('/s · 1:15'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator).last,
      );
      expect(bar.value, 0.425);

      progress(a, phase: JobPhase.merging);
      await tester.pump();
      expect(find.text('Merging...'), findsOneWidget);
    });

    testWidgets('cancel, retry, remove and clear', (tester) async {
      await pump(tester);
      final a = add('a');
      final b = add('b');
      await tester.pump();

      await tester.tap(key('queue.cancel.${a.id}'));
      await tester.pump();
      expect(find.text('Cancelled'), findsOneWidget);
      expect(key('queue.retry.${a.id}'), findsOneWidget);
      expect(key('queue.remove.${a.id}'), findsOneWidget);

      await tester.tap(key('queue.retry.${a.id}'));
      await tester.pump();
      expect(find.text('Cancelled'), findsNothing);

      await tester.tap(key('queue.cancel.${a.id}'));
      await tester.pump();
      await tester.tap(key('queue.remove.${a.id}'));
      await tester.pump();
      expect(find.text('Queue (1)'), findsOneWidget);

      env.media.finish(b.id);
      await tester.pump();
      expect(find.text('Done'), findsOneWidget);
      expect(key('queue.retry.${b.id}'), findsNothing);
      await tester.tap(key('queue.clear'));
      await tester.pump();
      expect(find.text('Queue (0)'), findsOneWidget);
    });

    testWidgets('Cancel queued shows only with waiting jobs', (tester) async {
      await pump(tester);
      final a = add('a');
      add('b');
      final c = add('c');
      await tester.pump();
      expect(key('queue.cancelQueued'), findsOneWidget);
      await tester.tap(key('queue.cancelQueued'));
      await tester.pump();
      expect(repo().job(a.id)!.status, JobStatus.running);
      expect(repo().job(c.id)!.status, JobStatus.cancelled);
      expect(key('queue.cancelQueued'), findsNothing);
    });

    testWidgets('Clear all asks before stopping downloads', (tester) async {
      await pump(tester);
      expect(key('queue.clearAll'), findsNothing);
      add('a');
      add('b');
      await tester.pump();
      await tester.tap(key('queue.clearAll'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Stop 2 downloads and clear the list?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(repo().jobs, hasLength(2));

      await tester.tap(key('queue.clearAll'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(key('queue.confirmClearAll'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(repo().jobs, isEmpty);
      expect(key('queue.clearAll'), findsNothing);
    });

    testWidgets('Clear all of finished jobs does not ask', (tester) async {
      await pump(tester);
      final a = add('a');
      env.media.finish(a.id);
      await tester.pumpAndSettle();
      await tester.tap(key('queue.clearAll'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(repo().jobs, isEmpty);
    });

    testWidgets('pause and resume a job', (tester) async {
      await pump(tester);
      final a = add('a');
      await tester.pump();
      progress(a, fraction: 0.43);
      await tester.pump();

      await tester.tap(key('queue.pause.${a.id}'));
      await tester.pump();
      expect(find.text('Paused · 43%'), findsOneWidget);
      expect(env.media.paused, [a.id]);
      expect(key('queue.pause.${a.id}'), findsNothing);
      expect(key('queue.retry.${a.id}'), findsNothing);
      expect(key('queue.cancel.${a.id}'), findsOneWidget);

      await tester.tap(key('queue.resume.${a.id}'));
      await tester.pump();
      expect(find.text('Paused · 43%'), findsNothing);
      expect(key('queue.pause.${a.id}'), findsOneWidget);
      expect(env.media.started, [a.id, a.id]);
    });

    testWidgets('a failed job shows the error and can be retried', (
      tester,
    ) async {
      await pump(tester);
      final a = add('a');
      await tester.pump();
      env.media.fail(a.id, const Network());
      await tester.pump();
      final details = tester.widget<Text>(
        find.text('Could not reach the server. Check your connection.'),
      );
      final theme = Theme.of(tester.element(find.byType(QueueView)));
      expect(details.style?.color, theme.colorScheme.error);
      expect(key('queue.retry.${a.id}'), findsOneWidget);
    });

    testWidgets('opens a finished file', (tester) async {
      when(() => env.files.open(any())).thenAnswer((_) async {});
      await pump(tester);
      final a = add('a');
      await tester.pump();
      expect(key('queue.open.${a.id}'), findsNothing);
      env.media.finish(a.id, '/out/a.mp4');
      await tester.pump();
      await tester.tap(key('queue.open.${a.id}'));
      await tester.pump();
      verify(() => env.files.open('/out/a.mp4')).called(1);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a file that will not open shows a message', (tester) async {
      when(() => env.files.open(any()))
          .thenAnswer((_) async => throw const FileError());
      await pump(tester);
      final a = add('a');
      await tester.pump();
      env.media.finish(a.id);
      await tester.pump();
      await tester.tap(key('queue.open.${a.id}'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  testWidgets('android opens a finished file', (tester) async {
    env = TestEnv.android();
    when(() => env.files.open(any())).thenAnswer((_) async {});
    await pump(tester);
    final a = add('a');
    await tester.pump();
    env.media.finish(a.id, '/out/a.mp4');
    await tester.pump();
    expect(find.text('Done'), findsOneWidget);
    await tester.tap(key('queue.open.${a.id}'));
    await tester.pump();
    verify(() => env.files.open('/out/a.mp4')).called(1);
  });

  testWidgets('no open button where open is unavailable', (tester) async {
    env = TestEnv.android();
    when(() => env.files.canOpen).thenReturn(false);
    await pump(tester);
    final a = add('a');
    await tester.pump();
    env.media.finish(a.id);
    await tester.pump();
    expect(find.text('Done'), findsOneWidget);
    expect(key('queue.open.${a.id}'), findsNothing);
  });
}
