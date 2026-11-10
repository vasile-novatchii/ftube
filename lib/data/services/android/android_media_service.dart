import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../domain/exceptions/ftube_exception.dart';
import '../../../domain/models/models.dart';
import '../desktop/yt_dlp_args.dart';
import '../desktop/yt_dlp_output.dart';
import '../ffmpeg_args.dart';
import '../media_service.dart';
import '../output_name.dart';
import '../progress_weights.dart';
import 'ffmpeg_kit_runner.dart';
import 'storage_permission_service.dart';
import 'yt_dlp_bridge.dart';

/// [MediaService] for Android: yt-dlp (through youtubedl-android) downloads
/// the streams and `ffmpeg_kit` muxes and converts them (spec-v0.3 D-31,
/// D-32).
class AndroidMediaService implements MediaService {
  AndroidMediaService({
    required this._ytDlp,
    required this._ffmpeg,
    required this.tempRoot,
    this._storage,
    this.idleTimeout = const Duration(seconds: 60),
  });

  final YtDlpBridge _ytDlp;
  final FfmpegRunner _ffmpeg;

  /// Checks access before writing and announces new files. Null in tests
  /// that do not cover storage.
  final StoragePermissionService? _storage;

  /// Parent of the per-job folders for partial files. Each job folder is
  /// deleted when the job ends, whatever the outcome.
  final Directory tempRoot;

  /// A yt-dlp run that prints nothing for this long is stopped (D-37).
  final Duration idleTimeout;

  final _jobs = <String, _Job>{};

  /// The yt-dlp update of this launch (D-36). Reset when it fails, so the
  /// next call tries again.
  Future<void>? _ready;
  var _infoCount = 0;

  /// Info runs in flight. The update waits for them, since it replaces the
  /// yt-dlp files they read (spec-v0.4-share D-75).
  final _infoRuns = <Future<void>>{};

  /// Doesn't wait for this launch's update when none has started: the
  /// installed yt-dlp answers at once, and the update starts after it. Only
  /// a failure with the old yt-dlp waits for the update and tries again
  /// (spec-v0.4-share D-75).
  @override
  Future<MediaInfo> fetchInfo(String url) async {
    final trimmed = url.trim();
    _checkUrl(trimmed);
    final ready = _ready;
    if (ready != null) {
      await ready;
      return _info(trimmed);
    }
    try {
      final info = await _info(trimmed);
      unawaited(_ensureReady());
      return info;
    } on Network {
      rethrow;
    } on FtubeException {
      await _ensureReady();
      return _info(trimmed);
    }
  }

  Future<MediaInfo> _info(String url) {
    final run = _runInfo(url);
    final done = run.then<void>((_) {}, onError: (Object _) {});
    _infoRuns.add(done);
    unawaited(done.whenComplete(() => _infoRuns.remove(done)));
    return run;
  }

  Future<MediaInfo> _runInfo(String url) async {
    final out = StringBuffer();
    final job = _Job('info-${_infoCount++}');
    final r = await _runYtDlp(job, YtDlpArgs.androidInfo(url), out.writeln);
    if (r.exitCode != 0) throw YtDlpOutput.mapError(r.exitCode, r.stderr);
    return YtDlpOutput.parseInfo(out.toString(), url: url);
  }

  @override
  Stream<JobProgress> download(DownloadRequest req) =>
      _stream(req.jobId, (job, emit) => _download(req, job, emit));

  @override
  Stream<JobProgress> convert(
    File src,
    AudioTarget target,
    File dst, {
    required String jobId,
  }) => _stream(jobId, (job, emit) => _convert(src, target, dst, job, emit));

  @override
  Future<void> cancel(String jobId) async {
    final job = _jobs[jobId];
    if (job == null) {
      await _deleteQuietly(Directory(p.join(tempRoot.path, jobId)));
      return;
    }
    job.paused = false;
    await _stop(job);
  }

