import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../domain/exceptions/ftube_exception.dart';
import '../../../domain/models/models.dart';
import '../binary_service.dart';
import '../ffmpeg_args.dart';
import '../media_service.dart';
import '../output_name.dart';
import '../process_runner.dart';
import '../progress_weights.dart';
import 'yt_dlp_args.dart';
import 'yt_dlp_output.dart';

/// [MediaService] that runs the bundled yt-dlp, ffmpeg and ffprobe.
class DesktopMediaService implements MediaService {
  DesktopMediaService({
    required this._binaries,
    required this._runner,
    required this.tempRoot,
  });

  final BinaryService _binaries;
  final ProcessRunner _runner;

  /// Parent of the per-job folders for partial files. Each job folder is
  /// deleted when the job ends, whatever the outcome.
  final Directory tempRoot;

  final _jobs = <String, _Job>{};

  @override
  Future<MediaInfo> fetchInfo(String url) async {
    _checkUrl(url);
    final tools = await _tools();
    final ProcessOutput out;
    try {
      out = await _runner.run(
        tools.ytDlp,
        YtDlpArgs.info(url, ffmpegDir: tools.ffmpegDir, denoPath: tools.deno),
      );
    } on ProcessException {
      throw BinaryMissing(Binary.ytDlp.label);
    }
    if (out.exitCode != 0) throw YtDlpOutput.mapError(out.exitCode, out.stderr);
    return YtDlpOutput.parseInfo(out.stdout, url: url);
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
    if (job == null) return;
    job.cancelled = true;
    await job.process?.kill();
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
          controller.addError(job.cancelled ? const Cancelled() : e, st);
        } finally {
          _jobs.remove(jobId);
          await controller.close();
        }
      }
      // Only the stream that started the job may cancel it; a rejected
      // duplicate must not touch the running one.
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
    _checkUrl(req.url);
    final tools = await _tools();
    final temp = Directory(p.join(tempRoot.path, req.jobId));
    try {
      await temp.create(recursive: true);
      final audioOnly = req.preset.isAudioOnly;
      String? outputPath;
      String? title;

      void onLine(String line) {
        switch (YtDlpOutput.parseLine(line)) {
          case final YtDlpDownloadLine l:
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
          case YtDlpPostprocessLine(started: true, :final phase?):
            emit(
              JobProgress(
                jobId: req.jobId,
                phase: phase,
                fraction: ProgressWeights.overall(
                  phase,
                  0,
                  audioOnly: audioOnly,
                ),
              ),
            );
          case YtDlpFileLine(:final path):
            outputPath = path;
          case YtDlpTitleLine(title: final t):
            title = t;
          case _:
        }
      }

      final (code, stderr) = await _run(
        job,
        tools.ytDlp,
        Binary.ytDlp,
        YtDlpArgs.download(
          req,
          ffmpegDir: tools.ffmpegDir,
          tempDir: temp.path,
          denoPath: tools.deno,
        ),
        onStdout: onLine,
        // yt-dlp writes postprocessor progress to stderr.
        onStderr: onLine,
      );
      if (job.cancelled) throw const Cancelled();
      if (code != 0) throw YtDlpOutput.mapError(code, stderr);
      final result = _result(outputPath, temp);
      await req.outDir.create(recursive: true);
      final dst = await OutputName.place(
        result,
        req.outDir,
        OutputName.fromTitle(title ?? ''),
      );
      return JobProgress(
        jobId: req.jobId,
        phase: JobPhase.finished,
        fraction: 1,
        outputPath: dst.path,
      );
    } finally {
      await _deleteQuietly(temp);
    }
  }

  Future<JobProgress> _convert(
    File src,
    AudioTarget target,
    File dst,
    _Job job,
    void Function(JobProgress) emit,
  ) async {
    final ffmpeg = (await _binaries.locate(Binary.ffmpeg)).path;
    final ffprobe = (await _binaries.locate(Binary.ffprobe)).path;
    final jobId = job.id;
    final dstExisted = dst.existsSync();
    var done = false;
    try {
      Duration? duration;
      try {
        final probe = await _runner.run(
          ffprobe,
          FfmpegArgs.probeDuration(src.path),
        );
        if (probe.exitCode == 0) {
          duration = FfmpegArgs.parseDuration(probe.stdout);
        }
      } on ProcessException {
        throw BinaryMissing(Binary.ffprobe.label);
      }
      emit(JobProgress(jobId: jobId, phase: JobPhase.converting, fraction: 0));

      void onLine(String line) {
        final t = FfmpegArgs.parseOutTime(line);
        final total = duration;
        if (t == null || total == null) return;
        emit(
          JobProgress(
            jobId: jobId,
            phase: JobPhase.converting,
            fraction: ProgressWeights.overall(
              JobPhase.converting,
              t.inMicroseconds / total.inMicroseconds,
              audioOnly: true,
              conversionOnly: true,
            ),
          ),
        );
      }

      final (code, stderr) = await _run(
        job,
        ffmpeg,
        Binary.ffmpeg,
        FfmpegArgs.convert(src.path, target, dst.path),
        onStdout: onLine,
      );
      if (job.cancelled) throw const Cancelled();
      if (code != 0) throw ProcessFailed.fromStderr(code, stderr);
      done = true;
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

  /// Starts [executable], feeds its output lines to the callbacks and
  /// returns the exit code with the last stderr lines.
  Future<(int, String)> _run(
    _Job job,
    String executable,
    Binary binary,
    List<String> args, {
    required void Function(String) onStdout,
    void Function(String)? onStderr,
  }) async {
    if (job.cancelled) throw const Cancelled();
    final RunningProcess process;
    try {
      process = await _runner.start(executable, args);
    } on ProcessException {
      throw BinaryMissing(binary.label);
    }
    job.process = process;
    if (job.cancelled) await process.kill();
    final tail = ListQueue<String>();
    final out = process.stdoutLines.forEach(onStdout);
    final err = process.stderrLines.forEach((line) {
      tail.add(line);
      if (tail.length > 50) tail.removeFirst();
      onStderr?.call(line);
    });
    final code = await process.exitCode;
    await Future.wait([out, err]);
    return (code, tail.join('\n'));
  }

  Future<_Tools> _tools() async {
    final ytDlp = await _binaries.locate(Binary.ytDlp);
    final ffmpeg = await _binaries.locate(Binary.ffmpeg);
    String? deno;
    try {
      deno = (await _binaries.locate(Binary.deno)).path;
    } on BinaryMissing {
      // Optional: YouTube still works without it, with fewer formats.
    }
    return (ytDlp: ytDlp.path, ffmpegDir: ffmpeg.parent.path, deno: deno);
  }

  /// The finished file: the path yt-dlp printed, else the only finished
  /// `media.*` in [temp].
  static File _result(String? printed, Directory temp) {
    if (printed != null && File(printed).existsSync()) return File(printed);
    final files = [
      for (final f in temp.listSync().whereType<File>())
        if (p.basename(f.path).startsWith('media.') &&
            !f.path.endsWith('.part') &&
            !f.path.endsWith('.ytdl'))
          f,
    ];
    if (files.length == 1) return files.single;
    throw Unexpected('yt-dlp left ${files.length} files and no final path');
  }

  static void _checkUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    final ok =
        uri != null &&
        (uri.isScheme('http') || uri.isScheme('https')) &&
        uri.host.isNotEmpty;
    if (!ok) throw InvalidUrl(url);
  }

  static Future<void> _deleteQuietly(FileSystemEntity entity) async {
    try {
      if (entity.existsSync()) await entity.delete(recursive: true);
    } on FileSystemException {
      // Best effort: a leftover temp file is not worth failing the job.
    }
  }
}

typedef _Tools = ({String ytDlp, String ffmpegDir, String? deno});

class _Job {
  _Job(this.id);

  final String id;
  bool cancelled = false;
  RunningProcess? process;
}
