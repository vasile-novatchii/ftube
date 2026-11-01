import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/data/services/android/stream_picker.dart';
import 'package:ftube/data/services/android/youtube_source.dart';
import 'package:ftube/domain/exceptions/ftube_exception.dart';
import 'package:ftube/domain/models/models.dart';

import 'fakes.dart';

void main() {
  /// A typical manifest: mp4 and webm video up to 2160p, audio in both.
  final manifest = [
    muxed(18, 'mp4', 360),
    videoOnly(137, 'mp4', 1080),
    videoOnly(248, 'webm', 1080),
    videoOnly(299, 'mp4', 1080, fps: 60),
    videoOnly(136, 'mp4', 720),
    videoOnly(247, 'webm', 720),
    videoOnly(135, 'mp4', 480),
    videoOnly(313, 'webm', 2160),
    audioOnly(140, 'mp4', 128000),
    audioOnly(139, 'mp4', 48000),
    audioOnly(251, 'webm', 160000),
    audioOnly(250, 'webm', 70000),
  ];

  List<int?> tags(StreamSelection s) => [s.video?.tag, s.audio?.tag];

  group('presets', () {
    test('best takes the highest video with matching audio', () {
      final s = StreamPicker.pick(manifest, QualityPreset.best);
      expect(tags(s), [313, 251]);
      expect(s.needsMerge, isTrue);
    });

    test('p1080 prefers 60 fps, then pairs mp4 with m4a audio', () {
      expect(tags(StreamPicker.pick(manifest, QualityPreset.p1080)), [
        299,
        140,
      ]);
    });

    test('p720 prefers mp4 over webm at the same height and fps', () {
      expect(tags(StreamPicker.pick(manifest, QualityPreset.p720)), [136, 140]);
    });

    test('p480 never goes above the limit', () {
      expect(tags(StreamPicker.pick(manifest, QualityPreset.p480)), [135, 140]);
    });

    test('skips video that has no audio in its container', () {
      final streams = [
        videoOnly(313, 'webm', 2160),
        videoOnly(137, 'mp4', 1080),
        audioOnly(140, 'mp4', 128000),
      ];
      expect(tags(StreamPicker.pick(streams, QualityPreset.best)), [137, 140]);
    });

    test('falls back to a muxed stream without merging', () {
      final streams = [muxed(18, 'mp4', 360), videoOnly(137, 'mp4', 1080)];
      final s = StreamPicker.pick(streams, QualityPreset.best);
      expect(tags(s), [18, null]);
      expect(s.needsMerge, isFalse);
    });

    test('audio presets take the highest bitrate in any container', () {
      for (final preset in [QualityPreset.audioMp3, QualityPreset.audioOgg]) {
        expect(tags(StreamPicker.pick(manifest, preset)), [null, 251]);
      }
    });

    test('throws Unsupported when nothing fits', () {
      expect(
        () => StreamPicker.pick([audioOnly(140, 'mp4', 1)], QualityPreset.p480),
        throwsA(isA<Unsupported>()),
      );
      expect(
        () =>
            StreamPicker.pick([muxed(18, 'mp4', 360)], QualityPreset.audioMp3),
        throwsA(isA<Unsupported>()),
      );
    });
  });

  group('custom', () {
    StreamSelection custom(String id) =>
        StreamPicker.pick(manifest, QualityPreset.custom, formatId: id);

    test('video-only itag gets matching audio', () {
      expect(tags(custom('248')), [248, 251]);
    });

    test('audio-only itag downloads alone', () {
      expect(tags(custom('139')), [null, 139]);
    });

    test('muxed itag downloads alone', () {
      expect(tags(custom('18')), [18, null]);
    });

    test('video+audio pair is used as given', () {
      expect(tags(custom('137+139')), [137, 139]);
    });

    test('rejects unknown or malformed ids', () {
      for (final id in ['999', 'abc', '', '137+18', '1+2+3']) {
        expect(() => custom(id), throwsA(isA<Unsupported>()), reason: id);
      }
    });
  });

  test('formats lists muxed, then video, then audio, best first', () {
    final formats = StreamPicker.formats(manifest);
    expect(formats.map((f) => f.id).take(3), ['18', '313', '299']);
    expect(formats.last.id, '139');

    final m4a = formats.firstWhere((f) => f.id == '140');
    expect(m4a.kind, FormatKind.audioOnly);
    expect(m4a.container, 'm4a');
    expect(m4a.bitrateKbps, 128);
    expect(m4a.resolution, isNull);

    final hd = formats.firstWhere((f) => f.id == '299');
    expect(hd.resolution, '1080p60');
    expect(hd.height, 1080);
    expect(hd.fps, 60);
  });

  test('YtStream extension is m4a for mp4 audio only', () {
    expect(audioOnly(140, 'mp4', 1).extension, 'm4a');
    expect(audioOnly(251, 'webm', 1).extension, 'webm');
    expect(videoOnly(137, 'mp4', 1080).extension, 'mp4');
    expect(
      const YtStream(
        tag: 1,
        kind: FormatKind.videoAudio,
        container: 'mp4',
      ).hasVideo,
      isTrue,
    );
  });
}
