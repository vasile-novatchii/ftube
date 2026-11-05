import 'dart:async';

import 'package:flutter/services.dart';

import '../../../domain/exceptions/ftube_exception.dart';

/// Outcome of one yt-dlp run on Android.
class YtDlpResult {
  const YtDlpResult({
    required this.exitCode,
    this.stderr = '',
    this.cancelled = false,
  });

  final int exitCode;
  final String stderr;

  /// The run was stopped by [YtDlpBridge.cancel].
  final bool cancelled;
}

/// yt-dlp on Android, run by youtubedl-android in the Kotlin
/// `YtDlpChannel` (spec-v0.3 D-33).
abstract interface class YtDlpBridge {
  /// Installed yt-dlp version, or null when unknown.
  Future<String?> version();

  /// Updates yt-dlp to the latest stable release and returns its version.
  Future<String?> update();

  /// Runs yt-dlp with [args] (the URL last). [onLine] gets every stdout
  /// line. [id] names the run for [cancel] and must be unique while it runs.
  Future<YtDlpResult> run(
    String id,
    List<String> args, {
    void Function(String line)? onLine,
  });

  /// Stops run [id]. Its [run] then completes with `cancelled`.
  Future<void> cancel(String id);
}

/// [YtDlpBridge] over the `io.github.infvyr.ftube/ytdlp` method channel.
class ChannelYtDlpBridge implements YtDlpBridge {
  ChannelYtDlpBridge({
    this._channel = const MethodChannel('io.github.infvyr.ftube/ytdlp'),
  }) {
    _channel.setMethodCallHandler(_onCall);
  }

  final MethodChannel _channel;
  final _listeners = <String, void Function(String)>{};

  Future<Object?> _onCall(MethodCall call) async {
    if (call.method != 'line') return null;
    final args = call.arguments as Map<Object?, Object?>;
    final id = args['id'] as String?;
    final line = args['line'] as String?;
    if (id != null && line != null) _listeners[id]?.call(line);
    return null;
  }

  @override
  Future<String?> version() => _invoke<String>('version');

  @override
  Future<String?> update() => _invoke<String>('update');

  @override
  Future<YtDlpResult> run(
    String id,
    List<String> args, {
    void Function(String line)? onLine,
  }) async {
    if (onLine != null) _listeners[id] = onLine;
    try {
      final r = await _invoke<Map<Object?, Object?>>('run', {
        'id': id,
        'args': args,
      });
      return YtDlpResult(
        exitCode: (r?['exitCode'] as int?) ?? -1,
        stderr: (r?['stderr'] as String?) ?? '',
        cancelled: (r?['cancelled'] as bool?) ?? false,
      );
    } finally {
      _listeners.remove(id);
    }
  }

  @override
  Future<void> cancel(String id) => _invoke<bool>('cancel', {'id': id});

  Future<T?> _invoke<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      // Init, update or process start failed in Kotlin.
      throw Unexpected('yt-dlp $method: ${e.message ?? e.code}');
    }
  }
}
