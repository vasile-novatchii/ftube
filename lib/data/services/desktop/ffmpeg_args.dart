import '../../../domain/models/audio_target.dart';

/// ffmpeg and ffprobe command lines and output parsing for conversions.
abstract final class FfmpegArgs {
  /// `ffprobe` call that prints only the duration in seconds.
  static List<String> probeDuration(String src) => [
    '-v',
    'error',
    '-show_entries',
    'format=duration',
    '-of',
    'default=noprint_wrappers=1:nokey=1',
    src,
  ];

  /// Audio conversion with the same codec settings as `ftube.sh`
  /// (stereo, 320 kb/s), writing machine-readable progress to stdout.
  static List<String> convert(String src, AudioTarget target, String dst) => [
    '-hide_banner',
    '-nostdin',
    '-y',
    '-i',
    src,
    '-vn',
    '-acodec',
    switch (target) {
      AudioTarget.mp3 => 'libmp3lame',
      AudioTarget.ogg => 'libvorbis',
    },
    '-ac',
    '2',
    '-b:a',
    '320k',
    '-progress',
    'pipe:1',
    '-nostats',
    dst,
  ];

  /// Parses ffprobe's duration output, or null when it is not a number.
  static Duration? parseDuration(String stdout) {
    final seconds = double.tryParse(stdout.trim());
    if (seconds == null || seconds <= 0) return null;
    return Duration(microseconds: (seconds * 1e6).round());
  }

  /// Position from an `out_time_us=` progress line, or null for other lines.
  static Duration? parseOutTime(String line) {
    const key = 'out_time_us=';
    if (!line.startsWith(key)) return null;
    final us = int.tryParse(line.substring(key.length).trim());
    return us == null || us < 0 ? null : Duration(microseconds: us);
  }
}
