import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/data/services/android/android_media_service.dart';
import 'package:ftube/data/services/android/storage_permission_service.dart';
import 'package:ftube/domain/exceptions/ftube_exception.dart';
import 'package:ftube/domain/models/models.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;

import 'fakes.dart';

class MockStorage extends Mock implements StoragePermissionService {}

void main() {
  const url = 'https://www.youtube.com/watch?v=abc123def45';

  late Directory root;
  late Directory out;
  late Directory temp;
  late FakeYtDlpBridge ytDlp;
  late FakeFfmpegRunner ffmpeg;
  late MockStorage storage;
  late AndroidMediaService service;

  setUp(() {
    root = Directory.systemTemp.createTempSync('ftube_ams_test');
    out = Directory(p.join(root.path, 'Download', 'Ftube'));
    temp = Directory(p.join(root.path, 'cache'));
    ytDlp = FakeYtDlpBridge();
    ffmpeg = FakeFfmpegRunner();
    storage = MockStorage();
    when(() => storage.ensureGranted()).thenAnswer((_) async {});
    when(() => storage.scanFile(any())).thenAnswer((_) async {});
    service = AndroidMediaService(
      ytDlp: ytDlp,
      ffmpeg: ffmpeg,
      tempRoot: temp,
      storage: storage,
    );
  });

  tearDown(() => root.deleteSync(recursive: true));

  DownloadRequest request(
    QualityPreset preset, {
    String jobId = 'j1',
    String? formatId,
  }) => DownloadRequest(
    jobId: jobId,
    url: url,
    preset: preset,
    outDir: out,
    formatId: formatId,
  );

  bool tempIsEmpty() =>
      !temp.existsSync() || temp.listSync(recursive: true).isEmpty;

  Future<Object?> errorOf(Stream<JobProgress> s) =>
      s.drain<void>().then<Object?>((_) => null, onError: (Object e) => e);

  group('fetchInfo', () {
    test('rejects invalid URLs without running yt-dlp', () async {
      for (final u in ['', 'not a url', 'ftp://x.test/a', 'https://']) {
        await expectLater(service.fetchInfo(u), throwsA(isA<InvalidUrl>()));
      }
      expect(ytDlp.runs, isEmpty);
    });

    test('parses yt-dlp -J for any site', () async {
      final info =
          await service.fetchInfo(' https://vimeo.com/1 ') as MediaInfo;
      expect(info.url, 'https://vimeo.com/1');
      expect(info.title, 'Big Buck Bunny');
      expect(info.uploader, 'Blender');
      expect(info.duration, const Duration(seconds: 10));
      expect(info.formats.map((f) => f.id), ['18', '140']);
      expect(ytDlp.runs.single, containsAllInOrder(['-J', '--']));
      expect(ytDlp.runs.single.last, 'https://vimeo.com/1');
    });

    test('maps a failed run', () async {
      ytDlp
        ..exitCode = 1
        ..stderr = 'ERROR: Unsupported URL: https://x.test';
      await expectLater(
        service.fetchInfo('https://x.test'),
        throwsA(isA<Unsupported>()),
      );
    });

    test('reads the playlist of a link when asked', () async {
      await service.fetchInfo(url, playlist: true);
      expect(ytDlp.runs.single, contains('--yes-playlist'));
    });

    test('updates yt-dlp once per launch, after the first info', () async {
      await service.fetchInfo(url);
      expect(ytDlp.runs, hasLength(1));
      expect(ytDlp.updateCalls, 0);
      await pumpEventQueue();
      expect(ytDlp.updateCalls, 1);
      await service.download(request(QualityPreset.best)).drain<void>();
      await service.fetchInfo(url);
      expect(ytDlp.updateCalls, 1);
    });

    test('a download updates before its first run', () async {
      await service.download(request(QualityPreset.best)).drain<void>();
      expect(ytDlp.updateCalls, 1);
    });

    test('the update waits for info runs in flight', () async {
      ytDlp.infoHold = Completer<void>();
      final info = service.fetchInfo(url);
      await pumpEventQueue();
      final download = service
          .download(request(QualityPreset.best))
          .drain<void>();
      await pumpEventQueue();
      expect(ytDlp.updateCalls, 0);
      expect(ytDlp.runs, hasLength(1));
      ytDlp.infoHold!.complete();
      await info;
      await download;
      expect(ytDlp.updateCalls, 1);
      expect(ytDlp.runs, hasLength(2));
    });

    test('a failure with the old yt-dlp retries after the update', () async {
      ytDlp
        ..exitCode = 1
        ..stderr = 'ERROR: [youtube] abc: Sign in to confirm';
      await expectLater(service.fetchInfo(url), throwsA(isA<FtubeException>()));
      expect(ytDlp.runs, hasLength(2));
      expect(ytDlp.updateCalls, 1);

      ytDlp.exitCode = 0;
      await service.fetchInfo(url);
      expect(ytDlp.runs, hasLength(3));
    });

    test('a network failure does not wait for the update', () async {
      ytDlp
        ..exitCode = 1
        ..stderr = 'ERROR: TransportError: timed out';
      await expectLater(service.fetchInfo(url), throwsA(isA<Network>()));
      expect(ytDlp.runs, hasLength(1));
      expect(ytDlp.updateCalls, 0);
    });

    test('a failed update is ignored and tried again next time', () async {
      ytDlp.updateError = const Network('offline');
      await service.fetchInfo(url);
      await pumpEventQueue();
      ytDlp.updateError = null;
      await service.fetchInfo(url);
      await pumpEventQueue();
      await service.fetchInfo(url);
      expect(ytDlp.updateCalls, 2);
    });
  });

  group('download', () {
    test('p1080 downloads video and audio, then muxes them', () async {
      final events = await service
          .download(request(QualityPreset.p1080))
          .toList();

      final phases = events.map((e) => e.phase).toSet().toList();
      expect(phases, [
        JobPhase.downloadingVideo,
        JobPhase.downloadingAudio,
        JobPhase.merging,
        JobPhase.finished,
      ]);
      final fractions = events.map((e) => e.fraction!).toList();
      expect(fractions, orderedEquals([...fractions]..sort()));
      final lastVideo = events.lastWhere(
        (e) => e.phase == JobPhase.downloadingVideo,
      );
      expect(lastVideo.fraction, closeTo(0.8, 1e-9));
      expect(lastVideo.downloadedBytes, 2000);
      expect(
        events.lastWhere((e) => e.phase == JobPhase.downloadingAudio).fraction,
        closeTo(0.95, 1e-9),
      );

      final dst = p.join(out.path, 'Big Buck Bunny： 60fps 4K!.mp4');
      expect(events.last.outputPath, dst);
      expect(File(dst).readAsStringSync(), 'ffmpeg output');
      final args = ytDlp.runs.single;
      expect(
        args,
        containsAllInOrder(['-f', 'bv*[height<=1080]+ba/b[height<=1080]']),
      );
      expect(args, isNot(contains('-x')));
      final mux = ffmpeg.calls.single;
      expect(mux, containsAllInOrder(['-c', 'copy']));
      expect(p.basename(mux[mux.indexOf('-i') + 1]), 'media.f137.mp4');
      expect(p.basename(mux[mux.lastIndexOf('-i') + 1]), 'media.f140.m4a');
      expect(tempIsEmpty(), isTrue);
      verify(() => storage.scanFile(dst)).called(1);
    });

    test('WebM video with M4A audio muxes into MKV', () async {
      ytDlp.parts = const [
        FakePart('248', 'webm'),
        FakePart('140', 'm4a', audio: true),
      ];
      final last = await service.download(request(QualityPreset.best)).last;
      expect(last.outputPath, endsWith('Big Buck Bunny： 60fps 4K!.mkv'));
    });

    test('finds the parts without Destination lines', () async {
      ytDlp.announce = false;
      final last = await service.download(request(QualityPreset.best)).last;
      expect(last.outputPath, endsWith('.mp4'));
      expect(ffmpeg.calls.single, contains('-c'));
    });

    test('audio presets convert the downloaded audio', () async {
      ytDlp.parts = const [FakePart('251', 'webm', audio: true, size: 600)];
      final events = await service
          .download(request(QualityPreset.audioOgg))
          .toList();

      expect(ytDlp.runs.single, containsAllInOrder(['-f', 'ba/b']));
      final args = ffmpeg.calls.single;
      expect(args, containsAllInOrder(['-acodec', 'libvorbis']));
      expect(args, isNot(contains('-progress')));
      final converting = events.where((e) => e.phase == JobPhase.converting);
      expect(converting.map((e) => e.fraction), [
        closeTo(0.9, 1e-9),
        closeTo(0.95, 1e-9),
      ]);
      expect(events.last.outputPath, endsWith('Big Buck Bunny： 60fps 4K!.ogg'));
      expect(tempIsEmpty(), isTrue);
    });

    test('M4A moves the audio stream without ffmpeg', () async {
      ytDlp.parts = const [FakePart('140', 'm4a', audio: true, size: 500)];
      final last = await service.download(request(QualityPreset.audioM4a)).last;
      expect(ytDlp.runs.single, containsAllInOrder(['-f', 'ba[ext=m4a]/ba/b']));
      expect(last.outputPath, endsWith('Big Buck Bunny： 60fps 4K!.m4a'));
      expect(ffmpeg.calls, isEmpty);
      expect(tempIsEmpty(), isTrue);
    });

    test('a single non-audio file is moved without ffmpeg', () async {
      ytDlp.parts = const [FakePart('18', 'mp4')];
      final last = await service
          .download(request(QualityPreset.custom, formatId: '18'))
          .last;
      expect(last.outputPath, endsWith('.mp4'));
      expect(File(last.outputPath!).lengthSync(), 1000);
      expect(ffmpeg.calls, isEmpty);
    });

    test('names the file "video" when yt-dlp prints no title', () async {
      ytDlp
        ..title = ''
        ..parts = const [FakePart('18', 'mp4')];
      final last = await service.download(request(QualityPreset.best)).last;
      expect(p.basename(last.outputPath!), 'video.mp4');
    });

    test('never overwrites an existing file', () async {
      out.createSync(recursive: true);
      File(p.join(out.path, 'Big Buck Bunny： 60fps 4K!.mp4'))
          .writeAsStringSync('old');

      final last = await service.download(request(QualityPreset.best)).last;

      expect(last.outputPath, endsWith('Big Buck Bunny： 60fps 4K! (2).mp4'));
      expect(
        File(p.join(out.path, 'Big Buck Bunny： 60fps 4K!.mp4'))
            .readAsStringSync(),
        'old',
      );
    });

    test('rejects URLs before checking storage', () async {
      await expectLater(
        service.download(
          DownloadRequest(
            jobId: 'j1',
            url: 'nope',
            preset: QualityPreset.best,
            outDir: out,
          ),
        ),
        emitsError(isA<InvalidUrl>()),
      );
      verifyNever(() => storage.ensureGranted());
    });

    test('fails with StoragePermission without access', () async {
      when(() => storage.ensureGranted())
          .thenThrow(const StoragePermission('denied'));

      await expectLater(
        service.download(request(QualityPreset.best)),
        emitsError(isA<StoragePermission>()),
      );
      expect(ytDlp.runs, isEmpty);
    });

    test('a failed yt-dlp run is mapped and leaves no files', () async {
      ytDlp
        ..exitCode = 1
        ..stderr = 'ERROR: unable to download video data: Connection reset';
      final err = await errorOf(service.download(request(QualityPreset.best)));
      expect(err, isA<Network>());
      expect(tempIsEmpty(), isTrue);
    });

    test('a run that writes no file is ProcessFailed', () async {
      ytDlp.parts = const [];
      final err = await errorOf(service.download(request(QualityPreset.best)));
      expect(err, isA<ProcessFailed>());
    });

    test('a failed mux is ProcessFailed and leaves no files', () async {
      ffmpeg.returnCode = 1;
      final err = await errorOf(service.download(request(QualityPreset.best)));

      expect(err, isA<ProcessFailed>());
      expect((err! as ProcessFailed).stderrTail, 'ffmpeg log\nlast line');
      expect(tempIsEmpty(), isTrue);
      expect(out.existsSync() && out.listSync().isNotEmpty, isFalse);
    });

    test('a run with no output for idleTimeout fails with Network', () async {
      service = AndroidMediaService(
        ytDlp: ytDlp,
        ffmpeg: ffmpeg,
        tempRoot: temp,
        idleTimeout: const Duration(milliseconds: 50),
      );
      ytDlp.silent = true;
      final err = await errorOf(service.download(request(QualityPreset.best)));
      expect(err, isA<Network>());
      expect(ytDlp.cancelled, ['j1']);
      expect(tempIsEmpty(), isTrue);
    });

    test('cancel during the download stops yt-dlp', () async {
      ytDlp.hold = Completer<void>();
      final events = <JobProgress>[];
      final done = Completer<Object>();
      service
          .download(request(QualityPreset.best))
          .listen(events.add, onError: done.complete);

      await pumpUntil(() => events.isNotEmpty);
      await service.cancel('j1');

      expect(await done.future, isA<Cancelled>());
      expect(ytDlp.cancelled, ['j1']);
      await pumpUntil(tempIsEmpty);
    });

    test('pause stops yt-dlp and keeps the partial files', () async {
      ytDlp.hold = Completer<void>();
      final events = <JobProgress>[];
      final done = Completer<Object>();
      service
          .download(request(QualityPreset.best))
          .listen(events.add, onError: done.complete);

      await pumpUntil(() => events.isNotEmpty);
      final part = File(p.join(temp.path, 'j1', 'media.mp4.part'))
        ..writeAsStringSync('x');
      await service.pause('j1');
      await service.pause('j1');

      expect(await done.future, isA<Paused>());
      expect(ytDlp.cancelled, ['j1']);
      expect(part.existsSync(), isTrue);

      await service.pause('nope');
      await service.cancel('j1');
      expect(tempIsEmpty(), isTrue);
    });

    test('cancel during ffmpeg cancels the session', () async {
      ffmpeg.hold = Completer<void>();
      final done = Completer<Object>();
      service
          .download(request(QualityPreset.best))
          .listen(null, onError: done.complete);

      await pumpUntil(() => ffmpeg.calls.isNotEmpty);
      await service.cancel('j1');

      expect(await done.future, isA<Cancelled>());
      expect(ffmpeg.cancelCount, 1);
      expect(ytDlp.cancelled, isEmpty);
      ffmpeg.hold!.complete();
      expect(tempIsEmpty(), isTrue);
    });

    test('cancelling the subscription cancels the job', () async {
      ytDlp.hold = Completer<void>();
      final sub = service.download(request(QualityPreset.best)).listen(null);
      await pumpUntil(() => ytDlp.runs.isNotEmpty);

      await sub.cancel();

      expect(ytDlp.cancelled, ['j1']);
      await service.cancel('unknown');
    });

    test('a second stream for a running job id is rejected', () async {
      ytDlp.hold = Completer<void>();
      final first = service.download(request(QualityPreset.best)).listen(null);
      addTearDown(first.cancel);
      await pumpUntil(() => ytDlp.runs.isNotEmpty);

      await expectLater(
        service.download(request(QualityPreset.best)),
        emitsError(isA<StateError>()),
      );
      expect(ytDlp.cancelled, isEmpty);
    });
  });

  test('muxExtension follows the yt-dlp merger', () {
    expect(AndroidMediaService.muxExtension('.mp4', '.m4a'), '.mp4');
    expect(AndroidMediaService.muxExtension('.MP4', '.mp4'), '.mp4');
    expect(AndroidMediaService.muxExtension('.webm', '.webm'), '.webm');
    expect(AndroidMediaService.muxExtension('.webm', '.m4a'), '.mkv');
    expect(AndroidMediaService.muxExtension('.mp4', '.webm'), '.mkv');
  });

  group('convert', () {
    late File src;
    late File dst;

    setUp(() {
      src = File(p.join(root.path, 'song.m4a'))..writeAsStringSync('audio');
      dst = File(p.join(root.path, 'song.mp3'));
    });

    test('reports progress over the whole range', () async {
      final events = await service
          .convert(src, AudioTarget.mp3, dst, jobId: 'c1')
          .toList();

      expect(events.map((e) => e.fraction), [0, closeTo(0.5, 1e-9), 1]);
      expect(events.last.phase, JobPhase.finished);
      expect(events.last.outputPath, dst.path);
      expect(dst.readAsStringSync(), 'ffmpeg output');
      expect(
        ffmpeg.calls.single,
        containsAllInOrder(['-acodec', 'libmp3lame']),
      );
      verify(() => storage.scanFile(dst.path)).called(1);
    });

    test('works without a duration', () async {
      ffmpeg.probeError = StateError('probe');
      final events = await service
          .convert(src, AudioTarget.mp3, dst, jobId: 'c1')
          .toList();
      expect(events.map((e) => e.fraction), [0, 1]);
    });

    test('removes a partial output on failure', () async {
      ffmpeg.returnCode = 1;
      ffmpeg.hold = Completer<void>();
      final done = expectLater(
        service.convert(src, AudioTarget.mp3, dst, jobId: 'c1'),
        emitsThrough(emitsError(isA<ProcessFailed>())),
      );
      await pumpUntil(() => ffmpeg.calls.isNotEmpty);
      dst.writeAsStringSync('partial');
      ffmpeg.hold!.complete();
      await done;
      expect(dst.existsSync(), isFalse);
    });

    test('keeps a file that existed before', () async {
      dst.writeAsStringSync('mine');
      ffmpeg.returnCode = 1;
      await expectLater(
        service.convert(src, AudioTarget.mp3, dst, jobId: 'c1'),
        emitsThrough(emitsError(isA<ProcessFailed>())),
      );
      expect(dst.readAsStringSync(), 'mine');
    });

    test('works without a storage service', () async {
      final bare = AndroidMediaService(
        ytDlp: ytDlp,
        ffmpeg: ffmpeg,
        tempRoot: temp,
      );
      final last = await bare
          .convert(src, AudioTarget.ogg, dst, jobId: 'c1')
          .last;
      expect(last.phase, JobPhase.finished);
    });
  });
}

/// Lets queued async work run until [done] holds.
Future<void> pumpUntil(bool Function() done) async {
  for (var i = 0; i < 1000 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(done(), isTrue, reason: 'condition not reached');
}
