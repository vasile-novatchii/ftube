import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/data/services/desktop/yt_dlp_args.dart';
import 'package:ftube/domain/models/models.dart';

void main() {
  group('formatSelector', () {
    test('maps every preset', () {
      expect(YtDlpArgs.formatSelector(QualityPreset.best), 'bv*+ba/b');
      expect(
        YtDlpArgs.formatSelector(QualityPreset.p1080),
        'bv*[height<=1080]+ba/b[height<=1080]',
      );
      expect(
        YtDlpArgs.formatSelector(QualityPreset.p720),
        'bv*[height<=720]+ba/b[height<=720]',
      );
      expect(
        YtDlpArgs.formatSelector(QualityPreset.p480),
        'bv*[height<=480]+ba/b[height<=480]',
      );
      expect(YtDlpArgs.formatSelector(QualityPreset.audioMp3), 'ba/b');
      expect(YtDlpArgs.formatSelector(QualityPreset.audioOgg), 'ba/b');
    });

    test('custom passes the format id through', () {
      expect(
        YtDlpArgs.formatSelector(QualityPreset.custom, formatId: '399+ba'),
        '399+ba',
      );
      expect(
        () => YtDlpArgs.formatSelector(QualityPreset.custom),
        throwsArgumentError,
      );
    });
  });

  test('common flags add the tools and keep titles as they are', () {
    expect(YtDlpArgs.common(ffmpegDir: '/bin', denoPath: '/bin/deno'), [
      '--ignore-config',
      '--no-playlist',
      '--ffmpeg-location',
      '/bin',
      '--js-runtimes',
      'deno:/bin/deno',
    ]);
    expect(
      YtDlpArgs.common(ffmpegDir: '/bin'),
      isNot(contains('--js-runtimes')),
    );
  });

  test('info ends with -J -- url', () {
    final args = YtDlpArgs.info('https://x.test/v', ffmpegDir: '/bin');
    expect(args.sublist(args.length - 3), ['-J', '--', 'https://x.test/v']);
  });

  group('download', () {
    DownloadRequest req(QualityPreset preset) => DownloadRequest(
      jobId: 'j1',
      url: 'https://x.test/v',
      preset: preset,
      outDir: Directory('/out'),
    );

    test('video preset: selector, temp output, templates, url last', () {
      final args = YtDlpArgs.download(
        req(QualityPreset.p720),
        ffmpegDir: '/bin',
        tempDir: '/tmp/j1',
      );
      String after(String flag) => args[args.indexOf(flag) + 1];
      expect(after('-f'), 'bv*[height<=720]+ba/b[height<=720]');
      expect(after('-o'), 'media.%(ext)s');
      expect(after('-P'), '/tmp/j1');
      expect(args.where((a) => a == '-P'), hasLength(1));
      expect(args, isNot(contains('/out')));
      expect(args, containsAll(['--newline', '--progress', '--no-simulate']));
      expect(args, isNot(contains('-x')));
      expect(
        args,
        containsAllInOrder([
          '--print',
          'video:FTUBE_TITLE|%(title)s',
          '--print',
          'after_move:FTUBE_FILE|%(filepath)s',
        ]),
      );
      expect(args.where((a) => a.startsWith('download:FTUBE|')), hasLength(1));
      expect(
        args.where((a) => a.startsWith('postprocess:FTUBE_PP|')),
        hasLength(1),
      );
      expect(args.sublist(args.length - 2), ['--', 'https://x.test/v']);
    });

    test('audio presets extract mp3 or vorbis at best quality', () {
      for (final (preset, format) in [
        (QualityPreset.audioMp3, 'mp3'),
        (QualityPreset.audioOgg, 'vorbis'),
      ]) {
        final args = YtDlpArgs.download(
          req(preset),
          ffmpegDir: '/bin',
          tempDir: '/t',
        );
        expect(
          args,
          containsAllInOrder([
            '-x',
            '--audio-format',
            format,
            '--audio-quality',
            '0',
          ]),
        );
      }
    });
  });

  group('android', () {
    test('info ends with -J -- url and adds no tool paths', () {
      expect(YtDlpArgs.androidInfo('https://x.test/v'), [
        '--ignore-config',
        '--no-playlist',
        '-J',
        '--',
        'https://x.test/v',
      ]);
    });

    test('download: temp output, title print, no -x or tool flags', () {
      for (final preset in QualityPreset.values) {
        final args = YtDlpArgs.androidDownload(
          DownloadRequest(
            jobId: 'j1',
            url: 'https://x.test/v',
            preset: preset,
            formatId: preset == QualityPreset.custom ? '137+ba' : null,
            outDir: Directory('/out'),
          ),
          tempDir: '/tmp/j1',
        );
        String after(String flag) => args[args.indexOf(flag) + 1];
        expect(
          after('-f'),
          YtDlpArgs.formatSelector(
            preset,
            formatId: preset == QualityPreset.custom ? '137+ba' : null,
          ),
        );
        expect(after('-o'), 'media.%(ext)s');
        expect(after('-P'), '/tmp/j1');
        expect(after('--print'), 'video:FTUBE_TITLE|%(title)s');
        expect(after('--progress-template'), startsWith('download:FTUBE|'));
        expect(
          args,
          isNot(
            anyOf(
              contains('-x'),
              contains('--ffmpeg-location'),
              contains('--js-runtimes'),
            ),
          ),
        );
        expect(args.sublist(args.length - 2), ['--', 'https://x.test/v']);
      }
    });
  });
}
