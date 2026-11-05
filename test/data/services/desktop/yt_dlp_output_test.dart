import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/data/services/desktop/yt_dlp_output.dart';
import 'package:ftube/domain/exceptions/ftube_exception.dart';
import 'package:ftube/domain/models/models.dart';

void main() {
  group('parseLine', () {
    test('parses a real progress capture', () {
      final lines = File('test/fixtures/yt_dlp/progress_video_audio.txt')
          .readAsLinesSync()
          .map(YtDlpOutput.parseLine)
          .toList();

      expect(lines, everyElement(isNotNull));
      final downloads = lines.whereType<YtDlpDownloadLine>().toList();
      expect(downloads.first.isAudio, isFalse);
      expect(downloads.last.isAudio, isTrue);
      expect(downloads.last.finished, isTrue);
      expect(downloads.last.fraction, 1);
      final file = lines.whereType<YtDlpFileLine>().single;
      expect(file.path, '/home/user/Downloads/Ftube/Me_at_the_zoo.mp4');
    });

    test('reads numbers and NA', () {
      final l =
          YtDlpOutput.parseLine(
                'FTUBE|downloading|1024|NA|4096.0|2048.5|7|avc1',
              )!
              as YtDlpDownloadLine;
      expect(l.downloadedBytes, 1024);
      expect(l.totalBytes, 4096, reason: 'falls back to the estimate');
      expect(l.speedBps, 2048.5);
      expect(l.eta, const Duration(seconds: 7));
      expect(l.fraction, 0.25);
      expect(l.isAudio, isFalse);

      final unknown =
          YtDlpOutput.parseLine('FTUBE|downloading|10|NA|NA|NA|NA|NA')!
              as YtDlpDownloadLine;
      expect(unknown.fraction, isNull);
      expect(unknown.eta, isNull);
      expect(unknown.speedBps, isNull);
    });

    test('maps postprocessors to phases', () {
      YtDlpPostprocessLine pp(String s) =>
          YtDlpOutput.parseLine(s)! as YtDlpPostprocessLine;
      expect(pp('FTUBE_PP|started|Merger').phase, JobPhase.merging);
      expect(pp('FTUBE_PP|started|ExtractAudio').phase, JobPhase.converting);
      expect(pp('FTUBE_PP|finished|MoveFiles').phase, isNull);
      expect(pp('FTUBE_PP|finished|Merger').started, isFalse);
    });

    test('keeps a | inside the file path', () {
      final l = YtDlpOutput.parseLine('FTUBE_FILE|/a|b.mp4')! as YtDlpFileLine;
      expect(l.path, '/a|b.mp4');
    });

    test('reads the title and keeps a | inside it', () {
      final l = YtDlpOutput.parseLine('FTUBE_TITLE|A | B')! as YtDlpTitleLine;
      expect(l.title, 'A | B');
    });

    test('reads a download destination', () {
      final l =
          YtDlpOutput.parseLine('[download] Destination: /t/media.f399.mp4 ')!
              as YtDlpDestinationLine;
      expect(l.path, '/t/media.f399.mp4');
    });

    test('ignores other lines', () {
      expect(YtDlpOutput.parseLine('WARNING: something'), isNull);
      expect(YtDlpOutput.parseLine('FTUBE|short'), isNull);
      expect(YtDlpOutput.parseLine(''), isNull);
    });
  });

  group('parseInfo', () {
    test('parses a real yt-dlp -J capture', () {
      final info = YtDlpOutput.parseInfo(
        File('test/fixtures/yt_dlp/info_video.json').readAsStringSync(),
        url: 'https://youtu.be/aqz-KE-bpKQ',
      );
      expect(info.url, 'https://youtu.be/aqz-KE-bpKQ');
      expect(info.title, startsWith('Big Buck Bunny'));
      expect(info.uploader, 'Blender');
      expect(info.duration, const Duration(seconds: 635));
      expect(info.thumbnailUrl, contains('ytimg.com'));
      expect(
        info.formats.map((f) => f.id),
        isNot(contains('sb0')),
        reason: 'storyboards are skipped',
      );

      final video = info.formats.firstWhere((f) => f.id == '399');
      expect(video.kind, FormatKind.videoOnly);
      expect(video.container, 'mp4');
      expect(video.height, 1080);
      expect(video.fps, 60);
      expect(video.resolution, '1920x1080');
      expect(video.bitrateKbps, 1568);
      expect(video.sizeBytes, 124386876);

      final audio = info.formats.firstWhere((f) => f.id == '140');
      expect(audio.kind, FormatKind.audioOnly);
      expect(audio.resolution, isNull);
      expect(audio.height, isNull);
    });

    test('detects combined formats and fills gaps', () {
      final info = YtDlpOutput.parseInfo('''
        {"channel": "C", "duration": 1.5, "formats": [
          {"format_id": "18", "ext": "mp4", "vcodec": "avc1", "acodec": "mp4a",
           "height": 360, "filesize_approx": 99},
          {"format_id": "direct"},
          {"ext": "mp4"}
        ]}''', url: 'https://x.test/v');
      expect(info.title, 'https://x.test/v');
      expect(info.uploader, 'C');
      expect(info.duration, const Duration(milliseconds: 1500));
      expect(info.formats.map((f) => (f.id, f.kind)), [
        ('18', FormatKind.videoAudio),
        ('direct', FormatKind.videoAudio),
      ]);
      expect(info.formats.first.sizeBytes, 99);
      expect(info.formats.last.container, '?');
    });

    test('rejects bad JSON and playlists', () {
      expect(
        () => YtDlpOutput.parseInfo('nope', url: 'u'),
        throwsA(isA<Unsupported>()),
      );
      expect(
        () => YtDlpOutput.parseInfo('[]', url: 'u'),
        throwsA(isA<Unsupported>()),
      );
      expect(
        () => YtDlpOutput.parseInfo('{"_type": "playlist"}', url: 'u'),
        throwsA(isA<Unsupported>()),
      );
    });
  });

  group('mapError', () {
    test('maps known yt-dlp errors', () {
      expect(
        YtDlpOutput.mapError(1, 'ERROR: Unsupported URL: https://x.test'),
        isA<Unsupported>(),
      );
      expect(
        YtDlpOutput.mapError(1, "ERROR: 'abc' is not a valid URL"),
        isA<InvalidUrl>(),
      );
      expect(
        YtDlpOutput.mapError(
          1,
          'WARNING: retrying\nERROR: [youtube] x: Unable to download webpage: '
          '<urlopen error [Errno 8] nodename nor servname provided> '
          '(caused by TransportError(...))',
        ),
        isA<Network>(),
      );
    });

    test('falls back to ProcessFailed with the stderr tail', () {
      final e = YtDlpOutput.mapError(2, 'line 1\nERROR: HTTP Error 403');
      expect(e, isA<ProcessFailed>());
      e as ProcessFailed;
      expect(e.exitCode, 2);
      expect(e.stderrTail, 'line 1\nERROR: HTTP Error 403');
    });

    test('uses ERROR lines only, so warnings do not mislead', () {
      expect(
        YtDlpOutput.mapError(
          1,
          'WARNING: Connection reset, retrying\nERROR: Video unavailable',
        ),
        isA<ProcessFailed>(),
      );
    });
  });
}
