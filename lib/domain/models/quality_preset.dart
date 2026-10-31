import 'audio_target.dart';

/// Download quality chosen on the Home screen.
enum QualityPreset {
  best(),
  p1080(maxHeight: 1080),
  p720(maxHeight: 720),
  p480(maxHeight: 480),
  audioMp3(audioTarget: AudioTarget.mp3),
  audioOgg(audioTarget: AudioTarget.ogg),

  /// A specific format picked from the "All formats" list.
  custom();

  const QualityPreset({this.maxHeight, this.audioTarget});

  /// Highest video height allowed, or null for no limit.
  final int? maxHeight;

  /// Target audio format for audio-only presets.
  final AudioTarget? audioTarget;

  bool get isAudioOnly => audioTarget != null;
}
