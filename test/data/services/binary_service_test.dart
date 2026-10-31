import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/data/services/binary_service.dart';
import 'package:ftube/data/services/process_runner.dart';
import 'package:ftube/domain/exceptions/ftube_exception.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;

import 'desktop/fakes.dart';

void main() {
  late Directory root;
  late Directory bin;
  late MockProcessRunner runner;
  late BinaryService service;

  File touch(Directory dir, String name) =>
      File(p.join(dir.path, name))..createSync(recursive: true);

  setUp(() {
    root = Directory.systemTemp.createTempSync('ftube_bin_test');
    bin = Directory(p.join(root.path, 'support', 'bin'))
      ..createSync(recursive: true);
    runner = MockProcessRunner();
    service = BinaryService(os: DesktopOs.macos, binDir: bin, runner: runner);
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('file names per OS', () {
    expect(Binary.ytDlp.fileName(DesktopOs.macos), 'yt-dlp_macos');
    expect(Binary.ytDlp.fileName(DesktopOs.linux), 'yt-dlp_linux');
    expect(Binary.ytDlp.fileName(DesktopOs.windows), 'yt-dlp.exe');
    expect(Binary.ffmpeg.fileName(DesktopOs.windows), 'ffmpeg.exe');
    expect(Binary.ffprobe.fileName(DesktopOs.linux), 'ffprobe');
    expect(Binary.deno.fileName(DesktopOs.macos), 'deno');
  });

  group('binDirFor', () {
    test('is support/bin', () {
      expect(
        BinaryService.binDirFor(Directory('/support')).path,
        p.join('/support', 'bin'),
      );
    });

    test('FTUBE_BIN_DIR overrides it', () {
      expect(
        BinaryService.binDirFor(
          Directory('/support'),
          environment: {BinaryService.devOverrideEnv: '/dev/bin'},
        ).path,
        '/dev/bin',
      );
    });
  });

  group('locate', () {
    test('finds an installed binary', () async {
      final ffmpeg = touch(bin, 'ffmpeg');
      expect((await service.locate(Binary.ffmpeg)).path, ffmpeg.path);
    });

    test('throws BinaryMissing with the binary label', () async {
      await expectLater(
        service.locate(Binary.deno),
        throwsA(isA<BinaryMissing>().having((e) => e.binary, 'binary', 'deno')),
      );
    });
  });

  group('version', () {
    test('parses each binary', () {
      expect(
        BinaryService.parseVersion(
          Binary.ffmpeg,
          'ffmpeg version 9.0.2 Copyright (c) 2000-2026\nbuilt with clang',
        ),
        '9.0.2',
      );
      expect(
        BinaryService.parseVersion(
          Binary.ffprobe,
          'ffprobe version n9.0.2-17-g2a571b6068 Copyright',
        ),
        'n9.0.2-17-g2a571b6068',
      );
      expect(
        BinaryService.parseVersion(
          Binary.deno,
          'deno 2.9.8 (stable, release, aarch64-apple-darwin)\nv8 14',
        ),
        '2.9.8',
      );
      expect(
        BinaryService.parseVersion(Binary.ytDlp, '2026.10.26\n'),
        '2026.10.26',
      );
      expect(BinaryService.parseVersion(Binary.ytDlp, ''), isNull);
    });

    test('runs the right flag', () async {
      final ffmpeg = touch(bin, 'ffmpeg');
      when(() => runner.run(ffmpeg.path, ['-version'])).thenAnswer(
        (_) async => const ProcessOutput(0, 'ffmpeg version 9.0.2 x', ''),
      );
      expect(await service.version(Binary.ffmpeg), '9.0.2');
    });

    test('is null when missing, failing or not runnable', () async {
      expect(await service.version(Binary.ffprobe), isNull);
      verifyNever(() => runner.run(any(), any()));

      final yt = touch(bin, 'yt-dlp_macos');
      when(() => runner.run(yt.path, ['--version']))
          .thenAnswer((_) async => const ProcessOutput(1, '', 'boom'));
      expect(await service.version(Binary.ytDlp), isNull);

      when(() => runner.run(yt.path, ['--version']))
          .thenThrow(const ProcessException('yt', []));
      expect(await service.version(Binary.ytDlp), isNull);
    });
  });

  group('updateYtDlp', () {
    test('runs -U on the installed yt-dlp and reads the new version', () async {
      final yt = touch(bin, 'yt-dlp_macos');
      when(() => runner.run(yt.path, ['-U']))
          .thenAnswer((_) async => const ProcessOutput(0, 'Updated', ''));
      when(() => runner.run(yt.path, ['--version']))
          .thenAnswer((_) async => const ProcessOutput(0, '2026.11.01\n', ''));
      expect(await service.updateYtDlp(), '2026.11.01');
    });

    test('throws ProcessFailed when -U fails', () async {
      final yt = touch(bin, 'yt-dlp_macos');
      when(() => runner.run(yt.path, ['-U']))
          .thenAnswer((_) async => const ProcessOutput(1, '', 'ERROR: no net'));
      await expectLater(
        service.updateYtDlp(),
        throwsA(
          isA<ProcessFailed>().having(
            (e) => e.stderrTail,
            'stderrTail',
            'ERROR: no net',
          ),
        ),
      );
    });

    test('throws BinaryMissing when yt-dlp is not installed', () async {
      await expectLater(service.updateYtDlp(), throwsA(isA<BinaryMissing>()));
      verifyNever(() => runner.run(any(), any()));
    });
  });
}
