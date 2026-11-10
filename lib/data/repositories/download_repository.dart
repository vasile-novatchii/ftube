import 'dart:async';
import 'dart:io';

import '../../domain/exceptions/ftube_exception.dart';
import '../../domain/models/models.dart';
import '../services/media_service.dart';

/// Source of truth for the in-memory download queue (spec section 3, job
/// lifecycle).
///
/// Up to [maxConcurrent] jobs run at once, in the order they were queued.
/// A cancelled job shows as cancelled at once; its slot is freed when the
/// media service has stopped it, and a retry waits for that too.
class DownloadRepository {
  DownloadRepository(
    this._media, {
    int maxConcurrent = 2,
    DateTime Function()? now,
  }) : _maxConcurrent = _clamp(maxConcurrent),
       _now = now ?? DateTime.now;

  final MediaService _media;
  final DateTime Function() _now;
  int _maxConcurrent;
  var _seq = 0;
  var _disposed = false;

  final _jobs = <String, DownloadJob>{};

  /// Media service runs that have not ended yet, by job id.
  final _runs = <String, StreamSubscription<JobProgress>>{};

  final _changes = StreamController<List<DownloadJob>>.broadcast(sync: true);

  /// All jobs in the order they were queued.
  List<DownloadJob> get jobs => List.unmodifiable(_jobs.values);

  /// Emits [jobs] after every change.
  Stream<List<DownloadJob>> get changes => _changes.stream;

  /// Queued and running jobs, for the queue badge.
  int get activeCount => _jobs.values.where((j) => j.status.isActive).length;

  int get maxConcurrent => _maxConcurrent;

  /// Changes the limit (clamped to 1..3). Lowering it lets running jobs
  /// finish; raising it starts queued jobs right away.
  set maxConcurrent(int value) {
    _maxConcurrent = _clamp(value);
    _pump();
  }

  DownloadJob? job(String id) => _jobs[id];

  /// Adds a download to the end of the queue and starts it when a slot is
  /// free.
  DownloadJob enqueue({
    required String url,
    required String title,
    required QualityPreset preset,
    required Directory outDir,
    String? formatId,
  }) {
    _checkOpen();
    final now = _now();
    final job = DownloadJob(
      request: DownloadRequest(
        jobId: 'job-${now.microsecondsSinceEpoch}-${_seq++}',
        url: url,
        preset: preset,
        outDir: outDir,
        formatId: formatId,
      ),
      title: title,
      createdAt: now,
    );
    _jobs[job.id] = job;
    _emit();
    _pump();
    return _jobs[job.id]!;
  }

  /// Cancels a queued or running job. Other jobs are left as they are.
  Future<void> cancel(String id) async {
    final job = _jobs[id];
    if (job == null || !job.status.canCancel) return;
    final wasRunning = job.status == JobStatus.running;
    final wasPaused = job.status == JobStatus.paused;
    // A paused job's partial files are deleted too, also once resumed.
    _set(job.copyWith(status: JobStatus.cancelled, error: const Cancelled()));
    if (wasRunning || wasPaused || job.progress != null) {
      await _media.cancel(id);
    }
  }

  /// Stops a queued or running job and keeps its partial files, so
  /// [resume] continues it (spec-v0.4 D-69).
  Future<void> pause(String id) async {
    final job = _jobs[id];
    if (job == null || !job.status.canPause) return;
    final wasRunning = job.status == JobStatus.running;
    _set(job.copyWith(status: JobStatus.paused));
    if (wasRunning) await _media.pause(id);
  }

  /// Puts a paused job back in its place in the queue.
  void resume(String id) {
    _checkOpen();
    final job = _jobs[id];
    if (job == null || !job.status.canResume) return;
    _set(job.copyWith(status: JobStatus.queued));
    _pump();
  }

  /// Pauses every queued and running job.
  Future<void> pauseAll() => Future.wait([
    for (final j in _jobs.values.toList())
      if (j.status.canPause) pause(j.id),
  ]);

  /// Resumes every paused job.
  void resumeAll() {
    for (final j in _jobs.values.toList()) {
      if (j.status.canResume) resume(j.id);
    }
  }

  /// Puts a failed or cancelled job back in the queue.
  void retry(String id) {
    _checkOpen();
    final job = _jobs[id];
    if (job == null || !job.status.canRetry) return;
    _set(job.copyWith(status: JobStatus.queued, progress: null, error: null));
    _pump();
  }

  /// Removes a completed, failed, cancelled or paused job from the list.
  void remove(String id) {
    final job = _jobs[id];
    if (job == null || !job.status.canRemove) return;
    _jobs.remove(id);
    if (job.status == JobStatus.paused) unawaited(_media.cancel(id));
    _emit();
  }

  /// Removes every completed job.
  void clearFinished() {
    final before = _jobs.length;
    _jobs.removeWhere((_, j) => j.status == JobStatus.completed);
    if (_jobs.length != before) _emit();
  }

  /// Stops every running job and closes [changes].
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final runs = _runs.values.toList();
    _runs.clear();
    await Future.wait(runs.map((s) => s.cancel()));
    await _changes.close();
  }

  void _pump() {
    if (_disposed) return;
    for (final job in _jobs.values.toList()) {
      if (_runs.length >= _maxConcurrent) return;
      if (job.status == JobStatus.queued && !_runs.containsKey(job.id)) {
        _start(job);
      }
    }
  }

  void _start(DownloadJob job) {
    final id = job.id;
    _set(job.copyWith(status: JobStatus.running));
    JobProgress? last;
    _runs[id] = _media
        .download(job.request)
        .listen(
          (progress) {
            last = progress;
            final current = _running(id);
            if (current != null) _set(current.copyWith(progress: progress));
          },
          onError: (Object e) => _end(
            id,
            e is Paused ? JobStatus.paused : JobStatus.failed,
            e is Cancelled || e is Paused
                ? null
                : e is FtubeException
                ? e
                : Unexpected('$e'),
            cancelled: e is Cancelled,
          ),
          onDone: () => last?.phase == JobPhase.finished
              ? _end(id, JobStatus.completed, null)
              : _end(
                  id,
                  JobStatus.failed,
                  const Unexpected('download ended without a result'),
                ),
          cancelOnError: true,
        );
  }

  /// Records how a run ended, unless the job was cancelled, retried or
  /// removed in the meantime, then frees the slot.
  void _end(
    String id,
    JobStatus status,
    FtubeException? error, {
    bool cancelled = false,
  }) {
    if (_runs.remove(id) == null) return;
    final current = _running(id);
    if (current != null) {
      _set(
        cancelled
            ? current.copyWith(
                status: JobStatus.cancelled,
                error: const Cancelled(),
              )
            : current.copyWith(status: status, error: error),
      );
    }
    _pump();
  }

  DownloadJob? _running(String id) {
    final job = _jobs[id];
    return job?.status == JobStatus.running ? job : null;
  }

  void _set(DownloadJob job) {
    assert(
      _jobs[job.id]!.status == job.status ||
          _jobs[job.id]!.status.canTransitionTo(job.status),
      '${_jobs[job.id]!.status} -> ${job.status}',
    );
    _jobs[job.id] = job;
    _emit();
  }

  void _emit() {
    if (!_disposed) _changes.add(jobs);
  }

  void _checkOpen() {
    if (_disposed) throw StateError('DownloadRepository is disposed');
  }

  static int _clamp(int n) =>
      n.clamp(AppSettings.minConcurrent, AppSettings.maxConcurrent);
}
