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
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('trash', () {
    final calls = <List<String>>[];
    Map<String, Object?> Function(List<String>) reply = (paths) => {
      'moved': paths,
      'error': null,
    };

    setUp(() {
      calls.clear();
      reply = (paths) => {'moved': paths, 'error': null};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(FileSystemService.trashChannel, (call) {
            final paths = ((call.arguments as Map)['paths'] as List)
                .cast<String>();
            calls.add(paths);
            return Future.value(reply(paths));
          });
    });

    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(FileSystemService.trashChannel, null),
    );

    test('sends existing files to the channel in one call', () async {
      final a = write('a.mp4');
      final missing = p.join(dir.path, 'gone.mp4');
      final moved = await service(DesktopOs.macos).trash([a.path, missing]);
      expect(calls, [
        [a.path],
      ]);
      expect(moved, [a.path]);
    });

    test('only missing files is a no-op', () async {
      expect(await service(null).trash([p.join(dir.path, 'x')]), isEmpty);
      expect(calls, isEmpty);
    });

    test('a cancelled Android dialog moves nothing', () async {
      reply = (_) => {'moved': <String>[], 'error': null};
      expect(await service(null).trash([write('a.mp4').path]), isEmpty);
    });

    test('a native error is a FileError', () async {
      reply = (_) => {'moved': <String>[], 'error': 'locked'};
      await expectLater(
        service(DesktopOs.windows).trash([write('a.mp4').path]),
        throwsA(isA<FileError>()),
      );
    });

    test('Linux uses gio trash per file and reports failures', () async {
      final a = write('a.mp4');
      final b = write('b.mp4');
      when(() => runner.run('gio', ['trash', '--', b.path]))
          .thenAnswer((_) async => const ProcessOutput(1, '', 'no'));
      await expectLater(
        service().trash([a.path, b.path]),
        throwsA(isA<FileError>()),
      );
      verify(() => runner.run('gio', ['trash', '--', a.path])).called(1);
      expect(calls, isEmpty);
    });

    test('Linux without gio is Unsupported', () async {
      when(() => runner.run(any(), any()))
          .thenThrow(const ProcessException('gio', []));
      await expectLater(
        service().trash([write('a.mp4').path]),
        throwsA(isA<Unsupported>()),
      );
    });
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

  group('openUrl (spec-v0.6 D-94)', () {
    final url = Uri.parse('https://github.com/o/r/releases/tag/v1.0.0');
    const link = 'https://github.com/o/r/releases/tag/v1.0.0';

    test('runs the system opener without a shell', () async {
      await service(DesktopOs.macos).openUrl(url);
      await service(DesktopOs.windows).openUrl(url);
      await service().openUrl(url);
      verify(() => runner.run('open', [link])).called(1);
      verify(
        () => runner.run('rundll32', ['url.dll,FileProtocolHandler', link]),
      ).called(1);
      verify(() => runner.run('xdg-open', [link])).called(1);
    });

    test('Windows ignores the exit code, others report it', () async {
      when(() => runner.run(any(), any()))
          .thenAnswer((_) async => const ProcessOutput(1, '', ''));
      await service(DesktopOs.windows).openUrl(url);
      await expectLater(service().openUrl(url), throwsA(isA<FileError>()));
    });

    test('Android opens through the launcher', () async {
      final launcher = MockLauncher();
      when(() => launcher.openUrl(any())).thenAnswer((_) async {});
      await FileSystemService(runner: runner, android: launcher).openUrl(url);
      verify(() => launcher.openUrl(link)).called(1);
    });

    test('only https links are opened', () async {
      for (final bad in ['http://x.com', 'file:///etc/passwd', 'x:y']) {
        await expectLater(
          service().openUrl(Uri.parse(bad)),
          throwsA(isA<Unsupported>()),
        );
      }
      verifyNever(() => runner.run(any(), any()));
    });
  });

  group('emptyDir', () {
    test('deletes the contents and keeps the folder', () async {
      final dir = Directory.systemTemp.createTempSync('ftube_empty_');
      addTearDown(() => dir.deleteSync(recursive: true));
      File(p.join(dir.path, 'a.part')).writeAsStringSync('x');
      Directory(p.join(dir.path, 'job-1')).createSync();
      File(p.join(dir.path, 'job-1', 'b.tmp')).writeAsStringSync('y');
      await FileSystemService(runner: MockProcessRunner()).emptyDir(dir);
      expect(dir.existsSync(), isTrue);
      expect(dir.listSync(), isEmpty);
    });

    test('a missing folder is a no-op', () async {
      await FileSystemService(runner: MockProcessRunner())
          .emptyDir(Directory('/no/such/ftube/dir'));
    });
  });
}
