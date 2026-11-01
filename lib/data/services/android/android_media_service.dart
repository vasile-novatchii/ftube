import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../../domain/exceptions/ftube_exception.dart';
import '../../../domain/models/models.dart';
import '../ffmpeg_args.dart';
import '../media_service.dart';
import '../progress_weights.dart';
import 'ffmpeg_kit_runner.dart';
import 'storage_permission_service.dart';
import 'stream_picker.dart';
import 'youtube_source.dart';

/// [MediaService] for Android: `youtube_explode_dart` downloads the streams
/// and `ffmpeg_kit` muxes and converts them (spec D-5). YouTube only.
class AndroidMediaService implements MediaService {
  AndroidMediaService({
    required this._source,
    required this._ffmpeg,
    required this.tempRoot,
    this._storage,
    this.progressInterval = const Duration(milliseconds: 250),
  });

  final YoutubeSource _source;
  final FfmpegRunner _ffmpeg;

  /// Checks access before writing and announces new files. Null in tests
  /// that do not cover storage.
  final StoragePermissionService? _storage;

  /// Parent of the per-job folders for partial files. Each job folder is
  /// deleted when the job ends, whatever the outcome.
  final Directory tempRoot;

  /// Minimum time between two byte-progress updates of one stream.
  final Duration progressInterval;

  final _jobs = <String, _Job>{};

