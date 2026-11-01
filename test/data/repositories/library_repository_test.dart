import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/data/repositories/library_repository.dart';
import 'package:ftube/data/services/android/storage_permission_service.dart';
import 'package:ftube/data/services/binary_service.dart';
import 'package:ftube/data/services/file_system_service.dart';
import 'package:ftube/data/services/process_runner.dart';
import 'package:ftube/domain/exceptions/ftube_exception.dart';
import 'package:ftube/domain/models/models.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;

import '../services/desktop/fakes.dart';
import 'fake_media_service.dart';

class MockStorage extends Mock implements StoragePermissionService {}

void main() {
  late Directory dir;
  late FakeMediaService media;
  late MockProcessRunner runner;
  late MockStorage storage;
  late FileSystemService files;

  LibraryRepository repo({bool android = false}) => LibraryRepository(
    files: files,
    media: media,
    storage: android ? storage : null,
  );

  File write(String name) =>
      File(p.join(dir.path, name))..writeAsStringSync(name);

  Future<LibraryItem> item(String name) => files.stat(write(name).path);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('ftube_lib_');
    media = FakeMediaService();
    runner = MockProcessRunner();
    when(() => runner.run(any(), any()))
        .thenAnswer((_) async => const ProcessOutput(0, '', ''));
    files = FileSystemService(runner: runner, os: DesktopOs.macos);
    storage = MockStorage();
    when(storage.ensureGranted).thenAnswer((_) async {});
    when(() => storage.scanFile(any())).thenAnswer((_) async {});
  });

  tearDown(() => dir.deleteSync(recursive: true));

  group('list', () {
    test('lists the folder', () async {
      write('a.mp4');
      expect((await repo().list(dir)).single.name, 'a.mp4');
    });

    test('needs storage access on Android', () async {
      when(storage.ensureGranted).thenThrow(const StoragePermission());
      await expectLater(
        repo(android: true).list(dir),
        throwsA(isA<StoragePermission>()),
      );
    });
  });

  group('delete', () {
    test('deletes every item and announces it on Android', () async {
      final items = [await item('a.mp4'), await item('b.mp3')];
      expect(await repo(android: true).delete(items), 2);
      expect(dir.listSync(), isEmpty);
      verify(() => storage.scanFile(items[0].path)).called(1);
      verify(() => storage.scanFile(items[1].path)).called(1);
    });

    test('tries every item, then throws the first error', () async {
      final a = await item('a.mp4');
      final b = await item('b.mp4');
      Process.runSync('chmod', ['555', dir.path]);
      addTearDown(() => Process.runSync('chmod', ['755', dir.path]));
      await expectLater(repo().delete([a, b]), throwsA(isA<FileError>()));
    }, skip: Platform.isWindows ? 'no chmod' : null);

    test('an empty list deletes nothing', () async {
      expect(await repo().delete(const []), 0);
    });
  });

  group('rename', () {
    test('keeps the extension', () async {
      final a = await item('a.mp4');
      final renamed = await repo(android: true).rename(a, '  My clip ');
      expect(renamed.name, 'My clip.mp4');
      expect(renamed.path, p.join(dir.path, 'My clip.mp4'));
      expect(File(renamed.path).readAsStringSync(), 'a.mp4');
      verify(() => storage.scanFile(a.path)).called(1);
      verify(() => storage.scanFile(renamed.path)).called(1);
    });

    test('does not double a typed extension', () async {
      final a = await item('a.mp4');
      expect((await repo().rename(a, 'b.MP4')).name, 'b.mp4');
    });

    test('a file without extension stays without one', () async {
      final a = await item('README');
      expect((await repo().rename(a, 'notes')).name, 'notes');
    });

    test('the same name is a no-op', () async {
      final a = await item('a.mp4');
      expect(await repo().rename(a, 'a'), same(a));
    });

    test('rejects bad names', () async {
      final a = await item('a.mp4');
      for (final name in [
        '',
        '  ',
        '.mp4',
        '.hidden',
        'dots.',
        'a/b',
        r'a\b',
        'a:b',
        'what?',
        'tab\tname',
        'x' * (LibraryRepository.maxNameLength + 1),
      ]) {
        await expectLater(
          repo().rename(a, name),
          throwsA(isA<InvalidFileName>()),
          reason: name,
        );
      }
    });

    test('never overwrites another file', () async {
      final a = await item('a.mp4');
      write('b.mp4');
      await expectLater(repo().rename(a, 'b'), throwsA(isA<FileExists>()));
    });
  });

  group('convert', () {
    test('writes next to the original with a free name', () async {
      final a = await item('song.mp4');
      write('song.mp3');
      final progress = await repo()
          .convert(a, AudioTarget.mp3, jobId: 'c1')
          .toList();
      expect(progress.single.outputPath, p.join(dir.path, 'song_2.mp3'));
      expect(media.converts.single, (
        a.path,
        AudioTarget.mp3,
        p.join(dir.path, 'song_2.mp3'),
        'c1',
      ));
    });

    test('rejects other files and the same format', () async {
      for (final (name, target) in [
        ('notes.txt', AudioTarget.mp3),
        ('song.mp3', AudioTarget.mp3),
        ('song.OGG', AudioTarget.ogg),
      ]) {
        await expectLater(
          repo().convert(await item(name), target, jobId: 'c'),
          emitsError(isA<Unsupported>()),
          reason: name,
        );
      }
      expect(media.converts, isEmpty);
    });

    test('cancelConversion cancels the job', () async {
      await repo().cancelConversion('c1');
      expect(media.cancelled, ['c1']);
    });
  });

  test('open and reveal go to the file system service', () async {
    final a = await item('a.mp4');
    final r = repo();
    expect(r.canReveal, isTrue);
    expect(r.canOpen, isTrue);
    expect(r.canShare, isFalse);
    await r.open(a);
    await r.reveal(a);
    verify(() => runner.run('open', [a.path])).called(1);
    verify(() => runner.run('open', ['-R', a.path])).called(1);
  });

  test('share goes to the file system service', () async {
    final a = await item('a.mp4');
    await expectLater(repo().share(a), throwsA(isA<Unsupported>()));
  });
}
