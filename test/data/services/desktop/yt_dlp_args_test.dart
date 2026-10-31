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

  test('common flags match ftube.sh and add the runtimes', () {
    expect(YtDlpArgs.common(ffmpegDir: '/bin', denoPath: '/bin/deno'), [
      '--ignore-config',
      '--no-playlist',
      '--restrict-filenames',
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

    test('video preset: selector, paths, templates, url last', () {
      final args = YtDlpArgs.download(
        req(QualityPreset.p720),
        ffmpegDir: '/bin',
        tempDir: '/tmp/j1',
      );
      String after(String flag) => args[args.indexOf(flag) + 1];
      expect(after('-f'), 'bv*[height<=720]+ba/b[height<=720]');
      expect(after('-o'), '%(title)s.%(ext)s');
      expect(args, containsAllInOrder(['-P', '/out', '-P', 'temp:/tmp/j1']));
      expect(args, containsAll(['--newline', '--progress', '--no-simulate']));
      expect(args, isNot(contains('-x')));
      expect(after('--print'), 'after_move:FTUBE_FILE|%(filepath)s');
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
}