  @override
  Future<MediaInfo> fetchInfo(String url) async {
    final id = _videoId(url);
    final YtVideo video;
    final List<YtStream> streams;
    try {
      (video, streams) = await (_source.video(id), _source.streams(id)).wait;
    } on ParallelWaitError<
      (YtVideo?, List<YtStream>?),
      (AsyncError?, AsyncError?)
    > catch (e) {
      final err = e.errors.$1 ?? e.errors.$2!;
      Error.throwWithStackTrace(err.error, err.stackTrace);
    }
    return MediaInfo(
      url: url.trim(),
      title: video.title,
      uploader: video.author,
      duration: video.duration,
      thumbnailUrl: video.thumbnailUrl,
      formats: StreamPicker.formats(streams),
    );
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
    job.stopTransfer?.call();
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
          controller.addError(job.cancelled ? const Cancelled() : e, st);
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
    final id = _videoId(req.url);
    await _storage?.ensureGranted();
    final streams = await _source.streams(id);
    final selection = StreamPicker.pick(
      streams,
      req.preset,
      formatId: req.formatId,
    );
    final video = await _source.video(id);
    _checkCancelled(job);

    final temp = Directory(p.join(tempRoot.path, req.jobId));
    try {
      await temp.create(recursive: true);
      final audioOnly = selection.video == null;
      File? videoFile;
      File? audioFile;

      if (selection.video case final v?) {
        videoFile = File(p.join(temp.path, 'video.${v.extension}'));
        await _transfer(
          job,
          v,
          videoFile,
          (got, total, speed, eta) => emit(
            _bytesProgress(
              req.jobId,
              JobPhase.downloadingVideo,
              got,
              total,
              speed,
              eta,
              audioOnly: false,
            ),
          ),
        );
      }

      if (selection.audio case final picked?) {
        // A second download from the same manifest may be refused, so the
        // audio stream comes from a fresh one when a video came first.
        var a = picked;
        if (videoFile != null) {
          final fresh = await _source.streams(id);
          a = fresh.firstWhere((s) => s.tag == a.tag, orElse: () => a);
        }
        audioFile = File(p.join(temp.path, 'audio.${a.extension}'));
        await _transfer(
          job,
          a,
          audioFile,
          (got, total, speed, eta) => emit(
            _bytesProgress(
              req.jobId,
              JobPhase.downloadingAudio,
              got,
              total,
              speed,
              eta,
              audioOnly: audioOnly,
            ),
          ),
        );
      }

      final File result;
      if (videoFile != null && audioFile != null) {
        emit(_phaseStart(req.jobId, JobPhase.merging, audioOnly: false));
        result = File(p.join(temp.path, 'out.${selection.video!.container}'));
        await _runFfmpeg(
          job,
          FfmpegArgs.mux(videoFile.path, audioFile.path, result.path),
        );
      } else if (req.preset.audioTarget case final target?) {
        emit(_phaseStart(req.jobId, JobPhase.converting, audioOnly: true));
        result = File(p.join(temp.path, 'out.${target.extension}'));
        await _runFfmpeg(
          job,
          FfmpegArgs.convert(
            audioFile!.path,
            target,
            result.path,
            pipeProgress: false,
          ),
          onTime: _onConvertTime(
            req.jobId,
            video.duration,
            emit,
            conversionOnly: false,
          ),
        );
      } else {
        result = (videoFile ?? audioFile)!;
      }

      _checkCancelled(job);
      await req.outDir.create(recursive: true);
      final ext = p.extension(result.path);
      final dst = _freePath(req.outDir, safeFileName(video.title), ext);
      await _move(result, dst);
      await _storage?.scanFile(dst.path);
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

  /// Writes [stream]'s bytes to [dst], reporting at most every
  /// [progressInterval] and once at the end.
  Future<void> _transfer(
    _Job job,
    YtStream stream,
    File dst,
    void Function(int got, int? total, double? speed, Duration? eta) onBytes,
  ) async {
    _checkCancelled(job);
    final total = stream.sizeBytes;
    final clock = Stopwatch()..start();
    var got = 0;
    var lastReport = Duration.zero;

    void report() {
      final elapsed = clock.elapsed;
      final seconds = elapsed.inMicroseconds / 1e6;
      final speed = seconds > 0 ? got / seconds : null;
      Duration? eta;
      if (speed != null && speed > 0 && total != null && total >= got) {
        eta = Duration(seconds: ((total - got) / speed).round());
      }
      onBytes(got, total, speed, eta);
      lastReport = elapsed;
    }

    final file = await dst.open(mode: FileMode.writeOnly);
    final finished = Completer<void>();
    late final StreamSubscription<List<int>> sub;
    try {
      sub = _source
          .open(stream)
          .listen(
            (chunk) async {
              // Pause while writing, so a fast network cannot fill memory.
              sub.pause();
              try {
                await file.writeFrom(
                  chunk is Uint8List ? chunk : Uint8List.fromList(chunk),
                );
                got += chunk.length;
                if (clock.elapsed - lastReport >= progressInterval) report();
              } on Object catch (e, st) {
                if (!finished.isCompleted) finished.completeError(e, st);
                await sub.cancel();
                return;
              }
              sub.resume();
            },
            onError: (Object e, StackTrace st) {
              if (!finished.isCompleted) finished.completeError(e, st);
            },
            onDone: () {
              if (!finished.isCompleted) finished.complete();
            },
            cancelOnError: true,
          );
      job.stopTransfer = () {
        unawaited(sub.cancel());
        if (!finished.isCompleted) finished.completeError(const Cancelled());
      };
      await finished.future;
      report();
    } finally {
      job.stopTransfer = null;
      await file.close();
    }
    _checkCancelled(job);
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

  static JobProgress _bytesProgress(
    String jobId,
    JobPhase phase,
    int got,
    int? total,
    double? speed,
    Duration? eta, {
    required bool audioOnly,
  }) => JobProgress(
    jobId: jobId,
    phase: phase,
    fraction: total == null || total <= 0
        ? null
        : ProgressWeights.overall(phase, got / total, audioOnly: audioOnly),
    downloadedBytes: got,
    totalBytes: total,
    speedBps: speed,
    eta: eta,
  );

  static JobProgress _phaseStart(
    String jobId,
    JobPhase phase, {
    required bool audioOnly,
  }) => JobProgress(
    jobId: jobId,
    phase: phase,
    fraction: ProgressWeights.overall(phase, 0, audioOnly: audioOnly),
  );

  String _videoId(String url) {
    final uri = Uri.tryParse(url.trim());
    final ok =
        uri != null &&
        (uri.isScheme('http') || uri.isScheme('https')) &&
        uri.host.isNotEmpty;
    if (!ok) throw InvalidUrl(url);
    return _source.parseVideoId(url.trim()) ??
        (throw Unsupported('only YouTube videos are supported: $url'));
  }

  static void _checkCancelled(_Job job) {
    if (job.cancelled) throw const Cancelled();
  }

  /// [title] made safe for any file system, like yt-dlp's
  /// `--restrict-filenames`: ASCII letters, digits, `.`, `_` and `-`.
  static String safeFileName(String title) {
    final cleaned = title
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp('_{2,}'), '_')
        .replaceAll(RegExp(r'^[._-]+|[._-]+$'), '');
    final short = cleaned.length > 150 ? cleaned.substring(0, 150) : cleaned;
    return short.isEmpty ? 'video' : short;
  }

  /// `<dir>/<name><ext>`, or `<name>_2<ext>`, `<name>_3<ext>`... when taken.
  static File _freePath(Directory dir, String name, String ext) {
    var file = File(p.join(dir.path, '$name$ext'));
    for (var n = 2; file.existsSync(); n++) {
      file = File(p.join(dir.path, '${name}_$n$ext'));
    }
    return file;
  }

  /// Renames [src] to [dst], copying when they are on different volumes
  /// (app cache to shared storage).
  static Future<void> _move(File src, File dst) async {
    try {
      await src.rename(dst.path);
    } on FileSystemException {
      await src.copy(dst.path);
      await _deleteQuietly(src);
    }
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

  /// Stops the byte transfer in progress, if any.
  void Function()? stopTransfer;

  /// The ffmpeg session in progress, if any.
  FfmpegTask? ffmpeg;
}
