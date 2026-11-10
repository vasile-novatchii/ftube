import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/config/providers.dart';
import 'package:ftube/data/repositories/download_repository.dart';
import 'package:ftube/domain/exceptions/ftube_exception.dart';
import 'package:ftube/domain/models/models.dart';
import 'package:ftube/ui/queue/view_model/queue_view_model.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers.dart';

void main() {
  late TestEnv env;
  late ProviderContainer c;

  QueueViewModel vm() => c.read(queueViewModelProvider.notifier);
  QueueState state() => c.read(queueViewModelProvider);
  DownloadRepository repo() => c.read(downloadRepositoryProvider);

  DownloadJob add(String title) => repo().enqueue(
    url: 'https://youtu.be/$title',
    title: title,
    preset: QualityPreset.best,
    outDir: Directory('/out'),
  );

  Future<void> start(TestEnv e) async {
    env = e;
    c = await env.container();
    c.listen(queueViewModelProvider, (_, _) {});
    c.listen(activeDownloadCountProvider, (_, _) {});
  }

  group('desktop', () {
    setUp(() => start(TestEnv.desktop()));

    test('starts empty', () {
      expect(state().jobs, isEmpty);
      expect(state().canOpen, isTrue);
      expect(state().hasCompleted, isFalse);
      expect(c.read(activeDownloadCountProvider), 0);
    });

    test('follows the queue', () async {
      final a = add('a');
      add('b');
      add('c');
      expect(state().jobs.map((j) => j.title), ['a', 'b', 'c']);
      expect(c.read(activeDownloadCountProvider), 3);

      env.media.finish(a.id);
      await pumpEventQueue();
      expect(state().hasCompleted, isTrue);
      expect(c.read(activeDownloadCountProvider), 2);

      vm().clearFinished();
      expect(state().jobs.map((j) => j.title), ['b', 'c']);
    });

    test('cancelQueued cancels the waiting jobs', () async {
      final a = add('a');
      add('b');
      final c = add('c');
      expect(state().hasQueued, isTrue);
      await vm().cancelQueued();
      expect(state().hasQueued, isFalse);
      expect(repo().job(a.id)!.status, JobStatus.running);
      expect(repo().job(c.id)!.status, JobStatus.cancelled);
    });

    test('clearAll stops and removes every job', () async {
      final a = add('a');
      add('b');
      env.media.finish(a.id);
      await pumpEventQueue();
      expect(state().unfinishedCount, 1);
      await vm().clearAll();
      await pumpEventQueue();
      expect(state().jobs, isEmpty);
      expect(state().unfinishedCount, 0);
    });

    test('cancel, retry and remove', () async {
      final a = add('a');
      await vm().cancel(a.id);
      await pumpEventQueue();
      expect(state().jobs.single.status, JobStatus.cancelled);

      vm().retry(a.id);
      expect(state().jobs.single.status, JobStatus.running);

      await vm().cancel(a.id);
      await pumpEventQueue();
      vm().remove(a.id);
      expect(state().jobs, isEmpty);
    });

    test('open passes the finished file to the system', () async {
      when(() => env.files.open(any())).thenAnswer((_) async {});
      final a = add('a');
      env.media.finish(a.id, '/out/a.mp4');
      await pumpEventQueue();
      expect(await vm().open(state().jobs.single), isNull);
      verify(() => env.files.open('/out/a.mp4')).called(1);
    });

    test('open returns the error', () async {
      when(() => env.files.open(any()))
          .thenAnswer((_) async => throw const FileError());
      final a = add('a');
      env.media.finish(a.id);
      await pumpEventQueue();
      expect(await vm().open(state().jobs.single), isA<FileError>());
    });

    test('open without a file does nothing', () async {
      expect(await vm().open(add('a')), isNull);
      verifyNever(() => env.files.open(any()));
    });
  });

  test('files are not opened where open is unavailable', () async {
    final e = TestEnv.android();
    when(() => e.files.canOpen).thenReturn(false);
    await start(e);
    expect(state().canOpen, isFalse);
    final a = add('a');
    env.media.finish(a.id);
    await pumpEventQueue();
    expect(await vm().open(state().jobs.single), isNull);
    verifyNever(() => env.files.open(any()));
  });
}