  @override
  Future<void> pause(String jobId) async {
    final job = _jobs[jobId];
    if (job == null || job.cancelled) return;
    job.paused = true;
    await _stop(job);
  }

  Future<void> _stop(_Job job) async {
    job.cancelled = true;
    if (job.ytDlpRunning) await _ytDlp.cancel(job.id);
    await job.ffmpeg?.cancel();
  }

  /// Runs [body] when the stream is listened to and turns its outcome into
  /// stream events. Cancelling the subscription cancels the job.
  Stream<JobProgress> _stream(
    String jobId,
    Future<JobProgress> Function(_Job job, void Function(JobProgress) emit)
    body,
  ) {
    final controller = StreamController<JobProgress>();
    _Job? owned;
    controller
      ..onListen = () async {
        if (_jobs.containsKey(jobId)) {
          controller.addError(StateError('job $jobId is already running'));
          await controller.close();
          return;
        }
        final job = owned = _jobs[jobId] = _Job(jobId);
        try {
          final last = await body(job, controller.add);
          if (job.cancelled) throw const Cancelled();
          controller.add(last);
        } on Object catch (e, st) {
          controller.addError(
            job.paused
                ? const Paused()
                : job.cancelled
                ? const Cancelled()
                : e,
            st,
          );
        } finally {
          _jobs.remove(jobId);
          await controller.close();
        }
      }
      ..onCancel = () async {
        if (owned != null && identical(_jobs[jobId], owned)) {
          await cancel(jobId);
        }
      };
    return controller.stream;
  }

  Future<JobProgress> _download(
    DownloadRequest req,
    _Job job,
    void Function(JobProgress) emit,
  ) async {
    _checkUrl(req.url.trim());
    await _storage?.ensureGranted();
    await _ensureReady();
    _checkCancelled(job);

    final temp = Directory(p.join(tempRoot.path, req.jobId));
    try {
      await temp.create(recursive: true);
      final audioOnly = req.preset.isAudioOnly;
      String? title;
      final parts = <_Part>[];

      void onLine(String line) {
        switch (YtDlpOutput.parseLine(line)) {
          case YtDlpTitleLine(title: final t):
            title = t;
          case YtDlpDestinationLine(:final path):
            parts.add(
              _Part(p.isAbsolute(path) ? path : p.join(temp.path, path)),
            );
          case final YtDlpDownloadLine l:
            if (parts.isNotEmpty) parts.last.isAudio ??= l.isAudio;
            final phase = l.isAudio
                ? JobPhase.downloadingAudio
                : JobPhase.downloadingVideo;
            final f = l.fraction;
            emit(
              JobProgress(
                jobId: req.jobId,
                phase: phase,
                fraction: f == null
                    ? null
                    : ProgressWeights.overall(phase, f, audioOnly: audioOnly),
                downloadedBytes: l.downloadedBytes,
                totalBytes: l.totalBytes,
                speedBps: l.speedBps,
                eta: l.eta,
              ),
            );
          case _:
        }
      }

      final r = await _runYtDlp(
        job,
        YtDlpArgs.androidDownload(req, tempDir: temp.path),
        onLine,
      );
      _checkCancelled(job);
      if (r.exitCode != 0) throw YtDlpOutput.mapError(r.exitCode, r.stderr);

      final files = _downloadedParts(parts, temp);
      if (files.isEmpty) {
        throw ProcessFailed.fromStderr(0, 'yt-dlp wrote no file\n${r.stderr}');
      }
      final File result;
      if (files.length >= 2) {
        // The selector asks for video first, then audio.
        final video = files.firstWhere(
          (f) => f.isAudio != true,
          orElse: () => files[0],
        );
        final audio = files.firstWhere(
          (f) => !identical(f, video),
          orElse: () => files[1],
        );
        emit(_phaseStart(req.jobId, JobPhase.merging, audioOnly: false));
        final ext = muxExtension(
          p.extension(video.path),
          p.extension(audio.path),
        );
        result = File(p.join(temp.path, 'out$ext'));
        await _runFfmpeg(
          job,
          FfmpegArgs.mux(video.path, audio.path, result.path),
        );
      } else if (req.preset.audioTarget case final target?) {
        final src = files.single.path;
        emit(_phaseStart(req.jobId, JobPhase.converting, audioOnly: true));
        Duration? duration;
        try {
          duration = await _ffmpeg.probeDuration(src);
        } on Object {
          // Progress stays at the phase start without a duration.
        }
        result = File(p.join(temp.path, 'out.${target.extension}'));
        await _runFfmpeg(
          job,
          FfmpegArgs.convert(src, target, result.path, pipeProgress: false),
          onTime: _onConvertTime(
            req.jobId,
            duration,
            emit,
            conversionOnly: false,
          ),
        );
      } else {
        result = File(files.single.path);
      }

      _checkCancelled(job);
      await req.outDir.create(recursive: true);
      final dst = await OutputName.place(
        result,
        req.outDir,
        OutputName.fromTitle(title ?? ''),
      );
      await _storage?.scanFile(dst.path);
      return JobProgress(
        jobId: req.jobId,
        phase: JobPhase.finished,
        fraction: 1,
        outputPath: dst.path,
      );
    } finally {
      // A paused job keeps its partial files for the resume (spec-v0.4 D-68).
      if (!job.paused) await _deleteQuietly(temp);
    }
  }

