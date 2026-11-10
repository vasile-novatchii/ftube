import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/config/providers.dart';
import 'package:ftube/data/services/android/storage_permission_service.dart';
import 'package:ftube/domain/exceptions/ftube_exception.dart';
import 'package:ftube/domain/models/models.dart';
import 'package:ftube/ui/home/view_model/home_view_model.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers.dart';

const url = 'https://youtu.be/abc';

const info = MediaInfo(
  url: url,
  title: 'Song',
  uploader: 'Band',
  duration: Duration(minutes: 3, seconds: 42),
  formats: [
    MediaFormat(
      id: '137',
      container: 'mp4',
      kind: FormatKind.videoOnly,
      resolution: '1080p',
      height: 1080,
    ),
    MediaFormat(
      id: '140',
      container: 'm4a',
      kind: FormatKind.audioOnly,
      bitrateKbps: 128,
    ),
  ],
);

const playlist = PlaylistInfo(
  url: 'https://youtube.com/playlist?list=PL1',
  title: 'Mix',
  entries: [
    PlaylistEntry(url: 'https://youtu.be/a', title: 'A'),
    PlaylistEntry(url: 'https://youtu.be/b', title: 'B', unavailable: true),
    PlaylistEntry(url: 'https://youtu.be/c', title: 'C'),
    PlaylistEntry(
      url: 'https://youtube.com/@c/videos',
      title: 'Videos',
      isList: true,
    ),
  ],
);

