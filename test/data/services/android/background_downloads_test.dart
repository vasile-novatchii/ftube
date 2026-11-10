import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/data/repositories/download_repository.dart';
import 'package:ftube/data/services/android/background_downloads.dart';
import 'package:ftube/data/services/android/notification_permission.dart';
import 'package:ftube/data/services/prefs_service.dart';
import 'package:ftube/domain/exceptions/ftube_exception.dart';
import 'package:ftube/domain/models/models.dart';
import 'package:ftube/l10n/generated/app_localizations.dart';

import '../../../ui/helpers.dart';
import '../../repositories/fake_media_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = BackgroundDownloads.channel;
  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final l10n = lookupAppLocalizations(const Locale('en'));

  late FakeMediaService media;
  late DownloadRepository repo;
  late List<MethodCall> calls;
  late int permissionRequests;

  late PrefsService prefs;
  BackgroundDownloads? bg;

  setUp(() async {
    calls = [];
    permissionRequests = 0;
    prefs = await testPrefs();
    media = FakeMediaService();
    repo = DownloadRepository(media);
    messenger
      ..setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      })
      ..setMockMethodCallHandler(permissions, (call) async {
        if (call.method == 'requestPermissions') permissionRequests++;
        return {17: 1};
      });
  });

  tearDown(() async {
    bg = null;
    await repo.dispose();
    messenger
      ..setMockMethodCallHandler(channel, null)
      ..setMockMethodCallHandler(permissions, null);
  });

  /// Disposes in the test body, so no cooldown timer outlives the test.
  /// Not awaited: the timer goes at once, the rest finishes in [tearDown].
  void end() => unawaited(bg?.dispose());

  BackgroundDownloads begin({bool withPermission = true}) =>
      bg = BackgroundDownloads(
        repository: repo,
        l10n: () => l10n,
        notifications: withPermission ? NotificationPermission(prefs) : null,
      )..start();

  DownloadJob add(String title) => repo.enqueue(
    url: 'https://youtu.be/$title',
    title: title,
    preset: QualityPreset.best,
    outDir: Directory('/out'),
  );

  List<MethodCall> named(String method) =>
      calls.where((c) => c.method == method).toList();

  Map<Object?, Object?> args(MethodCall c) => c.arguments as Map;

  /// Sends a call from the Kotlin side, like the notification action.
  Future<void> fromKotlin(String method) => messenger.handlePlatformMessage(
    channel.name,
    const StandardMethodCodec().encodeMethodCall(MethodCall(method)),
    (_) {},
  );

  testWidgets('sends nothing while the queue is idle', (tester) async {
    begin();
    await tester.pump(const Duration(seconds: 2));
    expect(calls, isEmpty);
    expect(bg!.active, isFalse);
    end();
  });

  testWidgets('first job starts the service with translated texts', (
    tester,
  ) async {
    begin();
    add('Video A');
    await tester.pump();
    final update = named('update').single;
    expect(args(update), {
      'title': 'Downloading 1 of 1',
      'text': 'Video A',
      'percent': null,
      'strings': {
        'progressChannel': 'Downloads in progress',
        'resultChannel': 'Finished downloads',
        'cancelAll': 'Cancel all',
        'pauseAll': 'Pause all',
        'resumeAll': 'Resume all',
        'timedOut': l10n.bgTimedOut,
      },
    });
    expect(bg!.active, isTrue);
    expect(permissionRequests, 1);
    end();
  });

  testWidgets('updates at most once a second, with the latest progress', (
    tester,
  ) async {
    begin();
    final job = add('a');
    await tester.pump();
    media
      ..progress(job.id, 0.1)
      ..progress(job.id, 0.3);
    await tester.pump();
    media.progress(job.id, 0.5);
    await tester.pump(const Duration(milliseconds: 500));
    expect(named('update'), hasLength(1));

    await tester.pump(const Duration(milliseconds: 500));
    expect(named('update'), hasLength(2));
    expect(args(named('update').last)['percent'], 50);
    expect(args(named('update').last)['title'], 'Downloading 1 of 1 - 50%');

    await tester.pump(const Duration(seconds: 2));
    expect(named('update'), hasLength(2));
    end();
  });

  testWidgets('counts jobs and stops with the result', (tester) async {
    begin();
    final a = add('a');
    final b = add('b');
    await tester.pump(const Duration(seconds: 1));
    media.finish(a.id);
    await tester.pump(const Duration(seconds: 1));
    expect(args(named('update').last)['title'], 'Downloading 2 of 2');
    expect(args(named('update').last)['text'], 'b');

    media.fail(b.id, const Network());
    await tester.pump();
    expect(args(named('stop').single), {
      'title': '1 download finished',
      'text': '1 download failed',
    });
    expect(bg!.active, isFalse);

    // The next job starts a new session, without asking again.
    add('c');
    await tester.pump(const Duration(seconds: 1));
    expect(args(named('update').last)['title'], 'Downloading 1 of 1');
    expect(permissionRequests, 1);
    end();
  });

  testWidgets('only failures put them in the title', (tester) async {
    begin();
    media.fail(add('a').id, const Network());
    await tester.pump();
    expect(args(named('stop').single), {
      'title': '1 download failed',
      'text': null,
    });
    end();
  });

  testWidgets('Cancel all cancels active jobs and posts no result', (
    tester,
  ) async {
    begin();
    final a = add('a');
    final b = add('b');
    final c = add('c');
    await tester.pump();

    await fromKotlin('cancelAll');
    await tester.pump();
    expect([a, b, c].map((j) => repo.job(j.id)!.status), [
      JobStatus.cancelled,
      JobStatus.cancelled,
      JobStatus.cancelled,
    ]);
    expect(args(named('stop').single), {'title': null, 'text': null});
    end();
  });

  testWidgets('Pause all leaves a paused notification', (tester) async {
    begin();
    final a = add('a');
    final b = add('b');
    final c = add('c');
    await tester.pump();

    await fromKotlin('pauseAll');
    await tester.pump();
    expect([a, b, c].map((j) => repo.job(j.id)!.status), [
      JobStatus.paused,
      JobStatus.paused,
      JobStatus.paused,
    ]);
    expect(media.paused, [a.id, b.id]);
    expect(args(named('paused').last), {
      'title': '3 downloads paused',
      'text': 'a',
    });
    expect(named('stop'), isEmpty);
    expect(bg!.active, isTrue);

    calls.clear();
    await fromKotlin('resumeAll');
    await tester.pump();
    expect(repo.job(a.id)!.status, JobStatus.running);
    expect(repo.job(c.id)!.status, JobStatus.queued);
    expect(args(named('update').single)['title'], 'Downloading 1 of 3');
    end();
  });

  testWidgets('Resume all with nothing paused stops the service', (
    tester,
  ) async {
    begin();
    await fromKotlin('resumeAll');
    await tester.pump();
    expect(args(named('stop').single), {'title': null, 'text': null});
    end();
  });

  testWidgets('Cancel all also cancels paused jobs', (tester) async {
    begin();
    final a = add('a');
    final b = add('b');
    await tester.pump();
    await repo.pause(a.id);
    await tester.pump();
    await fromKotlin('cancelAll');
    await tester.pump();
    expect(repo.job(a.id)!.status, JobStatus.cancelled);
    expect(repo.job(b.id)!.status, JobStatus.cancelled);
    expect(media.cancelled, containsAll([a.id, b.id]));
    expect(args(named('stop').single), {'title': null, 'text': null});
    end();
  });

  testWidgets('a paused job does not count as done', (tester) async {
    begin();
    final a = add('a');
    add('b');
    await tester.pump();
    await repo.pause(a.id);
    await tester.pump(const Duration(seconds: 1));
    expect(args(named('update').last)['title'], 'Downloading 1 of 2');
    end();
  });

  testWidgets('a retried job counts again', (tester) async {
    begin(withPermission: false);
    final a = add('a');
    final b = add('b');
    await tester.pump();
    media.fail(a.id, const Network());
    await tester.pump();
    repo.retry(a.id);
    await tester.pump(const Duration(seconds: 1));
    media
      ..finish(b.id)
      ..finish(a.id);
    await tester.pump();
    expect(args(named('stop').single), {
      'title': '2 downloads finished',
      'text': null,
    });
    expect(permissionRequests, 0);
    end();
  });

  testWidgets('a missing Kotlin side is ignored', (tester) async {
    begin();
    messenger.setMockMethodCallHandler(channel, null);
    final job = add('a');
    await tester.pump();
    media.finish(job.id);
    await tester.pump();
    expect(bg!.active, isFalse);
    end();
  });

  testWidgets('unknown calls from Kotlin are rejected', (tester) async {
    begin();
    ByteData? reply;
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(const MethodCall('nope')),
      (data) => reply = data,
    );
    expect(reply, isNull);
    end();
  });

  group('summarize', () {
    DownloadJob job(String id, JobStatus status, [double? fraction]) =>
        DownloadJob(
          request: DownloadRequest(
            jobId: id,
            url: 'u',
            preset: QualityPreset.best,
            outDir: Directory('/out'),
          ),
          title: id,
          createdAt: DateTime.utc(2026),
          status: status,
          progress: fraction == null
              ? null
              : JobProgress(
                  jobId: id,
                  phase: JobPhase.downloadingVideo,
                  fraction: fraction,
                ),
        );

    test('averages running jobs with known progress', () {
      final active = [
        job('a', JobStatus.running, 0.2),
        job('b', JobStatus.running, 0.5),
        job('c', JobStatus.running),
        job('d', JobStatus.queued),
      ];
      final s = BackgroundDownloads.summarize({
        'x': JobStatus.completed,
        for (final j in active) j.id: j.status,
      }, active);
      expect((s.current, s.total, s.percent, s.title), (2, 5, 35, 'a'));
    });

    test('uses the first queued job when none runs', () {
      final active = [job('q', JobStatus.queued)];
      final s = BackgroundDownloads.summarize({'q': JobStatus.queued}, active);
      expect((s.current, s.total, s.percent, s.title), (1, 1, null, 'q'));
    });
  });
}
