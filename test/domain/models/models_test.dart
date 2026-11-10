import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/domain/exceptions/ftube_exception.dart';
import 'package:ftube/domain/models/models.dart';

void main() {
  final outDir = Directory('/tmp/Ftube');

  DownloadRequest request({
    QualityPreset preset = QualityPreset.best,
    String? formatId,
  }) => DownloadRequest(
    jobId: 'j1',
    url: 'https://youtu.be/x',
    preset: preset,
    outDir: outDir,
    formatId: formatId,
  );

  group('DownloadRequest', () {
    test('custom preset requires a formatId', () {
      expect(
        () => request(preset: QualityPreset.custom),
        throwsA(isA<AssertionError>()),
      );
      expect(
        request(preset: QualityPreset.custom, formatId: '137').formatId,
        '137',
      );
    });

    test('has value equality', () {
      expect(request(), request());
      expect(request(), isNot(request(preset: QualityPreset.p720)));
    });
  });

  group('JobProgress', () {
    test('rejects a fraction outside 0..1', () {
      expect(
        () => JobProgress(jobId: 'j1', phase: JobPhase.merging, fraction: 1.5),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => JobProgress(jobId: 'j1', phase: JobPhase.merging, fraction: -0.1),
        throwsA(isA<AssertionError>()),
      );
    });

    test('accepts unknown and boundary fractions', () {
      for (final f in [null, 0.0, 1.0]) {
        expect(
          JobProgress(
            jobId: 'j1',
            phase: JobPhase.finished,
            fraction: f,
          ).fraction,
          f,
        );
      }
    });
  });

  group('DownloadJob', () {
    test('defaults to queued and reads id and output from its parts', () {
      final job = DownloadJob(
        request: request(),
        title: 'Song',
        createdAt: DateTime(2026),
      );
      expect(job.status, JobStatus.queued);
      expect(job.id, 'j1');
      expect(job.outputPath, isNull);

      final done = job.copyWith(
        status: JobStatus.completed,
        progress: const JobProgress(
          jobId: 'j1',
          phase: JobPhase.finished,
          fraction: 1,
          outputPath: '/tmp/Ftube/Song.mp4',
        ),
      );
      expect(done.outputPath, '/tmp/Ftube/Song.mp4');
      expect(done.request, job.request);
    });

    test('keeps the failure', () {
      const error = Network('timeout');
      final job = DownloadJob(
        request: request(),
        title: 'Song',
        createdAt: DateTime(2026),
        status: JobStatus.failed,
        error: error,
      );
      expect(job.error, same(error));
    });
  });

  group('MediaInfo', () {
    test('defaults to no formats and supports value equality', () {
      const a = MediaInfo(url: 'u', title: 't');
      expect(a.formats, isEmpty);
      const format = MediaFormat(
        id: '137',
        container: 'mp4',
        kind: FormatKind.videoOnly,
        resolution: '1920x1080',
        height: 1080,
      );
      expect(
        const MediaInfo(url: 'u', title: 't', formats: [format]),
        const MediaInfo(url: 'u', title: 't', formats: [format]),
      );
    });
  });

  group('PlaylistEntry', () {
    test('only plain available videos are downloadable', () {
      const e = PlaylistEntry(url: 'u', title: 't');
      expect(e.downloadable, isTrue);
      expect(e.copyWith(isList: true).downloadable, isFalse);
      expect(e.copyWith(unavailable: true).downloadable, isFalse);
      const p = PlaylistInfo(url: 'u', title: 't');
      expect(p.entries, isEmpty);
      expect(p.truncated, isFalse);
      expect(p, const PlaylistInfo(url: 'u', title: 't'));
    });
  });

  group('LibraryKind.fromPath', () {
    test('detects video, audio and other by extension', () {
      expect(LibraryKind.fromPath('/a/b/clip.MP4'), LibraryKind.video);
      expect(LibraryKind.fromPath(r'C:\Users\me\x.webm'), LibraryKind.video);
      expect(LibraryKind.fromPath('song.mp3'), LibraryKind.audio);
      expect(LibraryKind.fromPath('song.opus'), LibraryKind.audio);
      expect(LibraryKind.fromPath('notes.txt'), LibraryKind.other);
      expect(LibraryKind.fromPath('noext'), LibraryKind.other);
      expect(LibraryKind.fromPath('/a.b/.hidden'), LibraryKind.other);
    });
  });

  group('AppSettings', () {
    test('defaults match the spec', () {
      const s = AppSettings();
      expect(s.theme, ThemePreference.system);
      expect(s.language, AppLanguage.en);
      expect(s.downloadDir, isNull);
      expect(s.defaultPreset, QualityPreset.best);
      expect(s.concurrentDownloads, 2);
    });

    test('concurrent downloads stay within 1..3', () {
      expect(
        () => AppSettings(concurrentDownloads: 0),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => AppSettings(concurrentDownloads: 4),
        throwsA(isA<AssertionError>()),
      );
      expect(const AppSettings(concurrentDownloads: 3).concurrentDownloads, 3);
    });

    test('languages expose their locale code', () {
      expect(AppLanguage.values.map((l) => l.code), [
        'en',
        'ro',
        'ru',
        'es',
        'de',
        'ar',
      ]);
    });
  });
}