void main() {
  late TestEnv env;
  late ProviderContainer c;

  HomeViewModel vm() => c.read(homeViewModelProvider.notifier);
  HomeState state() => c.read(homeViewModelProvider);

  Future<void> setUpEnv(
    TestEnv e, [
    Map<String, Object> prefs = const {},
  ]) async {
    env = e..media.onFetch = (_) async => info;
    c = await env.container(prefs);
    c.listen(homeViewModelProvider, (_, _) {});
  }

  Future<void> fetched() async {
    vm().setUrl(url);
    await vm().fetch();
  }

  group('desktop', () {
    setUp(() => setUpEnv(TestEnv.desktop()));

    test('starts empty with the default preset', () {
      expect(state().url, '');
      expect(state().preset, QualityPreset.best);
      expect(state().canFetch, isFalse);
      expect(state().canDownload, isFalse);
    });

    test(
      'the default preset comes from Settings until a video is fetched',
      () async {
        await c
            .read(settingsRepositoryProvider)
            .update((s) => s.copyWith(defaultPreset: QualityPreset.p720));
        expect(state().preset, QualityPreset.p720);
        await fetched();
        await c
            .read(settingsRepositoryProvider)
            .update((s) => s.copyWith(defaultPreset: QualityPreset.p480));
        expect(state().preset, QualityPreset.p720);
      },
    );

    test('fetch reads the info for a trimmed link', () async {
      vm().setUrl('  $url ');
      expect(state().canFetch, isTrue);
      final f = vm().fetch();
      expect(state().fetching, isTrue);
      expect(state().canFetch, isFalse);
      await f;
      expect(env.media.fetched, [url]);
      expect(state().url, url);
      expect(state().info, info);
      expect(state().fetching, isFalse);
      expect(state().canDownload, isTrue);
    });

    test('rejects anything but an http(s) link', () async {
      for (final bad in ['abc', 'ftp://x.com/a', 'https://', 'file:///a']) {
        vm().setUrl(bad);
        await vm().fetch();
        expect(state().error, isA<InvalidUrl>(), reason: bad);
      }
      expect(env.media.fetched, isEmpty);
    });

    test('an empty link or a running fetch does nothing', () async {
      await vm().fetch();
      final pending = Completer<MediaInfo>();
      env.media.onFetch = (_) => pending.future;
      vm().setUrl(url);
      unawaited(vm().fetch());
      await vm().fetch();
      expect(env.media.fetched, [url]);
      pending.complete(info);
    });

    test('a failed fetch shows the error, and typing clears it', () async {
      env.media.onFetch = (_) async => throw const Network();
      await fetched();
      expect(state().error, isA<Network>());
      expect(state().info, isNull);
      vm().setUrl('x');
      expect(state().error, isNull);
    });

    test('presets and formats', () async {
      await fetched();
      vm().selectFormat('137');
      expect(state().preset, QualityPreset.custom);
      expect(state().selectedFormat!.id, '137');
      vm().selectPreset(QualityPreset.audioMp3);
      expect(state().formatId, isNull);
      expect(state().selectedFormat, isNull);
      expect(
        () => vm().selectPreset(QualityPreset.custom),
        throwsArgumentError,
      );
    });

    test('a new fetch resets a picked format to the default', () async {
      await fetched();
      vm().selectFormat('140');
      await fetched();
      expect(state().preset, QualityPreset.best);
      expect(state().formatId, isNull);
    });

    test('download queues the video in the download folder', () async {
      await fetched();
      vm().selectPreset(QualityPreset.p1080);
      final job = await vm().download();
      expect(job, isNotNull);
      final queued = c.read(downloadRepositoryProvider).jobs.single;
      expect(queued.title, 'Song');
      expect(queued.request.url, url);
      expect(queued.request.preset, QualityPreset.p1080);
      expect(queued.request.formatId, isNull);
      expect(queued.request.outDir.path, '/home/me/Downloads/Ftube');
    });

    test('a video-only format gets the best audio on desktop', () async {
      await fetched();
      vm().selectFormat('137');
      final first = await vm().download();
      env.media.finish(first!.id);
      await pumpEventQueue();
      vm().selectFormat('140');
      await vm().download();
      final ids = c
          .read(downloadRepositoryProvider)
          .jobs
          .map((j) => j.request.formatId);
      expect(ids, ['137+ba', '140']);
    });

    test('a video in the queue is not queued again, matched by id', () async {
      const id = 'dQw4w9WgXcQ';
      env.media.onFetch = (u) async => info.copyWith(url: u);
      vm().setUrl('https://youtu.be/$id');
      await vm().fetch();
      final job = await vm().download();
      await pumpEventQueue();
      expect(state().videoActive, isTrue);
      expect(state().canDownload, isFalse);
      vm().setUrl('https://www.youtube.com/watch?v=$id');
      await vm().fetch();
      expect(state().videoActive, isTrue);
      expect(await vm().download(), isNull);
      await c.read(downloadRepositoryProvider).cancel(job!.id);
      await pumpEventQueue();
      expect(state().canDownload, isTrue);
    });

    test('download without a folder shows NoDownloadFolder', () async {
      env.failLookups = true;
      c = await env.container();
      c.listen(homeViewModelProvider, (_, _) {});
      await fetched();
      expect(await vm().download(), isNull);
      expect(state().error, isA<NoDownloadFolder>());
    });

    test('download before a fetch does nothing', () async {
      expect(await vm().download(), isNull);
    });

    test('paste fills the link and fetches', () async {
      env.clipboard = '  $url\n';
      await vm().paste();
      expect(state().url, url);
      expect(state().info, info);
    });

    test('paste ignores an empty or unreadable clipboard', () async {
      await vm().paste();
      env.clipboardError = true;
      await vm().paste();
      expect(env.media.fetched, isEmpty);
    });

    test('a clipboard link is offered once', () async {
      env.clipboard = url;
      await vm().checkClipboard();
      expect(state().clipboardUrl, url);
      vm().dismissClipboard();
      await vm().checkClipboard();
      expect(state().clipboardUrl, isNull);
    });

    test('text and the current link are not offered', () async {
      env.clipboard = 'hello';
      await vm().checkClipboard();
      expect(state().clipboardUrl, isNull);
      env.clipboard = url;
      vm().setUrl(url);
      await vm().checkClipboard();
      expect(state().clipboardUrl, isNull);
      env.clipboard = null;
      await vm().checkClipboard();
      expect(state().clipboardUrl, isNull);
    });

    test('using the offered link fetches it', () async {
      env.clipboard = url;
      await vm().checkClipboard();
      await vm().useClipboard();
      expect(state().clipboardUrl, isNull);
      expect(state().info, info);
      await vm().useClipboard();
      expect(env.media.fetched, [url]);
    });

    test('storage commands do nothing on desktop', () async {
      await vm().grantStorageAccess();
      await vm().refreshStorageAccess();
      expect(state().storageBlocked, isFalse);
    });
  });

  group('playlist', () {
    setUp(() async {
      await setUpEnv(TestEnv.desktop());
      env.media.onFetch = (u) async => u == playlist.url ? playlist : info;
    });

    Future<void> fetchList() async {
      vm().setUrl(playlist.url);
      await vm().fetch();
    }

    test('selects every downloadable entry', () async {
      await fetchList();
      expect(state().playlist, playlist);
      expect(state().video, isNull);
      expect(state().selected, {0, 2});
      expect(state().canDownload, isTrue);
      expect(state().offersPlaylist, isFalse);
    });

    test('toggle, select none and select all', () async {
      await fetchList();
      vm().toggleEntry(0);
      expect(state().selected, {2});
      vm()
        ..toggleEntry(1) // unavailable
        ..toggleEntry(3) // a channel tab
        ..toggleEntry(9);
      expect(state().selected, {2});
      vm().toggleEntry(0);
      expect(state().selected, {0, 2});
      vm().selectNone();
      expect(state().selected, isEmpty);
      expect(state().canDownload, isFalse);
      expect(await vm().downloadPlaylist(), isNull);
      vm().selectAll();
      expect(state().selected, {0, 2});
    });

    test('downloadPlaylist queues the selected entries', () async {
      await fetchList();
      vm()
        ..selectPreset(QualityPreset.audioM4a)
        ..toggleEntry(0);
      final jobs = await vm().downloadPlaylist();
      expect(jobs!.map((j) => j.title), ['C']);
      final queued = c.read(downloadRepositoryProvider).jobs.single;
      expect(queued.request.url, 'https://youtu.be/c');
      expect(queued.request.preset, QualityPreset.audioM4a);
      expect(state().error, isNull);
    });

    test('a video download does nothing on a playlist', () async {
      await fetchList();
      expect(await vm().download(), isNull);
      vm().selectFormat('140');
      expect(state().preset, QualityPreset.best);
    });

    test('downloadPlaylist without a folder shows NoDownloadFolder', () async {
      env.failLookups = true;
      c = await env.container();
      c.listen(homeViewModelProvider, (_, _) {});
      await fetchList();
      expect(await vm().downloadPlaylist(), isNull);
      expect(state().error, isA<NoDownloadFolder>());
    });

    test('opening a channel tab fetches it as a new link', () async {
      await fetchList();
      await vm().openEntry(0); // a video, not a list
      expect(env.media.fetched, [playlist.url]);
      await vm().openEntry(3);
      expect(state().url, 'https://youtube.com/@c/videos');
      expect(env.media.fetched.last, 'https://youtube.com/@c/videos');
      expect(state().selected, isEmpty);
    });

    test('a video link with list= offers its playlist', () async {
      const watch = 'https://www.youtube.com/watch?v=abc&list=PL1';
      vm().setUrl(watch);
      await vm().fetch();
      expect(state().offersPlaylist, isTrue);
      env.media.onFetch = (_) async => playlist;
      await vm().showPlaylist();
      expect(env.media.fetchedPlaylists, [watch]);
      expect(state().playlist, playlist);
      expect(state().offersPlaylist, isFalse);
      await vm().showPlaylist();
      expect(env.media.fetchedPlaylists, hasLength(1));
    });

    test('openLink fills the field, fetches and counts', () async {
      vm().setUrl(url);
      final f = vm().fetch();
      await vm().openLink(playlist.url);
      await f;
      expect(state().url, playlist.url);
      expect(state().linkOpened, 1);
      expect(state().playlist, playlist);
    });

    test('a playlist link with no downloadable entries', () async {
      env.media.onFetch = (_) async => const PlaylistInfo(
        url: 'https://youtube.com/@c',
        title: 'C',
        entries: [PlaylistEntry(url: 'u', title: 'Videos', isList: true)],
      );
      vm().setUrl('https://youtube.com/@c');
      await vm().fetch();
      expect(state().selected, isEmpty);
      expect(state().selectedEntries, isEmpty);
      expect(state().canDownload, isFalse);
    });

    test(
      'queued entries leave the selection and are not queued again',
      () async {
        await fetchList();
        final jobs = await vm().downloadPlaylist();
        expect(jobs, hasLength(2));
        await pumpEventQueue();
        expect(state().selected, isEmpty);
        expect(state().activeStatus('https://youtu.be/a'), isNotNull);
        expect(state().canDownload, isFalse);
        vm()
          ..selectAll()
          ..toggleEntry(0);
        expect(state().selected, isEmpty);
        expect(await vm().downloadPlaylist(), isNull);
        expect(c.read(downloadRepositoryProvider).jobs, hasLength(2));

        env.media.finish(jobs![0].id);
        await pumpEventQueue();
        vm().selectAll();
        expect(state().selected, {0});
      },
    );

    test('a selection skips entries queued meanwhile', () async {
      await fetchList();
      c
          .read(downloadRepositoryProvider)
          .enqueue(
            url: 'https://youtu.be/a',
            title: 'A',
            preset: QualityPreset.best,
            outDir: Directory('/out'),
          );
      await pumpEventQueue();
      expect(state().selected, {0, 2});
      expect(state().selectedEntries.map((e) => e.title), ['C']);
    });

    test('a video playlist opens collapsed, a list of tabs expanded', () async {
      env.media.onFetch = (_) async =>
          playlist.copyWith(entries: playlist.entries.take(3).toList());
      await fetchList();
      expect(state().listOpen, isFalse);
      vm().toggleList();
      expect(state().listOpen, isTrue);
      vm().toggleList();
      expect(state().listOpen, isFalse);

      env.media.onFetch = (_) async => playlist;
      await vm().fetch();
      expect(state().listOpen, isTrue);
    });

    test('back returns to the channel without a fetch', () async {
      await fetchList();
      vm().toggleEntry(0);
      await vm().openEntry(3);
      expect(state().back.single.url, playlist.url);
      final fetches = env.media.fetched.length;
      expect(vm().goBack(), isTrue);
      expect(env.media.fetched, hasLength(fetches));
      expect(state().url, playlist.url);
      expect(state().playlist, playlist);
      expect(state().selected, {2});
      expect(state().listOpen, isTrue);
      expect(state().back, isEmpty);
      expect(vm().goBack(), isFalse);
    });

    test('a fresh link clears the back steps', () async {
      await fetchList();
      await vm().openEntry(3);
      vm().setUrl(url);
      await vm().fetch();
      expect(state().back, isEmpty);

      await fetchList();
      await vm().openEntry(3);
      await vm().openLink(url);
      expect(state().back, isEmpty);
    });

    test('Show playlist can go back to the video', () async {
      const watch = 'https://www.youtube.com/watch?v=abc&list=PL1';
      vm().setUrl(watch);
      await vm().fetch();
      env.media.onFetch = (_) async => playlist;
      await vm().showPlaylist();
      expect(vm().goBack(), isTrue);
      expect(state().video, info);
      expect(state().url, watch);
    });

    test('going back drops a fetch still running', () async {
      await fetchList();
      final pending = Completer<FetchResult>();
      env.media.onFetch = (_) => pending.future;
      final opening = vm().openEntry(3);
      expect(state().fetching, isTrue);
      vm().goBack();
      pending.complete(info);
      await opening;
      expect(state().playlist, playlist);
      expect(state().fetching, isFalse);
    });
  });

  group('android', () {
    setUp(() => setUpEnv(TestEnv.android()));

    test('a playlist download is blocked without storage access', () async {
      env.media.onFetch = (_) async => playlist;
      when(env.storage.status).thenAnswer((_) async => StorageAccess.denied);
      vm().setUrl(playlist.url);
      await vm().fetch();
      expect(await vm().downloadPlaylist(), isNull);
      expect(state().storageBlocked, isTrue);
    });

    test('a video-only format gets the best audio', () async {
      await fetched();
      vm().selectFormat('137');
      await vm().download();
      expect(
        c.read(downloadRepositoryProvider).jobs.single.request.formatId,
        '137+ba',
      );
    });

    test('download is blocked without storage access', () async {
      when(env.storage.status).thenAnswer((_) async => StorageAccess.denied);
      await fetched();
      expect(await vm().download(), isNull);
      expect(state().storageBlocked, isTrue);
      expect(state().canDownload, isFalse);
      expect(c.read(downloadRepositoryProvider).jobs, isEmpty);
    });

    test('granting access unblocks downloads', () async {
      when(env.storage.status).thenAnswer((_) async => StorageAccess.denied);
      await fetched();
      await vm().download();
      when(env.storage.request).thenAnswer((_) async => StorageAccess.granted);
      await vm().grantStorageAccess();
      expect(state().storageBlocked, isFalse);
    });

    test('a refused request opens the app settings', () async {
      when(env.storage.status).thenAnswer((_) async => StorageAccess.denied);
      await fetched();
      await vm().download();
      when(env.storage.request)
          .thenAnswer((_) async => StorageAccess.permanentlyDenied);
      await vm().grantStorageAccess();
      verify(env.storage.openSettings).called(1);
      expect(state().storageBlocked, isTrue);
    });

    test('coming back with access granted unblocks downloads', () async {
      when(env.storage.status).thenAnswer((_) async => StorageAccess.denied);
      await fetched();
      await vm().download();
      await vm().refreshStorageAccess();
      expect(state().storageBlocked, isTrue);
      when(env.storage.status).thenAnswer((_) async => StorageAccess.granted);
      await vm().refreshStorageAccess();
      expect(state().storageBlocked, isFalse);
    });
  });

  test('isWebUrl', () {
    expect(isWebUrl(' http://a.b/c '), isTrue);
    expect(isWebUrl('youtu.be/x'), isFalse);
  });
}
