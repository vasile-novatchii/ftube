import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/domain/models/models.dart';

void main() {
  test('video presets cap the height', () {
    expect(QualityPreset.best.maxHeight, isNull);
    expect(QualityPreset.p1080.maxHeight, 1080);
    expect(QualityPreset.p720.maxHeight, 720);
    expect(QualityPreset.p480.maxHeight, 480);
    expect(QualityPreset.p360.maxHeight, 360);
  });

  test('audio presets map to an audio target', () {
    expect(QualityPreset.audioMp3.audioTarget, AudioTarget.mp3);
    expect(QualityPreset.audioOgg.audioTarget, AudioTarget.ogg);
    // M4A keeps the original stream, so it has no target.
    expect(QualityPreset.audioM4a.audioTarget, isNull);
    expect(QualityPreset.values.where((p) => p.isAudioOnly), [
      QualityPreset.audioMp3,
      QualityPreset.audioM4a,
      QualityPreset.audioOgg,
    ]);
  });

  test('audio targets expose their extension', () {
    expect(AudioTarget.mp3.extension, 'mp3');
    expect(AudioTarget.ogg.extension, 'ogg');
  });
}
