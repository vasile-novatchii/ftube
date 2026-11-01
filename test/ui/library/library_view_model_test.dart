import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/config/providers.dart';
import 'package:ftube/data/repositories/settings_repository.dart';
import 'package:ftube/data/services/android/storage_permission_service.dart';
import 'package:ftube/domain/exceptions/ftube_exception.dart';
import 'package:ftube/domain/models/models.dart';
import 'package:ftube/ui/home/view_model/home_view_model.dart';
import 'package:ftube/ui/library/view_model/library_view_model.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;

import '../helpers.dart';
import 'library_fixtures.dart';

void main() {
  late TestEnv env;
  late ProviderContainer c;
  late Disk disk;
  late List<LibraryNotice> notices;

  LibraryState state() => c.read(libraryViewModelProvider);
  LibraryViewModel vm() => c.read(libraryViewModelProvider.notifier);
  List<String> names() => state().visible.map((i) => i.name).toList();
  LibraryItem item(String name) =>
      state().items.firstWhere((i) => i.name == name);

  Future<void> start(TestEnv e, [Map<String, Object> prefs = const {}]) async {
    env = e;
    disk = Disk(env.files);
    c = await env.container(prefs);
    addTearDown(c.dispose);
    notices = [];
    c.listen(libraryViewModelProvider.select((s) => s.notice), (_, n) {
      if (n != null) notices.add(n);
    });
    await pumpEventQueue();
  }

  group('desktop', () {
    setUp(() => start(TestEnv.desktop()));

    test('lists the download folder, newest first', () {
      expect(state().loading, isFalse);
      expect(state().error, isNull);
      expect(names(), ['a.mp4', 'b.mp3', 'c.txt']);
      expect(state().canOpen, isTrue);
      expect(state().canReveal, isTrue);
      expect(state().canShare, isFalse);
      verify(() => env.files.list(dirAt(downloads))).called(1);
    });

    test('filters, searches and sorts', () {
      vm().setFilter(LibraryFilter.video);
      expect(names(), ['a.mp4']);
      vm().setFilter(LibraryFilter.audio);
      expect(names(), ['b.mp3']);
      vm()
        ..setFilter(LibraryFilter.all)
        ..search('  B.M ');
      expect(names(), ['b.mp3']);
      vm().search('');
      vm().setSort(LibrarySort.size);
      expect(names(), ['a.mp4', 'c.txt', 'b.mp3']);
      vm().setSort(LibrarySort.name);
      expect(names(), ['a.mp4', 'b.mp3', 'c.txt']);
      vm().search('zzz');
      expect(names(), isEmpty);
      expect(state().isEmpty, isFalse);
    });

    test('selects, selects all and clears', () {
      vm().toggleSelected(item('b.mp3'));
      expect(state().selecting, isTrue);
      expect(vm().selectedItems.map((i) => i.name), ['b.mp3']);
      vm().toggleSelected(item('b.mp3'));
      expect(state().selecting, isFalse);
      vm().selectAll();
      expect(state().selected, hasLength(3));
      vm().clearSelection();
      expect(state().selected, isEmpty);
      vm()
        ..selectAll()
        ..setFilter(LibraryFilter.audio);
      expect(state().selected, isEmpty);
    });

    test('a delete hides the files until undone', () async {
      vm().toggleSelected(item('a.mp4'));
      await vm().deleteSelected();
      expect(names(), ['b.mp3', 'c.txt']);
      expect(state().selected, isEmpty);
      expect(state().notice, isA<LibraryDeleted>());
      expect((state().notice! as LibraryDeleted).count, 1);
      vm().undoDelete();
      expect(names(), ['a.mp4', 'b.mp3', 'c.txt']);
      await vm().delete([item('b.mp3')]);
      vm().undoDelete();
      verifyNever(() => env.files.delete(any()));
    });

    test('a second delete carries out the pending one', () async {
      await vm().delete([item('a.mp4')]);
      await vm().delete([item('b.mp3')]);
      verify(() => env.files.delete(p.join(downloads, 'a.mp4'))).called(1);
      expect(state().items.map((i) => i.name), ['b.mp3', 'c.txt']);
      expect(names(), ['c.txt']);
    });

    test('delete all removes what is shown', () async {
      vm().setFilter(LibraryFilter.audio);
      await vm().deleteAll();
      expect((state().notice! as LibraryDeleted).count, 1);
      vm().setFilter(LibraryFilter.all);
      expect(names(), ['a.mp4', 'c.txt']);
      await vm().delete(const []);
      expect(state().pendingDelete, {p.join(downloads, 'b.mp3')});
    });

    test('a failed delete is reported and the list reloaded', () async {
      when(() => env.files.delete(any())).thenThrow(const FileError('busy'));
      await vm().delete([item('a.mp4')]);
      await vm().delete([item('b.mp3')]);
      expect(notices.map((n) => n.runtimeType), [
        LibraryDeleted,
        LibraryFailed,
        LibraryDeleted,
      ]);
      expect(names(), ['a.mp4', 'c.txt']);
    });

    test('a pending delete is carried out on dispose', () async {
      await vm().delete([item('a.mp4')]);
      c.dispose();
      await pumpEventQueue();
      verify(() => env.files.delete(p.join(downloads, 'a.mp4'))).called(1);
    });

    test('renames and keeps the selection', () async {
      vm().toggleSelected(item('a.mp4'));
      expect(await vm().rename(item('a.mp4'), 'z'), isNull);
      expect(state().items.first.name, 'z.mp4');
      expect(state().selected, {p.join(downloads, 'z.mp4')});
    });

    test('a failed rename returns the error', () async {
      expect(await vm().rename(item('a.mp4'), 'b/c'), isA<InvalidFileName>());
      when(() => env.files.rename(any(), any()))
          .thenThrow(const FileExists('b.txt'));
      expect(await vm().rename(item('c.txt'), 'b'), isA<FileExists>());
      expect(names(), ['a.mp4', 'b.mp3', 'c.txt']);
    });

    test('converts and lists the new file', () async {
      final a = item('a.mp4');
      expect(state().canConvert(a, AudioTarget.mp3), isTrue);
      expect(state().canConvert(item('b.mp3'), AudioTarget.mp3), isFalse);
      expect(state().canConvert(item('c.txt'), AudioTarget.ogg), isFalse);
      env.media.onConvert = (id, dst) {
        disk.add(p.basename(dst.path), 5, DateTime(2027));
        return Stream.fromIterable([
          JobProgress(jobId: id, phase: JobPhase.converting, fraction: 0.5),
          JobProgress(
            jobId: id,
            phase: JobPhase.finished,
            fraction: 1,
            outputPath: dst.path,
          ),
        ]);
      };
      vm().convert(a, AudioTarget.mp3);
      expect(state().converting, {a.path: null});
      expect(state().canConvert(a, AudioTarget.ogg), isFalse);
      await pumpEventQueue();
      expect(state().converting, isEmpty);
      expect((state().notice! as LibraryConverted).name, 'a.mp3');
      expect(names().first, 'a.mp3');
      final (src, target, _, _) = env.media.converts.single;
      expect((src, target), (a.path, AudioTarget.mp3));
    });

    test('shows conversion progress and stops it', () async {
      final run = StreamController<JobProgress>();
      env.media.onConvert = (_, _) => run.stream;
      final a = item('a.mp4');
      vm().convert(a, AudioTarget.ogg);
      vm().convert(a, AudioTarget.ogg);
      expect(env.media.converts, hasLength(1));
      final id = env.media.converts.single.$4;
      run.add(JobProgress(jobId: id, phase: JobPhase.converting, fraction: .4));
      await pumpEventQueue();
      expect(state().converting, {a.path: .4});
      await vm().cancelConversion(a);
      expect(state().converting, isEmpty);
      expect(env.media.cancelled, [id]);
      await vm().cancelConversion(a);
      expect(env.media.cancelled, [id]);
      await run.close();
    });

    test('a failed conversion is reported, a cancelled one is not', () async {
      final runs = <StreamController<JobProgress>>[];
      env.media.onConvert = (_, _) {
        final run = StreamController<JobProgress>();
        runs.add(run);
        return run.stream;
      };
      vm().convert(item('a.mp4'), AudioTarget.mp3);
      runs.last.addError(const ProcessFailed(1, ''));
      await pumpEventQueue();
      expect(state().converting, isEmpty);
      expect((state().notice! as LibraryFailed).error, isA<ProcessFailed>());

      vm().convert(item('a.mp4'), AudioTarget.mp3);
      final notice = state().notice;
      runs.last.addError(const Cancelled());
      await pumpEventQueue();
      expect(state().converting, isEmpty);
      expect(state().notice, same(notice));

      vm().convert(item('a.mp4'), AudioTarget.mp3);
      await runs.last.close();
      await pumpEventQueue();
      expect((state().notice! as LibraryFailed).error, isA<Unexpected>());
    });

    test('running conversions are cancelled on dispose', () async {
      final run = StreamController<JobProgress>();
      addTearDown(run.close);
      env.media.onConvert = (_, _) => run.stream;
      vm().convert(item('a.mp4'), AudioTarget.mp3);
      final id = env.media.converts.single.$4;
      c.dispose();
      await pumpEventQueue();
      expect(env.media.cancelled, contains(id));
    });

    test('open, reveal and share report failures', () async {
      when(() => env.files.open(any())).thenAnswer((_) async {});
      when(() => env.files.reveal(any())).thenThrow(const FileError());
      await vm().open(item('a.mp4'));
      expect(state().notice, isNull);
      await vm().reveal(item('a.mp4'));
      expect((state().notice! as LibraryFailed).error, isA<FileError>());
      await vm().share(item('a.mp4'));
      verifyNever(() => env.files.share(any()));
      verify(() => env.files.open(p.join(downloads, 'a.mp4'))).called(1);
    });

    test('reloads when a download completes', () async {
      clearInteractions(env.files);
      final repo = c.read(downloadRepositoryProvider);
      final job = repo.enqueue(
        url: 'https://youtu.be/x',
        title: 'x',
        preset: QualityPreset.best,
        outDir: Directory(downloads),
      );
      env.media.progress(job.id, .5);
      await pumpEventQueue();
      verifyNever(() => env.files.list(any()));
      disk.add('x.mp4', 1, DateTime(2027));
      env.media.finish(job.id);
      await pumpEventQueue();
      verify(() => env.files.list(any())).called(1);
      expect(names().first, 'x.mp4');
      repo.clearFinished();
      await pumpEventQueue();
      verifyNever(() => env.files.list(any()));
    });

    test('reloads when the download folder changes', () async {
      await c
          .read(settingsRepositoryProvider)
          .update((s) => s.copyWith(downloadDir: '/elsewhere'));
      await pumpEventQueue();
      verify(() => env.files.list(dirAt('/elsewhere'))).called(1);
    });

    test('a listing error is shown and retried', () async {
      when(() => env.files.list(any())).thenThrow(const FileError('denied'));
      vm().toggleSelected(item('a.mp4'));
      await vm().load();
      expect(state().error, isA<FileError>());
      expect(state().items, isEmpty);
      expect(state().selected, isEmpty);
      expect(state().storageBlocked, isFalse);
      disk.stub();
      await vm().load();
      expect(state().error, isNull);
      expect(names(), hasLength(3));
    });
  });

  test('no download folder is an error', () async {
    final e = TestEnv.desktop()..defaultDir = (Completer()..complete(null));
    await start(e);
    expect(state().error, isA<NoDownloadFolder>());
    expect(state().isEmpty, isTrue);
  });

  group('android', () {
    test('can open and share but not reveal', () async {
      await start(TestEnv.android());
      expect(state().canOpen, isTrue);
      expect(state().canShare, isTrue);
      expect(state().canReveal, isFalse);
      when(() => env.files.share(any())).thenAnswer((_) async {});
      await vm().share(item('b.mp3'));
      await vm().reveal(item('b.mp3'));
      verify(() => env.files.share(p.join(downloads, 'b.mp3'))).called(1);
      verifyNever(() => env.files.reveal(any()));
    });

    test('blocked storage asks for access, then lists', () async {
      final e = TestEnv.android();
      when(e.storage.ensureGranted).thenThrow(const StoragePermission());
      await start(e);
      expect(state().storageBlocked, isTrue);

      when(() => env.storage.request())
          .thenAnswer((_) async => StorageAccess.permanentlyDenied);
      when(() => env.storage.status())
          .thenAnswer((_) async => StorageAccess.denied);
      await vm().grantStorageAccess();
      verify(() => env.storage.openSettings()).called(1);
      expect(state().storageBlocked, isTrue);

      when(env.storage.ensureGranted).thenAnswer((_) async {});
      when(() => env.storage.request())
          .thenAnswer((_) async => StorageAccess.granted);
      await vm().grantStorageAccess();
      expect(state().storageBlocked, isFalse);
      expect(names(), hasLength(3));
    });
  });

  test('desktop has no storage access to grant', () async {
    await start(TestEnv.desktop(), {SettingsRepository.themeKey: 'dark'});
    await vm().grantStorageAccess();
    verifyNever(() => env.storage.request());
  });
}
