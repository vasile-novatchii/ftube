import '../../../domain/exceptions/ftube_exception.dart';
import '../../../domain/models/media_format.dart';
import '../../../domain/models/quality_preset.dart';
import 'youtube_source.dart';

/// The streams to download for one request.
///
/// When [audio] is null, [video] is downloaded and used as is. When both are
/// set, they are muxed with `-c copy` into [video]'s container.
class StreamSelection {
  const StreamSelection({required this.video, this.audio})
    : assert(video != null || audio != null, 'nothing selected');

  /// A video-only or muxed stream, or null for audio-only downloads.
  final YtStream? video;
  final YtStream? audio;

  bool get needsMerge => video != null && audio != null;

  @override
  String toString() => 'StreamSelection($video, $audio)';
}

/// Picks streams from a manifest (spec: "Android format selection").
abstract final class StreamPicker {
  /// Chooses the streams for [preset]. [formatId] is required for
  /// [QualityPreset.custom]: an itag, or `<video itag>+<audio itag>`.
  ///
  /// Throws [Unsupported] when the manifest has nothing usable.
  static StreamSelection pick(
    List<YtStream> streams,
    QualityPreset preset, {
    String? formatId,
  }) {
    if (preset == QualityPreset.custom) {
      return _custom(streams, formatId ?? '');
    }
    if (preset.isAudioOnly) {
      return StreamSelection(video: null, audio: _bestAudio(streams));
    }
    final max = preset.maxHeight;
    bool fits(YtStream s) =>
        max == null || (s.height != null && s.height! <= max);

    final videoOnly = streams
        .where((s) => s.kind == FormatKind.videoOnly && fits(s))
        .toList();
    final pairs = [
      for (final v in videoOnly)
        if (_bestAudio(streams, container: v.container, orNull: true)
            case final a?)
          (v, a),
    ]..sort((x, y) => _compareVideo(y.$1, x.$1));
    if (pairs.isNotEmpty) {
      return StreamSelection(video: pairs.first.$1, audio: pairs.first.$2);
    }

    final muxed =
        streams
            .where((s) => s.kind == FormatKind.videoAudio && fits(s))
            .toList()
          ..sort((a, b) => _compareVideo(b, a));
    if (muxed.isNotEmpty) return StreamSelection(video: muxed.first);
    throw Unsupported('no stream for $preset');
  }

  /// Formats for the "All formats" list, best first within each kind.
  static List<MediaFormat> formats(List<YtStream> streams) {
    int rank(FormatKind k) => switch (k) {
      FormatKind.videoAudio => 0,
      FormatKind.videoOnly => 1,
      FormatKind.audioOnly => 2,
    };
    final sorted = [...streams]
      ..sort((a, b) {
        final byKind = rank(a.kind).compareTo(rank(b.kind));
        if (byKind != 0) return byKind;
        return a.hasVideo ? _compareVideo(b, a) : _compareAudio(b, a);
      });
    return [
      for (final s in sorted)
        MediaFormat(
          id: '${s.tag}',
          container: s.extension,
          kind: s.kind,
          resolution: s.hasVideo ? (s.qualityLabel ?? '${s.height}p') : null,
          height: s.height,
          fps: s.fps,
          bitrateKbps: s.bitrateBps == null
              ? null
              : (s.bitrateBps! / 1000).round(),
          sizeBytes: s.sizeBytes,
        ),
    ];
  }

  static StreamSelection _custom(List<YtStream> streams, String formatId) {
    YtStream byTag(String tag) {
      final n = int.tryParse(tag.trim());
      for (final s in streams) {
        if (s.tag == n) return s;
      }
      throw Unsupported('format $tag not in manifest');
    }

    final parts = formatId.split('+');
    if (parts.length == 2) {
      final v = byTag(parts[0]);
      final a = byTag(parts[1]);
      if (v.kind != FormatKind.videoOnly || a.kind != FormatKind.audioOnly) {
        throw Unsupported('format $formatId is not video+audio');
      }
      return StreamSelection(video: v, audio: a);
    }
    if (parts.length != 1) throw Unsupported('format $formatId');
    final s = byTag(parts.single);
    return switch (s.kind) {
      FormatKind.audioOnly => StreamSelection(video: null, audio: s),
      FormatKind.videoAudio => StreamSelection(video: s),
      FormatKind.videoOnly => StreamSelection(
        video: s,
        audio:
            _bestAudio(streams, container: s.container, orNull: true) ??
            (throw Unsupported('no audio for format $formatId')),
      ),
    };
  }

  /// Highest-bitrate audio-only stream, optionally limited to [container].
  static YtStream? _bestAudio(
    List<YtStream> streams, {
    String? container,
    bool orNull = false,
  }) {
    final audio =
        streams
            .where(
              (s) =>
                  s.kind == FormatKind.audioOnly &&
                  (container == null || s.container == container),
            )
            .toList()
          ..sort((a, b) => _compareAudio(b, a));
    if (audio.isNotEmpty) return audio.first;
    if (orNull) return null;
    throw const Unsupported('no audio stream');
  }

  /// Orders by height, then fps, then mp4 over webm (plays everywhere),
  /// then bitrate.
  static int _compareVideo(YtStream a, YtStream b) {
    final h = (a.height ?? 0).compareTo(b.height ?? 0);
    if (h != 0) return h;
    final f = (a.fps ?? 0).compareTo(b.fps ?? 0);
    if (f != 0) return f;
    final c = (a.container == 'mp4' ? 1 : 0).compareTo(
      b.container == 'mp4' ? 1 : 0,
    );
    if (c != 0) return c;
    return (a.bitrateBps ?? 0).compareTo(b.bitrateBps ?? 0);
  }

  static int _compareAudio(YtStream a, YtStream b) =>
      (a.bitrateBps ?? 0).compareTo(b.bitrateBps ?? 0);
}
