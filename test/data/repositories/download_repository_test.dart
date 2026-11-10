import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/data/repositories/download_repository.dart';
import 'package:ftube/domain/exceptions/ftube_exception.dart';
import 'package:ftube/domain/models/models.dart';

import 'fake_media_service.dart';

void main() {
  late FakeMediaService media;
  late DownloadRepository repo;
  final out = Directory('/out');

  DownloadJob add([String title = 'a', QualityPreset? preset]) => repo.enqueue(
    url: 'https://youtu.be/$title',
    title: title,
    preset: preset ?? QualityPreset.best,
    outDir: out,
  );

  JobStatus status(DownloadJob job) => repo.job(job.id)!.status;

  /// Lets the media streams deliver their events.
  Future<void> settle() => pumpEventQueue();

  setUp(() {
    media = FakeMediaService();
    repo = DownloadRepository(media, now: () => DateTime.utc(2026, 11));
  });

  tearDown(() => repo.dispose());

  group('enqueueAll', () {
    test('adds one job per item in order with one emit', () {
      var emits = 0;
      repo.changes.listen((_) => emits++);
      final jobs = repo.enqueueAll(
        [
          (url: 'u/a', title: 'a'),
          (url: 'u/b', title: 'b'),
          (url: 'u/c', title: 'c'),
        ],
        preset: QualityPreset.audioMp3,
        outDir: out,
      );
      expect(jobs.map((j) => j.title), ['a', 'b', 'c']);
      expect(jobs.map((j) => j.request.url), ['u/a', 'u/b', 'u/c']);
      expect(jobs.map((j) => j.id).toSet(), hasLength(3));
      expect(
        jobs.every((j) => j.request.preset == QualityPreset.audioMp3),
        isTrue,
      );
      expect(jobs.map(status), [
        JobStatus.running,
        JobStatus.running,
        JobStatus.queued,
      ]);
      // One add for all three, then one per start.
      expect(emits, 3);
    });

    test('an empty list adds nothing', () {
      var emits = 0;
      repo.changes.listen((_) => emits++);
      expect(
        repo.enqueueAll(const [], preset: QualityPreset.best, outDir: out),
        isEmpty,
      );
      expect(emits, 0);
    });
  });

  group('cancelQueued', () {
    test('cancels only queued jobs', () async {
      final jobs = [add('a'), add('b'), add('c'), add('d')];
      await repo.pause(jobs[1].id);
      await settle();
      // a and c run, b is paused, d waits.
      expect(jobs.map(status), [
        JobStatus.running,
        JobStatus.paused,
        JobStatus.running,
        JobStatus.queued,
      ]);
      await repo.cancelQueued();
      expect(jobs.map(status), [
        JobStatus.running,
        JobStatus.paused,
        JobStatus.running,
        JobStatus.cancelled,
      ]);
      expect(media.cancelled, isEmpty);
    });
  });

  group('clearAll', () {
    test('stops every unfinished job and removes all', () async {
      final jobs = [add('a'), add('b'), add('c'), add('d')];
      await repo.pause(jobs[1].id);
      await settle();
      media.finish(jobs[0].id);
      await settle();
      final events = <List<DownloadJob>>[];
      final sub = repo.changes.listen(events.add);
      await repo.clearAll();
      await settle();
      expect(repo.jobs, isEmpty);
      expect(events.last, isEmpty);
      expect(media.cancelled.toSet(), {jobs[1].id, jobs[2].id, jobs[3].id});
      await sub.cancel();
    });

    test('does nothing on an empty queue', () async {
      final events = <List<DownloadJob>>[];
      final sub = repo.changes.listen(events.add);
      await repo.clearAll();
      await settle();
      expect(events, isEmpty);
      await sub.cancel();
    });
  });

  group('enqueue', () {
    test('starts jobs up to the limit, in order', () async {
      final jobs = [add('a'), add('b'), add('c')];
      expect(jobs.map((j) => j.id).toSet(), hasLength(3));
      expect(jobs.map(status), [
        JobStatus.running,
        JobStatus.running,
        JobStatus.queued,
      ]);
      expect(media.started, [jobs[0].id, jobs[1].id]);
      expect(repo.activeCount, 3);

      final first = jobs.first;
      expect(first.title, 'a');
      expect(first.createdAt, DateTime.utc(2026, 11));
      expect(first.request.url, 'https://youtu.be/a');
      expect(first.request.outDir, out);
    });

    test('passes the preset and format id', () {
      final job = repo.enqueue(
        url: 'u',
        title: 't',
        preset: QualityPreset.custom,
        formatId: '137+140',
        outDir: out,
      );
      expect(job.request.preset, QualityPreset.custom);
      expect(job.request.formatId, '137+140');
    });

    test('emits the job list on every change', () async {
      final events = <List<JobStatus>>[];
      repo.changes.listen(
        (jobs) => events.add([for (final j in jobs) j.status]),
      );
      final job = add();
      media.progress(job.id, 0.5);
      await settle();
      media.finish(job.id);
      await settle();
      expect(events, [
        [JobStatus.queued],
        [JobStatus.running],
        [JobStatus.running], // 50%
        [JobStatus.running], // finished update
        [JobStatus.completed],
      ]);
    });
  });

  group('running', () {
    test('progress updates the job', () async {
      final job = add();
      media.progress(job.id, 0.25);
      await settle();
      expect(repo.job(job.id)!.progress!.fraction, 0.25);
    });

    test('finished completes the job and starts the next one', () async {
      repo.maxConcurrent = 1;
      final a = add('a');
      final b = add('b');
      expect(status(b), JobStatus.queued);
      media.finish(a.id, '/out/a.mp4');
      await settle();
      expect(status(a), JobStatus.completed);
      expect(repo.job(a.id)!.outputPath, '/out/a.mp4');
      expect(status(b), JobStatus.running);
    });

    test('a typed error fails the job with that error', () async {
      final job = add();
      media.fail(job.id, const Network('offline'));
      await settle();
      expect(status(job), JobStatus.failed);
      expect(repo.job(job.id)!.error, isA<Network>());
    });

    test('an untyped error becomes Unexpected', () async {
      final job = add();
      media.fail(job.id, StateError('boom'));
      await settle();
      expect(repo.job(job.id)!.error, isA<Unexpected>());
    });

    test('a stream that ends without a result fails', () async {
      final job = add();
      media.close(job.id);
      await settle();
      expect(status(job), JobStatus.failed);
      expect(repo.job(job.id)!.error, isA<Unexpected>());
    });

    test('a Cancelled error from the service cancels the job', () async {
      final job = add();
      media.fail(job.id, const Cancelled());
      await settle();
      expect(status(job), JobStatus.cancelled);
    });
  });

  group('cancel', () {
    test('a queued job is cancelled without touching the service', () async {
      repo.maxConcurrent = 1;
      add('a');
      final b = add('b');
      await repo.cancel(b.id);
      expect(status(b), JobStatus.cancelled);
      expect(media.cancelled, isEmpty);
    });

    test('a running job shows cancelled at once', () async {
      media.endOnCancel = false;
      final job = add();
      await repo.cancel(job.id);
      expect(status(job), JobStatus.cancelled);
      expect(repo.job(job.id)!.error, isA<Cancelled>());
      expect(media.cancelled, [job.id]);
    });

    test('the slot is freed only when the service has stopped', () async {
      media.endOnCancel = false;
      repo.maxConcurrent = 1;
      final a = add('a');
      final b = add('b');
      await repo.cancel(a.id);
      await settle();
      expect(status(b), JobStatus.queued);

      media.fail(a.id, const Cancelled());
      await settle();
      expect(status(a), JobStatus.cancelled);
      expect(status(b), JobStatus.running);
    });

    test('a late result after cancel is ignored', () async {
      media.endOnCancel = false;
      final job = add();
      await repo.cancel(job.id);
      media.finish(job.id);
      await settle();
      expect(status(job), JobStatus.cancelled);
    });

    test('finished jobs and unknown ids are ignored', () async {
      final job = add();
      media.finish(job.id);
      await settle();
      await repo.cancel(job.id);
      await repo.cancel('nope');
      expect(status(job), JobStatus.completed);
      expect(media.cancelled, isEmpty);
    });
  });

  group('retry', () {
    test('requeues a failed job and clears its error', () async {
      final job = add();
      media
        ..progress(job.id, 0.5)
        ..fail(job.id, const Network());
      await settle();
      repo.retry(job.id);
      final retried = repo.job(job.id)!;
      expect(retried.status, JobStatus.running);
      expect(retried.error, isNull);
      expect(retried.progress, isNull);
      expect(media.started, [job.id, job.id]);
    });

    test('waits for a cancelled run to stop before starting again', () async {
      media.endOnCancel = false;
      final job = add();
      await repo.cancel(job.id);
      repo.retry(job.id);
      expect(status(job), JobStatus.queued);
      expect(media.started, [job.id]);

      media.fail(job.id, const Cancelled());
      await settle();
      expect(status(job), JobStatus.running);
      expect(media.started, [job.id, job.id]);
    });

    test('ignores running, completed and unknown jobs', () async {
      final a = add('a');
      final b = add('b');
      media.finish(b.id);
      await settle();
      repo
        ..retry(a.id)
        ..retry(b.id)
        ..retry('nope');
      expect(status(a), JobStatus.running);
      expect(status(b), JobStatus.completed);
    });
  });

  group('remove and clear', () {
    test('remove drops finished jobs only', () async {
      final a = add('a');
      final b = add('b');
      media.fail(b.id, const Network());
      await settle();
      repo
        ..remove(a.id)
        ..remove(b.id)
        ..remove('nope');
      expect(repo.jobs.map((j) => j.id), [a.id]);
    });

    test('clearFinished drops completed jobs only', () async {
      final a = add('a');
      final b = add('b');
      final c = add('c');
      media
        ..finish(a.id)
        ..fail(b.id, const Network());
      await settle();
      var events = 0;
      repo.changes.listen((_) => events++);
      repo.clearFinished();
      expect(repo.jobs.map((j) => j.id), [b.id, c.id]);
      expect(events, 1);
      repo.clearFinished();
      expect(events, 1);
    });

    test('a removed job ignores its stopping run', () async {
      media.endOnCancel = false;
      final job = add();
      await repo.cancel(job.id);
      repo.remove(job.id);
      media.fail(job.id, const Cancelled());
      await settle();
      expect(repo.jobs, isEmpty);
    });
  });

  group('maxConcurrent', () {
    test('is clamped to 1..3', () {
      repo.maxConcurrent = 0;
      expect(repo.maxConcurrent, 1);
      repo.maxConcurrent = 9;
      expect(repo.maxConcurrent, 3);
      expect(DownloadRepository(media, maxConcurrent: 7).maxConcurrent, 3);
    });

    test('raising it starts queued jobs', () {
      repo.maxConcurrent = 1;
      final jobs = [add('a'), add('b'), add('c')];
      repo.maxConcurrent = 3;
      expect(jobs.map(status), everyElement(JobStatus.running));
    });

    test('lowering it lets running jobs finish', () async {
      final a = add('a');
      final b = add('b');
      final c = add('c');
      repo.maxConcurrent = 1;
      expect(status(b), JobStatus.running);
      media.finish(a.id);
      await settle();
      expect(status(c), JobStatus.queued);
      media.finish(b.id);
      await settle();
      expect(status(c), JobStatus.running);
    });
  });

  group('pause and resume', () {
    test('a queued job pauses without touching the service', () async {
      add('a');
      add('b');
      final c = add('c');
      await repo.pause(c.id);
      expect(status(c), JobStatus.paused);
      expect(media.paused, isEmpty);
      expect(repo.activeCount, 2);
    });

    test('a running job keeps its progress and frees its slot', () async {
      repo.maxConcurrent = 1;
      final a = add('a');
      final b = add('b');
      await settle();
      media.progress(a.id, 0.4);
      await settle();
      await repo.pause(a.id);
      await settle();
      expect(status(a), JobStatus.paused);
      expect(repo.job(a.id)!.progress?.fraction, 0.4);
      expect(repo.job(a.id)!.error, isNull);
      expect(media.paused, [a.id]);
      expect(status(b), JobStatus.running);
    });

    test('resume puts the job back in its place', () async {
      repo.maxConcurrent = 1;
      final a = add('a');
      final b = add('b');
      final c = add('c');
      await settle();
      await repo.pause(a.id);
      await settle();
      repo.resume(a.id);
      expect(status(a), JobStatus.queued);
      media.finish(b.id);
      await settle();
      // a was queued before c, so it runs first, with the same id.
      expect(status(a), JobStatus.running);
      expect(status(c), JobStatus.queued);
      expect(media.started.where((id) => id == a.id), hasLength(2));
    });

    test('resume waits for the paused run to stop', () async {
      media.endOnCancel = false;
      final a = add('a');
      await settle();
      await repo.pause(a.id);
      repo.resume(a.id);
      expect(status(a), JobStatus.queued);
      expect(media.started, [a.id]);
      media.fail(a.id, const Paused());
      await settle();
      expect(status(a), JobStatus.running);
      expect(media.started, [a.id, a.id]);
    });

    test('pauseAll and resumeAll', () async {
      final jobs = [add('a'), add('b'), add('c')];
      await repo.pauseAll();
      await settle();
      expect(jobs.map(status).toSet(), {JobStatus.paused});
      expect(repo.activeCount, 0);
      repo.resumeAll();
      await settle();
      expect(jobs.map(status), [
        JobStatus.running,
        JobStatus.running,
        JobStatus.queued,
      ]);
    });

    test('ignores jobs that cannot be paused or resumed', () async {
      final a = add('a');
      await settle();
      media.finish(a.id);
      await settle();
      await repo.pause(a.id);
      await repo.pause('nope');
      repo
        ..resume(a.id)
        ..resume('nope');
      expect(status(a), JobStatus.completed);
      expect(media.paused, isEmpty);
    });

    test('cancel and remove of a paused job drop its files', () async {
      final a = add('a');
      final b = add('b');
      await settle();
      await repo.pause(a.id);
      await repo.pause(b.id);
      await settle();
      await repo.cancel(a.id);
      expect(status(a), JobStatus.cancelled);
      repo.remove(b.id);
      expect(repo.job(b.id), isNull);
      expect(media.cancelled, [a.id, b.id]);
    });

    test(
      'cancel of a resumed job that has not restarted drops its files',
      () async {
        repo.maxConcurrent = 1;
        final a = add('a');
        add('b');
        await settle();
        media.progress(a.id, 0.5);
        await settle();
        await repo.pause(a.id);
        await settle();
        repo.resume(a.id);
        await repo.cancel(a.id);
        expect(media.cancelled, [a.id]);
      },
    );

    test('a Paused error from the service pauses a running job', () async {
      final a = add('a');
      await settle();
      media.fail(a.id, const Paused());
      await settle();
      expect(status(a), JobStatus.paused);
    });
  });

  test('dispose stops running jobs and rejects new ones', () async {
    final job = add();
    var closed = false;
    repo.changes.listen(null, onDone: () => closed = true);
    await repo.dispose();
    expect(media.isRunning(job.id), isFalse);
    expect(closed, isTrue);
    expect(add, throwsStateError);
    expect(() => repo.retry(job.id), throwsStateError);
    await repo.dispose();
  });
}
