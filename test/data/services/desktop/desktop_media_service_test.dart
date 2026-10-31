import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/data/services/binary_service.dart';
import 'package:ftube/data/services/desktop/desktop_media_service.dart';
import 'package:ftube/data/services/process_runner.dart';
import 'package:ftube/domain/exceptions/ftube_exception.dart';
import 'package:ftube/domain/models/models.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;

import 'fakes.dart';

void main() {
  late Directory root;
  late Directory bin;
  late Directory out;
  late Directory temp;
  late MockProcessRunner runner;
  late DesktopMediaService service;

  String binPath(String name) => p.join(bin.path, name);

  setUp(() {
    root = Directory.systemTemp.createTempSync('ftube_dms_test');
    bin = Directory(p.join(root.path, 'bin'))..createSync();
    out = Directory(p.join(root.path, 'out'));
    temp = Directory(p.join(root.path, 'tmp'));
    for (final name in ['yt-dlp_linux', 'ffmpeg', 'ffprobe', 'deno']) {
      File(binPath(name)).createSync();
    }
    runner = MockProcessRunner();
    service = DesktopMediaService(
      binaries: BinaryService(
        os: DesktopOs.linux,
        bundledDir: bin,
        supportDir: Directory(p.join(root.path, 'support')),
        runner: runner,
      ),
      runner: runner,
      tempRoot: temp,
    );
  });

  tearDown(() => root.deleteSync(recursive: true));

  /// Makes the next `start` return [process] and records its arguments.
  List<String> Function() onStart(FakeProcess process) {
    late List<String> args;
    when(() => runner.start(any(), any())).thenAnswer((inv) async {
      args = inv.positionalArguments[1] as List<String>;
      process.markStarted();
      return process;
    });
    return () => args;
  }

  DownloadRequest request(QualityPreset preset, {String jobId = 'j1'}) =>
      DownloadRequest(
        jobId: jobId,
        url: 'https://www.youtube.com/watch?v=jNQXAC9IVRw',
        preset: preset,
        outDir: out,
      );

  group('fetchInfo', () {
    test('rejects invalid URLs without running yt-dlp', () async {
      for (final url in ['', 'not a url', 'ftp://x.test/a', 'https://']) {
        await expectLater(service.fetchInfo(url), throwsA(isA<InvalidUrl>()));
      }
      verifyNever(() => runner.run(any(), any()));
    });

    test('runs yt-dlp -J with bundled ffmpeg and deno', () async {
      final json = File('test/fixtures/yt_dlp/info_video.json')
          .readAsStringSync();
      when(() => runner.run(binPath('yt-dlp_linux'), any()))
          .thenAnswer((_) async => ProcessOutput(0, json, ''));

      final info = await service.fetchInfo('https://youtu.be/aqz-KE-bpKQ');

      expect(info.title, startsWith('Big Buck Bunny'));
      final args =
          verify(() => runner.run(binPath('yt-dlp_linux'), captureAny()))
                  .captured
                  .single
              as List<String>;
      expect(args, containsAllInOrder(['--ffmpeg-location', bin.path]));
      expect(
        args,
        containsAllInOrder(['--js-runtimes', 'deno:${binPath('deno')}']),
      );
      expect(args.last, 'https://youtu.be/aqz-KE-bpKQ');
    });

    test('works without deno', () async {
      File(binPath('deno')).deleteSync();
      when(
        () => runner.run(any(), any()),
      ).thenAnswer((_) async => const ProcessOutput(0, '{"title": "t"}', ''));
      await service.fetchInfo('https://x.test/v');
      final args =
          verify(() => runner.run(any(), captureAny())).captured.single
              as List<String>;
      expect(args, isNot(contains('--js-runtimes')));
    });

    test('maps yt-dlp failures', () async {
      when(() => runner.run(any(), any())).thenAnswer(
        (_) async => const ProcessOutput(1, '', 'ERROR: Unsupported URL: x'),
      );
      await expectLater(
        service.fetchInfo('https://x.test/v'),
        throwsA(isA<Unsupported>()),
      );
    });

    test(
      'BinaryMissing when yt-dlp or ffmpeg is absent or not runnable',
      () async {
        when(() => runner.run(any(), any()))
            .thenThrow(const ProcessException('yt-dlp', []));
        await expectLater(
          service.fetchInfo('https://x.test/v'),
          throwsA(isA<BinaryMissing>()),
        );

        File(binPath('ffmpeg')).deleteSync();
        await expectLater(
          service.fetchInfo('https://x.test/v'),
          throwsA(
            isA<BinaryMissing>().having((e) => e.binary, 'binary', 'ffmpeg'),
          ),
        );
      },
    );
  });

  group('download', () {
    test('replays a real capture as weighted progress', () async {
      final process = FakeProcess();
      final args = onStart(process);
      final events = <JobProgress>[];
      final done = service
          .download(request(QualityPreset.best))
          .listen(events.add)
          .asFuture<void>();

      await process.started;
      await pumpEventQueue();
      expect(temp.listSync().single.path, p.join(temp.path, 'j1'));
      expect(out.existsSync(), isTrue);
      for (final line in File(
        'test/fixtures/yt_dlp/progress_video_audio.txt',
      ).readAsLinesSync()) {
        process.out(line);
      }
      // stdout and stderr are separate pipes; let stdout drain first, as
      // yt-dlp finishes downloading before it starts the merger.
      await pumpEventQueue();
      process
        ..err('FTUBE_PP|started|Merger')
        ..err('FTUBE_PP|finished|Merger');
      await process.finish(0);
      await done;

      expect(args(), containsAllInOrder(['-P', 'temp:${temp.path}/j1']));
      final phases = events.map((e) => e.phase).toSet();
      expect(phases, {
        JobPhase.downloadingVideo,
        JobPhase.downloadingAudio,
        JobPhase.merging,
        JobPhase.finished,
      });
      final fractions = events.map((e) => e.fraction!).toList();
      expect(fractions, orderedEquals([...fractions]..sort()));
      expect(events.first.totalBytes, 195278);
      expect(events.last.fraction, 1);
      expect(
        events.last.outputPath,
        '/home/user/Downloads/Ftube/Me_at_the_zoo.mp4',
      );
      expect(temp.listSync(), isEmpty, reason: 'job temp folder removed');
    });

    test('audio presets report download then conversion', () async {
      final process = FakeProcess();
      onStart(process);
      final events = <JobProgress>[];
      final done = service
          .download(request(QualityPreset.audioMp3))
          .listen(events.add)
          .asFuture<void>();
      await process.started;
      await pumpEventQueue();
      process
        ..out('FTUBE|downloading|50|100|NA|1|1|none')
        ..err('FTUBE_PP|started|ExtractAudio')
        ..out('FTUBE_FILE|/out/song.mp3');
      await process.finish(0);
      await done;

      expect(events.map((e) => (e.phase, e.fraction)), [
        (JobPhase.downloadingAudio, 0.45),
        (JobPhase.converting, 0.9),
        (JobPhase.finished, 1.0),
      ]);
      expect(events.last.outputPath, '/out/song.mp3');
    });

    test('non-zero exit becomes a typed error and cleans up', () async {
      final process = FakeProcess();
      onStart(process);
      final result = service.download(request(QualityPreset.p720)).toList();
      await process.started;
      await pumpEventQueue();
      process.err('ERROR: [youtube] x: Video unavailable');
      await process.finish(1);

      await expectLater(
        result,
        throwsA(
          isA<ProcessFailed>().having(
            (e) => e.stderrTail,
            'stderrTail',
            contains('Video unavailable'),
          ),
        ),
      );
      expect(temp.listSync(), isEmpty);
    });

    test('invalid URL fails before starting', () async {
      final req = request(QualityPreset.best).copyWith(url: 'nope');
      await expectLater(
        service.download(req).toList(),
        throwsA(isA<InvalidUrl>()),
      );
      verifyNever(() => runner.start(any(), any()));
    });

    test('missing binary or start failure gives BinaryMissing', () async {
      when(() => runner.start(any(), any()))
          .thenThrow(const ProcessException('yt', []));
      await expectLater(
        service.download(request(QualityPreset.best)).toList(),
        throwsA(isA<BinaryMissing>()),
      );
    });

    test('rejects a second stream for a running job id', () async {
      final process = FakeProcess();
      onStart(process);
      final first = service.download(request(QualityPreset.best)).toList();
      await process.started;
      await pumpEventQueue();
      await expectLater(
        service.download(request(QualityPreset.best)).toList(),
        throwsStateError,
      );
      await process.finish(0);
      await first;
    });
  });

  group('cancel', () {
    test('kills the process and ends the stream with Cancelled', () async {
      final process = FakeProcess();
      onStart(process);
      final result = service.download(request(QualityPreset.best)).toList();
      await process.started;
      await pumpEventQueue();
      process.out('FTUBE|downloading|1|10|NA|1|1|avc1');

      await service.cancel('j1');

      await expectLater(result, throwsA(isA<Cancelled>()));
      expect(process.killCount, 1);
      expect(temp.listSync(), isEmpty);
    });

    test('before the process starts, it never runs for long', () async {
      final process = FakeProcess();
      final called = Completer<void>();
      final started = Completer<RunningProcess>();
      when(() => runner.start(any(), any())).thenAnswer((_) {
        called.complete();
        return started.future;
      });
      final result = service.download(request(QualityPreset.best)).toList();
      await called.future;

      await service.cancel('j1');
      started.complete(process);

      await expectLater(result, throwsA(isA<Cancelled>()));
      expect(process.killCount, 1);
    });

    test('cancelling the subscription cancels the job', () async {
      final process = FakeProcess();
      onStart(process);
      final sub = service.download(request(QualityPreset.best)).listen(null);
      await process.started;
      await pumpEventQueue();
      await sub.cancel();
      expect(process.killCount, 1);
    });

    test('ignores unknown ids', () async {
      await service.cancel('nope');
    });
  });

  group('convert', () {
    late File src;
    late File dst;

    setUp(() {
      src = File(p.join(root.path, 'in.mkv'))..writeAsStringSync('x');
      dst = File(p.join(root.path, 'out.mp3'));
      when(() => runner.run(binPath('ffprobe'), any()))
          .thenAnswer((_) async => const ProcessOutput(0, '10.0\n', ''));
    });

    test('reports progress from ffmpeg and finishes with dst', () async {
      final process = FakeProcess();
      final args = onStart(process);
      final events = <JobProgress>[];
      final done = service
          .convert(src, AudioTarget.mp3, dst, jobId: 'c1')
          .listen(events.add)
          .asFuture<void>();
      await process.started;
      await pumpEventQueue();
      process
        ..out('out_time_us=2500000')
        ..out('progress=continue')
        ..out('out_time_us=10000000')
        ..out('progress=end');
      await process.finish(0);
      await done;

      expect(args().last, dst.path);
      expect(events.map((e) => (e.jobId, e.phase, e.fraction)), [
        ('c1', JobPhase.converting, 0.0),
        ('c1', JobPhase.converting, 0.25),
        ('c1', JobPhase.converting, 1.0),
        ('c1', JobPhase.finished, 1.0),
      ]);
      expect(events.last.outputPath, dst.path);
    });

    test('unknown duration still converts, without fractions', () async {
      when(() => runner.run(binPath('ffprobe'), any()))
          .thenAnswer((_) async => const ProcessOutput(1, '', 'bad'));
      final process = FakeProcess();
      onStart(process);
      final events = <JobProgress>[];
      final done = service
          .convert(src, AudioTarget.ogg, dst, jobId: 'c1')
          .listen(events.add)
          .asFuture<void>();
      await process.started;
      await pumpEventQueue();
      process.out('out_time_us=2500000');
      await process.finish(0);
      await done;
      expect(events.map((e) => e.phase), [
        JobPhase.converting,
        JobPhase.finished,
      ]);
    });

    test('failure deletes the partial output', () async {
      final process = FakeProcess();
      onStart(process);
      final result = service
          .convert(src, AudioTarget.mp3, dst, jobId: 'c1')
          .toList();
      await process.started;
      await pumpEventQueue();
      dst.writeAsStringSync('partial');
      process.err('Error opening output');
      await process.finish(1);

      await expectLater(result, throwsA(isA<ProcessFailed>()));
      expect(dst.existsSync(), isFalse);
    });

    test('cancel keeps a file that existed before', () async {
      dst.writeAsStringSync('old');
      final process = FakeProcess();
      onStart(process);
      final result = service
          .convert(src, AudioTarget.mp3, dst, jobId: 'c1')
          .toList();
      await process.started;
      await pumpEventQueue();
      await service.cancel('c1');

      await expectLater(result, throwsA(isA<Cancelled>()));
      expect(dst.existsSync(), isTrue);
    });
  });
}