  /// The parts yt-dlp announced that exist, else every finished file in
  /// [temp] (yt-dlp may skip the Destination line).
  static List<_Part> _downloadedParts(List<_Part> announced, Directory temp) {
    final existing = [
      for (final part in announced)
        if (File(part.path).existsSync()) part,
    ];
    if (existing.isNotEmpty) return existing;
    const audioExts = {'.m4a', '.opus', '.mp3', '.aac', '.ogg'};
    return [
      for (final f in temp.listSync().whereType<File>())
        if (!f.path.endsWith('.part') && !f.path.endsWith('.ytdl'))
          _Part(f.path)
            ..isAudio = audioExts.contains(p.extension(f.path).toLowerCase())
                ? true
                : null,
    ];
  }

  /// The container yt-dlp's merger would pick (D-35): `.mp4` for MP4 video
  /// with M4A/MP4 audio, `.webm` for WebM with WebM, else `.mkv`.
  static String muxExtension(String videoExt, String audioExt) {
    final v = videoExt.toLowerCase();
    final a = audioExt.toLowerCase();
    if (v == '.mp4' && (a == '.m4a' || a == '.mp4')) return '.mp4';
    if (v == '.webm' && a == '.webm') return '.webm';
    return '.mkv';
  }

  /// Updates yt-dlp once per launch before its first use (D-36). A failed
  /// update keeps the installed version and is tried again next time.
  Future<void> _ensureReady() => _ready ??= _update();

  Future<void> _update() async {
    await Future.wait(_infoRuns.toList());
    try {
      await _ytDlp.update();
    } on Object {
      _ready = null;
    }
  }

  /// Runs yt-dlp for [job], stopping it after [idleTimeout] without output.
  Future<YtDlpResult> _runYtDlp(
    _Job job,
    List<String> args,
    void Function(String line) onLine,
  ) async {
    var stalled = false;
    Timer? idle;
    void arm() {
      idle?.cancel();
      idle = Timer(idleTimeout, () {
        stalled = true;
        unawaited(_ytDlp.cancel(job.id));
      });
    }

    job.ytDlpRunning = true;
    arm();
    try {
      final r = await _ytDlp.run(
        job.id,
        args,
        onLine: (line) {
          arm();
          onLine(line);
        },
      );
      if (job.cancelled) throw const Cancelled();
      if (stalled) {
        throw Network('yt-dlp printed nothing for ${idleTimeout.inSeconds}s');
      }
      if (r.cancelled) throw const Cancelled();
      return r;
    } finally {
      idle?.cancel();
      job.ytDlpRunning = false;
    }
  }

