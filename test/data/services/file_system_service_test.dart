import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/data/services/android/android_file_launcher.dart';
import 'package:ftube/data/services/binary_service.dart';
import 'package:ftube/data/services/file_system_service.dart';
import 'package:ftube/data/services/process_runner.dart';
import 'package:ftube/domain/exceptions/ftube_exception.dart';
import 'package:ftube/domain/models/library_item.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;

import 'desktop/fakes.dart';

class MockLauncher extends Mock implements AndroidFileLauncher {}

void main() {
  late Directory dir;
  late MockProcessRunner runner;

  FileSystemService service([DesktopOs? os = DesktopOs.linux]) =>
      FileSystemService(runner: runner, os: os);

  File write(String name, {int size = 3, DateTime? modified}) {
    final f = File(p.join(dir.path, name))
      ..writeAsBytesSync(List.filled(size, 0));
    if (modified != null) f.setLastModifiedSync(modified);
    return f;
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('ftube_fs_');
    runner = MockProcessRunner();
    when(() => runner.run(any(), any()))
        .thenAnswer((_) async => const ProcessOutput(0, '', ''));
  });

  tearDown(() => dir.deleteSync(recursive: true));

  group('list', () {
    test('returns visible files, newest first', () async {
      write('old.mp4', size: 10, modified: DateTime(2026));
      write('new.mp3', modified: DateTime(2026, 6));
      write('notes.txt', modified: DateTime(2026, 3));
      for (final hidden in ['.DS_Store', 'a.mp4.part', 'b.ytdl', 'c.TMP']) {
        write(hidden);
      }
      Directory(p.join(dir.path, 'sub')).createSync();

      final items = await service().list(dir);
      expect(items.map((i) => i.name), ['new.mp3', 'notes.txt', 'old.mp4']);
      final old = items.last;
      expect(old.path, p.join(dir.path, 'old.mp4'));
      expect(old.sizeBytes, 10);
      expect(old.modified, DateTime(2026));
      expect(old.kind, LibraryKind.video);
      expect(items.first.kind, LibraryKind.audio);
      expect(items[1].kind, LibraryKind.other);
    });

    test('a missing folder is empty', () async {
      expect(await service().list(Directory(p.join(dir.path, 'x'))), isEmpty);
    });

    test('stat reads one file and throws FileError when missing', () async {
      final f = write('a.mp4', size: 5);
      expect((await service().stat(f.path)).sizeBytes, 5);
      await expectLater(
        service().stat(p.join(dir.path, 'gone.mp4')),
        throwsA(isA<FileError>()),
      );
    });
  });

  group('delete', () {
    test('removes the file; a missing file is fine', () async {
      final f = write('a.mp4');
      await service().delete(f.path);
      expect(f.existsSync(), isFalse);
      await service().delete(f.path);
    });

    test('a read-only folder throws FileError', () async {
      final f = write('a.mp4');
      Process.runSync('chmod', ['555', dir.path]);
      addTearDown(() => Process.runSync('chmod', ['755', dir.path]));
      await expectLater(service().delete(f.path), throwsA(isA<FileError>()));
    }, skip: Platform.isWindows ? 'no chmod' : null);
  });

  group('rename', () {
    test('moves the file', () async {
      final f = write('a.mp4');
      final to = p.join(dir.path, 'b.mp4');
      await service().rename(f.path, to);
      expect(File(to).existsSync(), isTrue);
      expect(f.existsSync(), isFalse);
    });

    test('never overwrites', () async {
      final a = write('a.mp4');
      final b = write('b.mp4', size: 7);
      await expectLater(
        service().rename(a.path, b.path),
        throwsA(isA<FileExists>().having((e) => e.name, 'name', 'b.mp4')),
      );
      expect(b.lengthSync(), 7);
    });

    test('a missing source throws FileError', () async {
      await expectLater(
        service().rename(
          p.join(dir.path, 'gone.mp4'),
          p.join(dir.path, 'b.mp4'),
        ),
        throwsA(isA<FileError>()),
      );
    });
  });

  group('open and reveal', () {
    const file = '/d/Ftube/a.mp4';

    Future<List<Object?>> call(
      Future<void> Function(FileSystemService, String) action,
      DesktopOs os,
    ) async {
      await action(service(os), file);
      return verify(() => runner.run(captureAny(), captureAny())).captured;
    }

    test('use the system tools per OS', () async {
      Future<void> open(FileSystemService s, String f) => s.open(f);
      Future<void> reveal(FileSystemService s, String f) => s.reveal(f);
      expect(await call(open, DesktopOs.macos), [
        'open',
        [file],
      ]);
      expect(await call(reveal, DesktopOs.macos), [
        'open',
        ['-R', file],
      ]);
      expect(await call(open, DesktopOs.windows), [
        'explorer.exe',
        [file],
      ]);
      expect(await call(reveal, DesktopOs.windows), [
        'explorer.exe',
        ['/select,$file'],
      ]);
      expect(await call(open, DesktopOs.linux), [
        'xdg-open',
        [file],
      ]);
      expect(await call(reveal, DesktopOs.linux), [
        'xdg-open',
        ['/d/Ftube'],
      ]);
    });

    test('a non-zero exit is a FileError, except on Windows', () async {
      when(() => runner.run(any(), any()))
          .thenAnswer((_) async => const ProcessOutput(1, '', ''));
      await expectLater(service().open(file), throwsA(isA<FileError>()));
      await service(DesktopOs.windows).open(file);
    });

    test('a missing tool is Unsupported', () async {
      when(() => runner.run(any(), any()))
          .thenThrow(const ProcessException('xdg-open', []));
      await expectLater(service().reveal(file), throwsA(isA<Unsupported>()));
    });

    test('reveal is desktop only, share is Android only', () {
      final android = service(null);
      expect(android.canReveal, isFalse);
      expect(service().canReveal, isTrue);
      expect(service().canShare, isFalse);
      expect(() => android.reveal(file), throwsA(isA<Unsupported>()));
      expect(() => service().share(file), throwsA(isA<Unsupported>()));
    });

    test('Android without a launcher cannot open or share', () {
      final android = service(null);
      expect(android.canOpen, isFalse);
      expect(android.canShare, isFalse);
      expect(() => android.open(file), throwsA(isA<Unsupported>()));
      expect(() => android.share(file), throwsA(isA<Unsupported>()));
    });

    test('Android opens and shares through the launcher', () async {
      final launcher = MockLauncher();
      when(() => launcher.open(any())).thenAnswer((_) async {});
      when(() => launcher.share(any())).thenAnswer((_) async {});
      final android = FileSystemService(runner: runner, android: launcher);
      expect(android.canOpen, isTrue);
      expect(android.canShare, isTrue);
      await android.open(file);
      await android.share(file);
      verify(() => launcher.open(file)).called(1);
      verify(() => launcher.share(file)).called(1);
      verifyNever(() => runner.run(any(), any()));
    });
  });
}
