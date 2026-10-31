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
  late Directory bundled;
  late Directory support;
  late MockProcessRunner runner;
  late BinaryService service;

  File touch(Directory dir, String name) =>
      File(p.join(dir.path, name))..createSync(recursive: true);

  setUp(() {
    root = Directory.systemTemp.createTempSync('ftube_bin_test');
    bundled = Directory(p.join(root.path, 'bundle'))..createSync();
    support = Directory(p.join(root.path, 'support'))..createSync();
    runner = MockProcessRunner();
    service = BinaryService(
      os: DesktopOs.macos,
      bundledDir: bundled,
      supportDir: support,
      runner: runner,
    );
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

  group('bundledDirFor', () {
    test('uses the executable folder, and bundle/lib on Linux', () {
      expect(
        BinaryService.bundledDirFor(
          DesktopOs.macos,
          '/Apps/Ftube.app/Contents/MacOS/ftube',
        ).path,
        '/Apps/Ftube.app/Contents/MacOS',
      );
      expect(
        BinaryService.bundledDirFor(DesktopOs.linux, '/opt/ftube/ftube').path,
        p.join('/opt/ftube', 'lib'),
      );
    });

    test('FTUBE_BIN_DIR overrides it', () {
      expect(
        BinaryService.bundledDirFor(
          DesktopOs.linux,
          '/opt/ftube/ftube',
          environment: {BinaryService.devOverrideEnv: '/dev/bin'},
        ).path,
        '/dev/bin',
      );
    });
  });

  group('locate', () {
    test('finds a bundled binary', () async {
      final ffmpeg = touch(bundled, 'ffmpeg');
      expect((await service.locate(Binary.ffmpeg)).path, ffmpeg.path);
    });

    test('throws BinaryMissing with the binary label', () async {
      await expectLater(
        service.locate(Binary.deno),
        throwsA(isA<BinaryMissing>().having((e) => e.binary, 'binary', 'deno')),
      );
    });

    test('prefers the updated yt-dlp copy', () async {
      touch(bundled, 'yt-dlp_macos');
      final copy = touch(support, p.join('bin', 'yt-dlp_macos'));
      expect((await service.locate(Binary.ytDlp)).path, copy.path);
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
      final ffmpeg = touch(bundled, 'ffmpeg');
      when(() => runner.run(ffmpeg.path, ['-version'])).thenAnswer(
        (_) async => const ProcessOutput(0, 'ffmpeg version 9.0.2 x', ''),
      );
      expect(await service.version(Binary.ffmpeg), '9.0.2');
    });

    test('is null when missing, failing or not runnable', () async {
      expect(await service.version(Binary.ffprobe), isNull);
      verifyNever(() => runner.run(any(), any()));

      final yt = touch(bundled, 'yt-dlp_macos');
      when(() => runner.run(yt.path, ['--version']))
          .thenAnswer((_) async => const ProcessOutput(1, '', 'boom'));
      expect(await service.version(Binary.ytDlp), isNull);

      when(() => runner.run(yt.path, ['--version']))
          .thenThrow(const ProcessException('yt', []));
      expect(await service.version(Binary.ytDlp), isNull);
    });
  });

  group('updateYtDlp', () {
    late File copy;

    setUp(() {
      copy = File(p.join(support.path, 'bin', 'yt-dlp_macos'));
      when(() => runner.run('chmod', any()))
          .thenAnswer((_) async => const ProcessOutput(0, '', ''));
    });

    test('copies the bundled binary once, then updates the copy', () async {
      touch(bundled, 'yt-dlp_macos').writeAsStringSync('bundled');
      when(() => runner.run(copy.path, ['-U']))
          .thenAnswer((_) async => const ProcessOutput(0, 'Updated', ''));
      when(() => runner.run(copy.path, ['--version']))
          .thenAnswer((_) async => const ProcessOutput(0, '2026.11.01\n', ''));

      expect(await service.updateYtDlp(), '2026.11.01');
      expect(copy.readAsStringSync(), 'bundled');
      verify(() => runner.run('chmod', ['755', copy.path])).called(1);

      copy.writeAsStringSync('updated');
      await service.updateYtDlp();
      expect(copy.readAsStringSync(), 'updated', reason: 'not copied again');
      verifyNever(() => runner.run('chmod', any()));
    });

    test('throws ProcessFailed when -U fails', () async {
      touch(bundled, 'yt-dlp_macos');
      when(() => runner.run(copy.path, ['-U']))
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

    test('throws BinaryMissing without a bundled yt-dlp', () async {
      await expectLater(service.updateYtDlp(), throwsA(isA<BinaryMissing>()));
    });
  });
}
