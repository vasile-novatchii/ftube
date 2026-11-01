import 'dart:async';

import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';

/// Outcome of one in-process ffmpeg run.
class FfmpegResult {
  const FfmpegResult({required this.returnCode, this.logs = ''});

  /// 0 on success, 255 when cancelled, otherwise ffmpeg's exit code.
  final int returnCode;

  /// ffmpeg's log output, for `ProcessFailed`.
  final String logs;

  bool get isSuccess => returnCode == ReturnCode.success;
  bool get isCancelled => returnCode == ReturnCode.cancel;
}

/// A running ffmpeg session.
abstract interface class FfmpegTask {
  Future<FfmpegResult> get result;

  /// Stops the session; [result] then completes with a cancel code.
  Future<void> cancel();
}

/// The parts of `ffmpeg_kit` that [AndroidMediaService] uses.
abstract interface class FfmpegRunner {
  /// Starts ffmpeg with [args]. [onTime] gets the position written so far.
  Future<FfmpegTask> start(
    List<String> args, {
    void Function(Duration time)? onTime,
  });

  /// Duration of the media at [path], or null when unknown.
  Future<Duration?> probeDuration(String path);

  /// Version of the bundled FFmpeg, or null when unknown.
  Future<String?> version();
}

/// [FfmpegRunner] backed by `ffmpeg_kit_flutter_new_audio`.
class KitFfmpegRunner implements FfmpegRunner {
  const KitFfmpegRunner();

  @override
  Future<FfmpegTask> start(
    List<String> args, {
    void Function(Duration time)? onTime,
  }) async {
    final done = Completer<FfmpegResult>();
    final session = await FFmpegKit.executeWithArgumentsAsync(
      args,
      (session) async {
        try {
          final code = await session.getReturnCode();
          final logs = await session.getAllLogsAsString() ?? '';
          done.complete(
            FfmpegResult(returnCode: code?.getValue() ?? -1, logs: logs),
          );
        } on Object catch (e, st) {
          done.completeError(e, st);
        }
      },
      null,
      onTime == null
          ? null
          : (s) => onTime(Duration(milliseconds: s.getTime())),
    );
    return _KitTask(session.getSessionId(), done.future);
  }

  @override
  Future<Duration?> probeDuration(String path) async {
    final session = await FFprobeKit.getMediaInformation(path);
    final seconds = double.tryParse(
      session.getMediaInformation()?.getDuration() ?? '',
    );
    if (seconds == null || seconds <= 0) return null;
    return Duration(microseconds: (seconds * 1e6).round());
  }

  @override
  Future<String?> version() async {
    try {
      return await FFmpegKitConfig.getFFmpegVersion();
    } on Object {
      return null;
    }
  }
}

class _KitTask implements FfmpegTask {
  _KitTask(this._sessionId, this.result);

  final int? _sessionId;

  @override
  final Future<FfmpegResult> result;

  @override
  Future<void> cancel() async {
    final id = _sessionId;
    if (id != null) await FFmpegKit.cancel(id);
  }
}
