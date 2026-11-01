import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/data/services/ffmpeg_args.dart';
import 'package:ftube/data/services/progress_weights.dart';
import 'package:ftube/domain/models/models.dart';

void main() {
  group('FfmpegArgs', () {
    test('convert uses the ftube.sh codec settings', () {
      expect(FfmpegArgs.convert('in.mkv', AudioTarget.mp3, 'out.mp3'), [
        '-hide_banner',
        '-nostdin',
        '-y',
        '-i',
        'in.mkv',
        '-vn',
        '-acodec',
        'libmp3lame',
        '-ac',
        '2',
        '-b:a',
        '320k',
        '-progress',
        'pipe:1',
        '-nostats',
        'out.mp3',
      ]);
      expect(
        FfmpegArgs.convert('a', AudioTarget.ogg, 'b'),
        containsAllInOrder(['-acodec', 'libvorbis']),
      );
    });

    test('convert can leave out the stdout progress pipe', () {
      final args = FfmpegArgs.convert(
        'a',
        AudioTarget.mp3,
        'b',
        pipeProgress: false,
      );
      expect(args, isNot(contains('-progress')));
      expect(args, isNot(contains('pipe:1')));
      expect(args.last, 'b');
    });

    test('mux copies the first video and the second audio stream', () {
      expect(FfmpegArgs.mux('v.mp4', 'a.m4a', 'out.mp4'), [
        '-hide_banner',
        '-nostdin',
        '-y',
        '-i',
        'v.mp4',
        '-i',
        'a.m4a',
        '-map',
        '0:v:0',
        '-map',
        '1:a:0',
        '-c',
        'copy',
        'out.mp4',
      ]);
    });

    test('probeDuration ends with the source', () {
      expect(FfmpegArgs.probeDuration('in.mkv').last, 'in.mkv');
    });

    test('parseDuration', () {
      expect(
        FfmpegArgs.parseDuration('12.500000\n'),
        const Duration(milliseconds: 12500),
      );
      expect(FfmpegArgs.parseDuration('N/A'), isNull);
      expect(FfmpegArgs.parseDuration('0'), isNull);
    });

    test('parseOutTime', () {
      expect(
        FfmpegArgs.parseOutTime('out_time_us=2500000'),
        const Duration(milliseconds: 2500),
      );
      expect(FfmpegArgs.parseOutTime('out_time_us=N/A'), isNull);
      expect(FfmpegArgs.parseOutTime('progress=continue'), isNull);
    });
  });

  group('ProgressWeights', () {
    double w(JobPhase p, double f, {bool audio = false, bool conv = false}) =>
        ProgressWeights.overall(p, f, audioOnly: audio, conversionOnly: conv);

    test('video job: 0-80, 80-95, 95-100', () {
      expect(w(JobPhase.downloadingVideo, 0), 0);
      expect(w(JobPhase.downloadingVideo, 1), 0.8);
      expect(w(JobPhase.downloadingAudio, 0), 0.8);
      expect(w(JobPhase.downloadingAudio, 1), closeTo(0.95, 1e-9));
      expect(w(JobPhase.merging, 0), 0.95);
      expect(w(JobPhase.finished, 0), 1);
    });

    test('audio job: 0-90, then conversion 90-100', () {
      expect(w(JobPhase.downloadingAudio, 0.5, audio: true), 0.45);
      expect(w(JobPhase.converting, 0, audio: true), 0.9);
      expect(w(JobPhase.converting, 1, audio: true), 1);
    });

    test('a local conversion uses the whole range and clamps', () {
      expect(w(JobPhase.converting, 0.5, conv: true), 0.5);
      expect(w(JobPhase.converting, 7, conv: true), 1);
      expect(w(JobPhase.converting, -1, conv: true), 0);
    });
  });
}
