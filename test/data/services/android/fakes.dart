import 'dart:async';
import 'dart:io';

import 'package:ftube/data/services/android/ffmpeg_kit_runner.dart';
import 'package:ftube/data/services/android/yt_dlp_bridge.dart';
import 'package:path/path.dart' as p;

/// One file the fake yt-dlp writes: `media.f<id>.<ext>`.
class FakePart {
  const FakePart(this.id, this.ext, {this.audio = false, this.size = 1000});

  final String id;
  final String ext;
  final bool audio;
  final int size;
}

/// A [YtDlpBridge] that acts like yt-dlp without ffmpeg (spec-v0.3 D-32):
/// it prints the title, then for each of [parts] a Destination line,
/// writes the file and prints two `FTUBE|` progress lines.
class FakeYtDlpBridge implements YtDlpBridge {
  FakeYtDlpBridge({
    this.title = 'Big Buck Bunny: 60fps 4K!',
    this.parts = const [
      FakePart('137', 'mp4', size: 2000),
      FakePart('140', 'm4a', audio: true, size: 500),
    ],
  });

  String title;
  List<FakePart> parts;

  /// stdout of `-J` runs.
  String infoJson =
      '{"title": "Big Buck Bunny", "uploader": "Blender", '
      '"duration": 10, "thumbnail": "https://img.test/t.jpg", "formats": ['
      '{"format_id": "18", "ext": "mp4", "vcodec": "avc1", "acodec": "mp4a", '
      '"resolution": "640x360", "height": 360}, '
      '{"format_id": "140", "ext": "m4a", "vcodec": "none", "acodec": "mp4a", '
      '"resolution": "audio only"}]}';

  int exitCode = 0;
  String stderr = '';

  /// Print Destination lines; yt-dlp may leave them out.
  bool announce = true;

  /// When set, runs wait for this after printing the first part's lines.
  Completer<void>? hold;

  /// Runs print nothing and wait until cancelled.
  bool silent = false;

  Object? updateError;
  String? installed = '2026.10.26';

  int updateCalls = 0;
  final runs = <List<String>>[];
  final cancelled = <String>[];
  final _cancels = <String, Completer<void>>{};

  @override
  Future<String?> version() async => installed;

  @override
  Future<String?> update() async {
    updateCalls++;
    if (updateError case final e?) throw e;
    return installed;
  }

  @override
  Future<YtDlpResult> run(
    String id,
    List<String> args, {
    void Function(String line)? onLine,
  }) async {
    runs.add(args);
    final cancel = _cancels[id] = Completer<void>();
    final emit = onLine ?? (_) {};
    try {
      await Future<void>.delayed(Duration.zero);
      if (silent) {
        await cancel.future;
        return const YtDlpResult(exitCode: -1, cancelled: true);
      }
      if (args.contains('-J')) {
        emit(infoJson);
        return YtDlpResult(exitCode: exitCode, stderr: stderr);
      }
      final dir = args[args.indexOf('-P') + 1];
      emit('FTUBE_TITLE|$title');
      for (final (i, part) in parts.indexed) {
        final path = p.join(dir, 'media.f${part.id}.${part.ext}');
        if (announce) emit('[download] Destination: $path');
        final vcodec = part.audio ? 'none' : 'avc1';
        emit(
          'FTUBE|downloading|${part.size ~/ 2}|${part.size}|NA|1000|1|$vcodec',
        );
        if (i == 0 && hold != null) {
          await Future.any([hold!.future, cancel.future]);
          if (cancel.isCompleted) {
            return const YtDlpResult(exitCode: -1, cancelled: true);
          }
        }
        await File(path).writeAsString('x' * part.size);
        emit('FTUBE|finished|${part.size}|${part.size}|NA|NA|NA|$vcodec');
      }
      return YtDlpResult(exitCode: exitCode, stderr: stderr);
    } finally {
      _cancels.remove(id);
    }
  }

  @override
  Future<void> cancel(String id) async {
    cancelled.add(id);
    final c = _cancels[id];
    if (c != null && !c.isCompleted) c.complete();
  }
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

  String? ffmpegVersion = '7.1';

  @override
  Future<String?> version() async => ffmpegVersion;
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