  Future<JobProgress> _convert(
    File src,
    AudioTarget target,
    File dst,
    _Job job,
    void Function(JobProgress) emit,
  ) async {
    await _storage?.ensureGranted();
    final jobId = job.id;
    final dstExisted = dst.existsSync();
    var done = false;
    try {
      Duration? duration;
      try {
        duration = await _ffmpeg.probeDuration(src.path);
      } on Object {
        // Progress stays indeterminate without a duration.
      }
      emit(JobProgress(jobId: jobId, phase: JobPhase.converting, fraction: 0));
      await _runFfmpeg(
        job,
        FfmpegArgs.convert(src.path, target, dst.path, pipeProgress: false),
        onTime: _onConvertTime(jobId, duration, emit, conversionOnly: true),
      );
      done = true;
      await _storage?.scanFile(dst.path);
      return JobProgress(
        jobId: jobId,
        phase: JobPhase.finished,
        fraction: 1,
        outputPath: dst.path,
      );
    } finally {
      // Remove a partial output, but never a file that was there before.
      if (!done && !dstExisted) await _deleteQuietly(dst);
    }
  }

  Future<void> _runFfmpeg(
    _Job job,
    List<String> args, {
    void Function(Duration)? onTime,
  }) async {
    _checkCancelled(job);
    final task = await _ffmpeg.start(args, onTime: onTime);
    job.ffmpeg = task;
    try {
      if (job.cancelled) await task.cancel();
      final r = await task.result;
      if (job.cancelled || r.isCancelled) throw const Cancelled();
      if (!r.isSuccess) throw ProcessFailed.fromStderr(r.returnCode, r.logs);
    } finally {
      job.ffmpeg = null;
    }
  }

  void Function(Duration) _onConvertTime(
    String jobId,
    Duration? duration,
    void Function(JobProgress) emit, {
    required bool conversionOnly,
  }) => (t) {
    if (duration == null || duration <= Duration.zero) return;
    emit(
      JobProgress(
        jobId: jobId,
        phase: JobPhase.converting,
        fraction: ProgressWeights.overall(
          JobPhase.converting,
          t.inMicroseconds / duration.inMicroseconds,
          audioOnly: true,
          conversionOnly: conversionOnly,
        ),
      ),
    );
  };

  static JobProgress _phaseStart(
    String jobId,
    JobPhase phase, {
    required bool audioOnly,
  }) => JobProgress(
    jobId: jobId,
    phase: phase,
    fraction: ProgressWeights.overall(phase, 0, audioOnly: audioOnly),
  );

  static void _checkUrl(String url) {
    final uri = Uri.tryParse(url);
    final ok =
        uri != null &&
        (uri.isScheme('http') || uri.isScheme('https')) &&
        uri.host.isNotEmpty;
    if (!ok) throw InvalidUrl(url);
  }

  static void _checkCancelled(_Job job) {
    if (job.cancelled) throw const Cancelled();
  }

  static Future<void> _deleteQuietly(FileSystemEntity entity) async {
    try {
      if (entity.existsSync()) await entity.delete(recursive: true);
    } on FileSystemException {
      // Best effort: a leftover temp file is not worth failing the job.
    }
  }
}

class _Job {
  _Job(this.id);

  final String id;
  bool cancelled = false;

  /// Stopped by [MediaService.pause]; implies [cancelled].
  bool paused = false;

  /// yt-dlp is running for this job.
  bool ytDlpRunning = false;

  /// The ffmpeg session in progress, if any.
  FfmpegTask? ffmpeg;
}

/// One file yt-dlp wrote.
class _Part {
  _Part(this.path);

  final String path;

  /// From the first progress line after the file started; null if none.
  bool? isAudio;
}
