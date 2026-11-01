import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import '../../../domain/exceptions/ftube_exception.dart';
import '../../../domain/models/media_format.dart';

/// Title and metadata of one YouTube video.
class YtVideo {
  const YtVideo({
    required this.id,
    required this.title,
    this.author,
    this.duration,
    this.thumbnailUrl,
  });

  final String id;
  final String title;
  final String? author;
  final Duration? duration;
  final String? thumbnailUrl;
}

/// One stream of a YouTube manifest, without the package types, so the
/// stream picker and the service can be tested with plain values.
class YtStream {
  const YtStream({
    required this.tag,
    required this.kind,
    required this.container,
    this.height,
    this.fps,
    this.bitrateBps,
    this.sizeBytes,
    this.qualityLabel,
    this.handle,
  });

  /// YouTube itag, unique within a manifest. Used as the format id.
  final int tag;
  final FormatKind kind;

  /// `mp4` or `webm` (also used as the file extension).
  final String container;
  final int? height;
  final int? fps;
  final int? bitrateBps;
  final int? sizeBytes;
  final String? qualityLabel;

  /// The package's stream object, passed back to [YoutubeSource.open].
  final Object? handle;

  bool get hasVideo => kind != FormatKind.audioOnly;

  /// Extension of the audio file this stream holds, or of the video file.
  String get extension =>
      kind == FormatKind.audioOnly && container == 'mp4' ? 'm4a' : container;

  @override
  String toString() => 'YtStream($tag, $kind, $container, ${height}p)';
}

/// The parts of `youtube_explode_dart` that [AndroidMediaService] uses.
///
/// Errors are reported as `FtubeException` subclasses.
abstract interface class YoutubeSource {
  /// Video id of [url], or null when [url] is not a YouTube video URL.
  String? parseVideoId(String url);

  Future<YtVideo> video(String videoId);

  /// A fresh manifest. YouTube may refuse a second download from the same
  /// manifest, so callers fetch one per stream they download.
  Future<List<YtStream>> streams(String videoId);

  /// Bytes of [stream], which must come from [streams].
  Stream<List<int>> open(YtStream stream);

  void close();
}

/// [YoutubeSource] backed by `youtube_explode_dart`.
class ExplodeYoutubeSource implements YoutubeSource {
  ExplodeYoutubeSource([yt.YoutubeExplode? client])
    : _yt = client ?? yt.YoutubeExplode();

  final yt.YoutubeExplode _yt;

  @override
  String? parseVideoId(String url) => yt.VideoId.parseVideoId(url.trim());

  @override
  Future<YtVideo> video(String videoId) => _guard(() async {
    final v = await _yt.videos.get(videoId);
    return YtVideo(
      id: v.id.value,
      title: v.title,
      author: v.author,
      duration: v.duration,
      thumbnailUrl: v.thumbnails.highResUrl,
    );
  });

  @override
  Future<List<YtStream>> streams(String videoId) => _guard(() async {
    final manifest = await _yt.videos.streams.getManifest(videoId);
    return [for (final s in manifest.streams) ?_toStream(s)];
  });

  @override
  Stream<List<int>> open(YtStream stream) {
    final handle = stream.handle;
    if (handle is! yt.StreamInfo) {
      throw ArgumentError.value(stream, 'stream', 'not from streams()');
    }
    return _yt.videos.streams
        .get(handle)
        .handleError(
          (Object e, StackTrace st) =>
              Error.throwWithStackTrace(mapError(e), st),
        );
  }

  @override
  void close() => _yt.close();

  static YtStream? _toStream(yt.StreamInfo s) {
    final container = s.container.name;
    if (container != 'mp4' && container != 'webm') return null;
    final kind = switch (s) {
      yt.MuxedStreamInfo() => FormatKind.videoAudio,
      yt.VideoOnlyStreamInfo() => FormatKind.videoOnly,
      yt.AudioOnlyStreamInfo() => FormatKind.audioOnly,
      _ => null,
    };
    if (kind == null) return null;
    final video = s is yt.VideoStreamInfo ? s : null;
    return YtStream(
      tag: s.tag,
      kind: kind,
      container: container,
      height: video?.videoResolution.height,
      fps: video?.framerate.framesPerSecond.round(),
      bitrateBps: s.bitrate.bitsPerSecond,
      sizeBytes: s.size.totalBytes,
      qualityLabel: s.qualityLabel,
      handle: s,
    );
  }

  static Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on Object catch (e, st) {
      Error.throwWithStackTrace(mapError(e), st);
    }
  }

  /// Maps package and I/O errors to `FtubeException`s.
  static Object mapError(Object e) => switch (e) {
    FtubeException() => e,
    yt.VideoUnplayableException() => Unsupported(e.toString()),
    yt.RequestLimitExceededException() ||
    yt.TransientFailureException() ||
    SocketException() ||
    HttpException() ||
    TimeoutException() ||
    TlsException() ||
    http.ClientException() => Network(e.toString()),
    yt.YoutubeExplodeException() => Network(e.toString()),
    ArgumentError() => InvalidUrl(e.toString()),
    _ => e,
  };
}
