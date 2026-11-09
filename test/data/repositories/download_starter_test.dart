import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/config/providers.dart';
import 'package:ftube/data/repositories/download_starter.dart';
import 'package:ftube/data/services/android/storage_permission_service.dart';
import 'package:ftube/domain/models/models.dart';
import 'package:mocktail/mocktail.dart';

import '../../ui/helpers.dart';

const info = MediaInfo(url: 'https://youtu.be/abc', title: 'Song');
const video = MediaFormat(
  id: '137',
  container: 'mp4',
  kind: FormatKind.videoOnly,
);
const muxed = MediaFormat(
  id: '18',
  container: 'mp4',
  kind: FormatKind.videoAudio,
);
const audio = MediaFormat(
  id: '140',
  container: 'm4a',
  kind: FormatKind.audioOnly,
);

void main() {
  late TestEnv env;
  late ProviderContainer c;

  DownloadStarter starter() => c.read(downloadStarterProvider);
  List<DownloadJob> jobs() => c.read(downloadRepositoryProvider).jobs;

  Future<void> setUpEnv(TestEnv e) async {
    env = e;
    c = await env.container();
  }

  test('selector adds the best audio to a video-only format', () {
    expect(DownloadStarter.selector(null), isNull);
    expect(DownloadStarter.selector(video), '137+ba');
    expect(DownloadStarter.selector(muxed), '18');
    expect(DownloadStarter.selector(audio), '140');
  });

  group('desktop', () {
    setUp(() => setUpEnv(TestEnv.desktop()));

    test('queues with the preset in the download folder', () async {
      final job = await starter().start(info, QualityPreset.p720);
      expect(jobs().single.request.jobId, job.request.jobId);
      expect(job.request.url, info.url);
      expect(job.title, 'Song');
      expect(job.request.preset, QualityPreset.p720);
      expect(job.request.formatId, isNull);
      expect(job.request.outDir.path, '/home/me/Downloads/Ftube');
    });

    test('a picked format overrides the preset', () async {
      final job = await starter().start(
        info,
        QualityPreset.best,
        format: video,
      );
      expect(job.request.preset, QualityPreset.custom);
      expect(job.request.formatId, '137+ba');
    });

    test('throws NoDownloadFolder without a folder', () async {
      env.failLookups = true;
      await expectLater(
        starter().start(info, QualityPreset.best),
        throwsA(isA<NoDownloadFolder>()),
      );
      expect(jobs(), isEmpty);
    });
  });

  group('android', () {
    setUp(() => setUpEnv(TestEnv.android()));

    test('queues when storage access is granted', () async {
      await starter().start(info, QualityPreset.audioMp3);
      expect(jobs().single.request.preset, QualityPreset.audioMp3);
    });

    test('throws StorageBlocked without storage access', () async {
      when(() => env.storage.status())
          .thenAnswer((_) async => StorageAccess.denied);
      await expectLater(
        starter().start(info, QualityPreset.best),
        throwsA(isA<StorageBlocked>()),
      );
      expect(jobs(), isEmpty);
    });
  });
}
