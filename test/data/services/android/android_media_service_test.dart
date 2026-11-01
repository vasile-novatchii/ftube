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
  late FakeYoutubeSource source;
  late FakeFfmpegRunner ffmpeg;
  late MockStorage storage;
  late AndroidMediaService service;

  setUp(() {
    root = Directory.systemTemp.createTempSync('ftube_ams_test');
    out = Directory(p.join(root.path, 'Download', 'Ftube'));
    temp = Directory(p.join(root.path, 'cache'));
    source = FakeYoutubeSource(
      streamList: [
        muxed(18, 'mp4', 360),
        videoOnly(137, 'mp4', 1080, size: 2000),
        videoOnly(248, 'webm', 1080),
        audioOnly(140, 'mp4', 128000, size: 500),
        audioOnly(251, 'webm', 160000, size: 600),
      ],
    );
    ffmpeg = FakeFfmpegRunner();
    storage = MockStorage();
    when(() => storage.ensureGranted()).thenAnswer((_) async {});
    when(() => storage.scanFile(any())).thenAnswer((_) async {});
    service = AndroidMediaService(
      source: source,
      ffmpeg: ffmpeg,
      tempRoot: temp,
      storage: storage,
      progressInterval: Duration.zero,
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

  group('fetchInfo', () {
    test('rejects invalid URLs', () async {
      for (final u in ['', 'not a url', 'ftp://x.test/a', 'https://']) {
        await expectLater(service.fetchInfo(u), throwsA(isA<InvalidUrl>()));
      }
      expect(source.manifestCalls, 0);
    });

    test('rejects URLs that are not YouTube videos', () async {
      await expectLater(
        service.fetchInfo('https://vimeo.com/1'),
        throwsA(isA<Unsupported>()),
      );
    });

    test('maps the video and its formats', () async {
      final info = await service.fetchInfo(' $url ');
      expect(info.url, url);
      expect(info.title, 'Big Buck Bunny: 60fps 4K!');
      expect(info.uploader, 'Blender');
      expect(info.duration, const Duration(seconds: 10));
      expect(info.thumbnailUrl, 'https://img.test/t.jpg');
      expect(info.formats.map((f) => f.id), ['18', '137', '248', '251', '140']);
    });

    test('passes on errors from either request', () async {
      source.streamsError = const Network('offline');
      await expectLater(service.fetchInfo(url), throwsA(isA<Network>()));
      source
        ..streamsError = null
        ..videoError = const Unsupported('private');
      await expectLater(service.fetchInfo(url), throwsA(isA<Unsupported>()));
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
      expect(lastVideo.totalBytes, 2000);
      expect(lastVideo.speedBps, isNotNull);
      expect(
        events.lastWhere((e) => e.phase == JobPhase.downloadingAudio).fraction,
        closeTo(0.95, 1e-9),
      );

      final dst = p.join(out.path, 'Big_Buck_Bunny_60fps_4K.mp4');
      expect(events.last.outputPath, dst);
      expect(File(dst).readAsStringSync(), 'ffmpeg output');
      expect(source.opened, [137, 140]);
      // A fresh manifest for the second stream.
      expect(source.manifestCalls, 2);
      final mux = ffmpeg.calls.single;
      expect(mux, containsAllInOrder(['-c', 'copy']));
      expect(p.basename(mux[mux.indexOf('-i') + 1]), 'video.mp4');
      expect(p.basename(mux[mux.lastIndexOf('-i') + 1]), 'audio.m4a');
      expect(tempIsEmpty(), isTrue);
      verify(() => storage.scanFile(dst)).called(1);
    });

    test('audio presets convert the best audio stream', () async {
      final events = await service
          .download(request(QualityPreset.audioOgg))
          .toList();

      expect(source.opened, [251]);
      expect(source.manifestCalls, 1);
      final args = ffmpeg.calls.single;
      expect(args, containsAllInOrder(['-acodec', 'libvorbis']));
      expect(args, isNot(contains('-progress')));
      final converting = events.where((e) => e.phase == JobPhase.converting);
      expect(converting.map((e) => e.fraction), [
        closeTo(0.9, 1e-9),
        closeTo(0.95, 1e-9),
      ]);
      expect(
        events.lastWhere((e) => e.phase == JobPhase.downloadingAudio).fraction,
        closeTo(0.9, 1e-9),
      );
      expect(events.last.outputPath, endsWith('Big_Buck_Bunny_60fps_4K.ogg'));
      expect(tempIsEmpty(), isTrue);
    });

    test('custom audio-only and muxed formats skip ffmpeg', () async {
      final a = await service
          .download(request(QualityPreset.custom, formatId: '140'))
          .last;
      expect(a.outputPath, endsWith('.m4a'));
      final m = await service
          .download(request(QualityPreset.custom, formatId: '18', jobId: 'j2'))
          .last;
      expect(m.outputPath, endsWith('.mp4'));
      expect(File(m.outputPath!).lengthSync(), 1000);
      expect(ffmpeg.calls, isEmpty);
    });

    test('never overwrites an existing file', () async {
      out.createSync(recursive: true);
      File(p.join(out.path, 'Big_Buck_Bunny_60fps_4K.mp4'))
          .writeAsStringSync('old');

      final last = await service.download(request(QualityPreset.best)).last;

      expect(last.outputPath, endsWith('Big_Buck_Bunny_60fps_4K_2.mp4'));
      expect(
        File(p.join(out.path, 'Big_Buck_Bunny_60fps_4K.mp4'))
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
      expect(source.manifestCalls, 0);
    });

    test('reports Unsupported when no stream fits', () async {
      source.streamList = [audioOnly(140, 'mp4', 1)];
      await expectLater(
        service.download(request(QualityPreset.p720)),
        emitsError(isA<Unsupported>()),
      );
    });

    test('a failed mux is ProcessFailed and leaves no files', () async {
      ffmpeg.returnCode = 1;
      final err = await service
          .download(request(QualityPreset.best))
          .drain<void>()
          .then<Object?>((_) => null, onError: (Object e) => e);

      expect(err, isA<ProcessFailed>());
      expect((err! as ProcessFailed).stderrTail, 'ffmpeg log\nlast line');
      expect(tempIsEmpty(), isTrue);
      expect(out.existsSync() && out.listSync().isNotEmpty, isFalse);
    });

    test('a stream error ends the job and cleans up', () async {
      source.failAfterFirstChunk[137] = const Network('reset');
      await expectLater(
        service.download(request(QualityPreset.best)),
        emitsThrough(emitsError(isA<Network>())),
      );
      expect(tempIsEmpty(), isTrue);
    });

    test('cancel during a transfer ends with Cancelled', () async {
      final live = source.live[137] = StreamController<List<int>>();
      addTearDown(live.close);
      final events = <JobProgress>[];
      final done = Completer<Object>();
      service
          .download(request(QualityPreset.best))
          .listen(events.add, onError: done.complete);

      live.add(List<int>.filled(100, 1));
      await pumpUntil(() => events.isNotEmpty);
      await service.cancel('j1');

      expect(await done.future, isA<Cancelled>());
      expect(source.opened, [137]);
      await pumpUntil(tempIsEmpty);
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
      ffmpeg.hold!.complete();
      expect(tempIsEmpty(), isTrue);
    });

    test('cancelling the subscription cancels the job', () async {
      final live = source.live[137] = StreamController<List<int>>();
      addTearDown(live.close);
      final sub = service.download(request(QualityPreset.best)).listen(null);
      await pumpUntil(() => source.opened.isNotEmpty);

      await sub.cancel();

      expect(live.hasListener, isFalse);
      await service.cancel('unknown');
    });

    test('a second stream for a running job id is rejected', () async {
      final live = source.live[137] = StreamController<List<int>>();
      addTearDown(live.close);
      final first = service.download(request(QualityPreset.best)).listen(null);
      addTearDown(first.cancel);
      await pumpUntil(() => source.opened.isNotEmpty);

      await expectLater(
        service.download(request(QualityPreset.best)),
        emitsError(isA<StateError>()),
      );
      expect(live.hasListener, isTrue);
    });
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
        source: source,
        ffmpeg: ffmpeg,
        tempRoot: temp,
      );
      final last = await bare
          .convert(src, AudioTarget.ogg, dst, jobId: 'c1')
          .last;
      expect(last.phase, JobPhase.finished);
    });
  });

  test('safeFileName keeps only portable characters', () {
    expect(
      AndroidMediaService.safeFileName('Big Buck Bunny: 60fps 4K!'),
      'Big_Buck_Bunny_60fps_4K',
    );
    expect(AndroidMediaService.safeFileName('a/b\\c?.mp4'), 'a_b_c_.mp4');
    expect(AndroidMediaService.safeFileName('...'), 'video');
    expect(AndroidMediaService.safeFileName('Café — été'), 'Caf_t');
    expect(AndroidMediaService.safeFileName('x' * 300).length, 150);
  });
}

/// Lets queued async work run until [done] holds.
Future<void> pumpUntil(bool Function() done) async {
  for (var i = 0; i < 1000 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(done(), isTrue, reason: 'condition not reached');
}
