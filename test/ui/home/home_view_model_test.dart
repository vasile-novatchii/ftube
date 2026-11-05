import 'dart:async';

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
      await vm().download();
      vm().selectFormat('140');
      await vm().download();
      final ids = c
          .read(downloadRepositoryProvider)
          .jobs
          .map((j) => j.request.formatId);
      expect(ids, ['137+ba', '140']);
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

  group('android', () {
    setUp(() => setUpEnv(TestEnv.android()));

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
