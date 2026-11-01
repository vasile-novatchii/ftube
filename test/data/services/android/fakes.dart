import 'dart:async';
import 'dart:io';

import 'package:ftube/data/services/android/ffmpeg_kit_runner.dart';
import 'package:ftube/data/services/android/youtube_source.dart';
import 'package:ftube/domain/models/models.dart';

YtStream muxed(int tag, String container, int height) => YtStream(
  tag: tag,
  kind: FormatKind.videoAudio,
  container: container,
  height: height,
  fps: 30,
  bitrateBps: height * 1000,
  sizeBytes: 1000,
  qualityLabel: '${height}p',
);

YtStream videoOnly(
  int tag,
  String container,
  int height, {
  int fps = 30,
  int size = 1000,
}) => YtStream(
  tag: tag,
  kind: FormatKind.videoOnly,
  container: container,
  height: height,
  fps: fps,
  bitrateBps: height * 2000,
  sizeBytes: size,
  qualityLabel: fps > 30 ? '${height}p$fps' : '${height}p',
);

YtStream audioOnly(int tag, String container, int bitrate, {int size = 100}) =>
    YtStream(
      tag: tag,
      kind: FormatKind.audioOnly,
      container: container,
      bitrateBps: bitrate,
      sizeBytes: size,
    );

/// A [YoutubeSource] that serves fixed streams. Each stream's bytes are
/// [size] bytes of its tag, sent in chunks of [chunk] bytes, unless a
/// controller is registered in [live].
class FakeYoutubeSource implements YoutubeSource {
  FakeYoutubeSource({
    required this.streamList,
    this.info = const YtVideo(
      id: 'abc123def45',
      title: 'Big Buck Bunny: 60fps 4K!',
      author: 'Blender',
      duration: Duration(seconds: 10),
      thumbnailUrl: 'https://img.test/t.jpg',
    ),
    this.chunk = 400,
  });

  List<YtStream> streamList;
  YtVideo info;
  final int chunk;

  Object? videoError;
  Object? streamsError;

  /// Error thrown by the stream with this tag after its first chunk.
  final failAfterFirstChunk = <int, Object>{};

  /// Streams left open until the test closes them.
  final live = <int, StreamController<List<int>>>{};

  int manifestCalls = 0;
  final opened = <int>[];
  bool closed = false;

  @override
  String? parseVideoId(String url) {
    final uri = Uri.parse(url);
    if (uri.host == 'youtu.be') return uri.pathSegments.first;
    if (uri.host.endsWith('youtube.com')) return uri.queryParameters['v'];
    return null;
  }

  @override
  Future<YtVideo> video(String videoId) async {
    if (videoError case final e?) throw e;
    return info;
  }

  @override
  Future<List<YtStream>> streams(String videoId) async {
    manifestCalls++;
    if (streamsError case final e?) throw e;
    return streamList;
  }

  @override
  Stream<List<int>> open(YtStream stream) {
    opened.add(stream.tag);
    if (live[stream.tag] case final c?) return c.stream;
    return _bytes(stream);
  }

  Stream<List<int>> _bytes(YtStream stream) async* {
    final total = stream.sizeBytes ?? 0;
    for (var sent = 0; sent < total; sent += chunk) {
      final n = sent + chunk > total ? total - sent : chunk;
      yield List<int>.filled(n, stream.tag & 0xff);
      if (failAfterFirstChunk[stream.tag] case final e?) throw e;
    }
  }

  @override
  void close() => closed = true;
}

/// An [FfmpegRunner] that records calls and writes the output file.
class FakeFfmpegRunner implements FfmpegRunner {
  final calls = <List<String>>[];

  /// Return code of the next sessions; 0 writes the output file.
  int returnCode = 0;
  String logs = 'ffmpeg log\nlast line';

  /// Positions reported through `onTime` before finishing.
  List<Duration> times = const [Duration(seconds: 5)];

  Duration? duration = const Duration(seconds: 10);
  Object? probeError;

  /// When set, sessions wait for this before finishing.
  Completer<void>? hold;
  int cancelCount = 0;

  @override
  Future<FfmpegTask> start(
    List<String> args, {
    void Function(Duration time)? onTime,
  }) async {
    calls.add(args);
    final task = _FakeTask(this);
    unawaited(task.run(args, onTime));
    return task;
  }

  @override
  Future<Duration?> probeDuration(String path) async {
    if (probeError case final e?) throw e;
    return duration;
  }
}

class _FakeTask implements FfmpegTask {
  _FakeTask(this._runner);

  final FakeFfmpegRunner _runner;
  final _done = Completer<FfmpegResult>();
  bool _cancelled = false;

  @override
  Future<FfmpegResult> get result => _done.future;

  Future<void> run(List<String> args, void Function(Duration)? onTime) async {
    await Future<void>.delayed(Duration.zero);
    for (final t in _runner.times) {
      onTime?.call(t);
    }
    if (_runner.hold case final h?) await h.future;
    if (_cancelled) return;
    final code = _runner.returnCode;
    if (code == 0) await writeFile(args.last, 'ffmpeg output');
    _done.complete(FfmpegResult(returnCode: code, logs: _runner.logs));
  }

  @override
  Future<void> cancel() async {
    _runner.cancelCount++;
    if (_cancelled || _done.isCompleted) return;
    _cancelled = true;
    _done.complete(const FfmpegResult(returnCode: 255));
  }
}

Future<void> writeFile(String path, String content) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}
