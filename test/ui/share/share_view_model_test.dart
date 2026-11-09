import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/config/providers.dart';
import 'package:ftube/data/repositories/download_starter.dart';
import 'package:ftube/data/repositories/settings_repository.dart';
import 'package:ftube/data/services/android/storage_permission_service.dart';
import 'package:ftube/domain/exceptions/ftube_exception.dart';
import 'package:ftube/domain/models/models.dart';
import 'package:ftube/ui/share/view_model/share_view_model.dart';
import 'package:mocktail/mocktail.dart';

import '../../data/services/android/share_host.dart';
import '../helpers.dart';

const url = 'https://youtu.be/abc';

const info = MediaInfo(
  url: url,
  title: 'Song',
  formats: [
    MediaFormat(id: '137', container: 'mp4', kind: FormatKind.videoOnly),
    MediaFormat(id: '18', container: 'mp4', kind: FormatKind.videoAudio),
    MediaFormat(id: '140', container: 'm4a', kind: FormatKind.audioOnly),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestEnv env;
  late ShareHost host;
  late ProviderContainer c;

  ShareViewModel vm() => c.read(shareViewModelProvider.notifier);
  ShareState state() => c.read(shareViewModelProvider);
  List<DownloadJob> jobs() => c.read(downloadRepositoryProvider).jobs;

  Future<void> setUpEnv([Map<String, Object> prefs = const {}]) async {
    c = await env.container(prefs);
    c
      ..listen(shareSessionProvider, (_, _) {})
      ..listen(shareViewModelProvider, (_, _) {});
  }

  /// Shares [text] and lets the popup load.
  Future<void> share(String? text) async {
    await host.show(text);
    await pumpEventQueue();
  }

  group('android', () {
    setUp(() async {
      host = ShareHost()..install();
      env = TestEnv.android()
        ..share = host.service
        ..media.onFetch = (_) async => info;
      await host.service.start();
      await setUpEnv();
    });

    tearDown(() async {
      c.dispose();
      host.uninstall();
      await host.service.dispose();
    });

    test('shows nothing until a share arrives', () {
      expect(c.read(shareSessionProvider), isNull);
      expect(state().url, isNull);
      expect(state().fetching, isFalse);
      expect(env.media.fetched, isEmpty);
    });

    test('a shared link is fetched with the default preset', () async {
      await host.show('Look at https://youtu.be/abc!');
      expect(state().url, url);
      expect(state().fetching, isTrue);
      expect(state().canDownload, isFalse);
      await pumpEventQueue();
      expect(env.media.fetched, [url]);
      expect(state().info, info);
      expect(state().fetching, isFalse);
      expect(state().preset, QualityPreset.best);
      expect(state().audio, isFalse);
      expect(state().canDownload, isTrue);
    });

    test('a share without a link fetches nothing', () async {
      await share('hello');
      expect(c.read(shareSessionProvider), isNotNull);
      expect(state().url, isNull);
      expect(state().fetching, isFalse);
      expect(env.media.fetched, isEmpty);
    });

    test('asks for storage access before fetching', () async {
      when(() => env.storage.status())
          .thenAnswer((_) async => StorageAccess.denied);
      await share(url);
      expect(state().noAccess, isTrue);
      expect(state().fetching, isFalse);
      expect(state().canDownload, isFalse);
      expect(env.media.fetched, isEmpty);
    });

    test('a failed fetch shows the error and can be retried', () async {
      env.media.onFetch = (_) async => throw const Network();
      await share(url);
      expect(state().error, isA<Network>());
      expect(state().canDownload, isFalse);

      env.media.onFetch = (_) async => info;
      await vm().retry();
      expect(state().error, isNull);
      expect(state().info, info);
    });

    test('retry does nothing while fetching or without a link', () async {
      await vm().retry();
      expect(env.media.fetched, isEmpty);
      final pending = Completer<MediaInfo>();
      env.media.onFetch = (_) => pending.future;
      await share(url);
      unawaited(vm().retry());
      expect(env.media.fetched, [url]);
      pending.complete(info);
    });

    test('a new share starts over and drops the older fetch', () async {
      final first = Completer<MediaInfo>();
      env.media.onFetch = (_) => first.future;
      await share(url);
      env.media.onFetch = (_) async =>
          info.copyWith(url: 'https://youtu.be/xyz', title: 'Other');
      await share('https://youtu.be/xyz');
      expect(state().info?.title, 'Other');
      first.complete(info);
      await pumpEventQueue();
      expect(state().info?.title, 'Other');
      expect(state().url, 'https://youtu.be/xyz');
    });

    test('tabs switch presets and formats', () async {
      await share(url);
      expect(state().presets, shareVideoPresets);
      expect(state().formats.map((f) => f.id), ['137', '18']);

      vm().selectTab(audio: true);
      expect(state().audio, isTrue);
      expect(state().preset, QualityPreset.audioMp3);
      expect(state().presets, shareAudioPresets);
      expect(state().formats.map((f) => f.id), ['140']);

      vm().selectTab(audio: true);
      expect(state().preset, QualityPreset.audioMp3);

      vm().selectTab(audio: false);
      expect(state().preset, QualityPreset.best);
    });

    test('a picked format overrides the chip until the tab changes', () async {
      await share(url);
      vm().selectFormat('137');
      expect(state().selectedFormat?.id, '137');
      vm().selectPreset(QualityPreset.p720);
      expect(state().formatId, isNull);
      expect(state().preset, QualityPreset.p720);

      vm().selectFormat('18');
      vm().selectTab(audio: true);
      expect(state().selectedFormat, isNull);
      // A video format is not offered on the Audio tab.
      vm().selectFormat('18');
      expect(state().selectedFormat, isNull);

      expect(
        () => vm().selectPreset(QualityPreset.custom),
        throwsArgumentError,
      );
    });

    test('download queues the video and closes with a toast', () async {
      await share(url);
      vm().selectFormat('137');
      await vm().download(toast: 'Download started');
      final job = jobs().single;
      expect(job.request.preset, QualityPreset.custom);
      expect(job.request.formatId, '137+ba');
      final close = host.calls.lastWhere((c) => c.method == 'close');
      expect(close.arguments, {'toast': 'Download started'});
      expect(c.read(shareSessionProvider), isNull);
    });

    test('download without storage access asks for it', () async {
      await share(url);
      when(() => env.storage.status())
          .thenAnswer((_) async => StorageAccess.denied);
      await vm().download(toast: 't');
      expect(state().noAccess, isTrue);
      expect(state().queuing, isFalse);
      expect(jobs(), isEmpty);
      expect(c.read(shareSessionProvider), isNotNull);
    });

    test('download without a folder shows the error', () async {
      await share(url);
      env.failLookups = true;
      c.invalidate(downloadDirectoryProvider);
      await vm().download(toast: 't');
      expect(state().error, isA<NoDownloadFolder>());
      expect(state().queuing, isFalse);
      expect(jobs(), isEmpty);
    });

    test('download does nothing before the video is fetched', () async {
      await vm().download(toast: 't');
      expect(jobs(), isEmpty);
      expect(host.calls.where((c) => c.method == 'close'), isEmpty);
    });

    test('close and openApp end the share through Android', () async {
      await share(url);
      await c.read(shareSessionProvider.notifier).close();
      expect(host.calls.last.method, 'close');
      expect(c.read(shareSessionProvider), isNull);

      await share(url);
      await c.read(shareSessionProvider.notifier).openApp();
      expect(host.calls.last.method, 'openApp');
      expect(c.read(shareSessionProvider), isNull);
    });

    test('close ends the share itself when Android fails', () async {
      await share(url);
      host.fail = true;
      await c.read(shareSessionProvider.notifier).close();
      expect(c.read(shareSessionProvider), isNull);
      await share(url);
      await c.read(shareSessionProvider.notifier).openApp();
      expect(c.read(shareSessionProvider), isNull);
    });
  });

  test('the default preset comes from Settings', () async {
    host = ShareHost(pending: url)..install();
    addTearDown(host.uninstall);
    env = TestEnv.android()
      ..share = host.service
      ..media.onFetch = (_) async => info;
    await host.service.start();
    await setUpEnv({SettingsRepository.presetKey: 'audioOgg'});
    addTearDown(c.dispose);
    await pumpEventQueue();
    expect(state().preset, QualityPreset.audioOgg);
    expect(state().audio, isTrue);
    vm().selectTab(audio: false);
    expect(state().preset, QualityPreset.best);
    vm().selectTab(audio: true);
    expect(state().preset, QualityPreset.audioOgg);
  });

  test('a custom default preset falls back to Best', () async {
    host = ShareHost(pending: url)..install();
    addTearDown(host.uninstall);
    env = TestEnv.android()
      ..share = host.service
      ..media.onFetch = (_) async => info;
    await host.service.start();
    await setUpEnv({SettingsRepository.presetKey: 'custom'});
    addTearDown(c.dispose);
    expect(state().preset, QualityPreset.best);
  });

  test('desktop has no share session', () async {
    env = TestEnv.desktop();
    await setUpEnv();
    addTearDown(c.dispose);
    expect(c.read(shareSessionProvider), isNull);
    await c.read(shareSessionProvider.notifier).close();
    await c.read(shareSessionProvider.notifier).openApp();
    expect(c.read(shareSessionProvider), isNull);
  });
}
