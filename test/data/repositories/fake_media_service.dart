import 'dart:async';
import 'dart:io';

import 'package:ftube/data/services/media_service.dart';
import 'package:ftube/domain/exceptions/ftube_exception.dart';
import 'package:ftube/domain/models/models.dart';

/// A [MediaService] whose runs are driven by the test, one controller per
/// job id. Like the real services, a run keeps its id busy until it ends.
class FakeMediaService implements MediaService {
  final runs = <String, StreamController<JobProgress>>{};
  final started = <String>[];
  final cancelled = <String>[];
  final paused = <String>[];
  final converts = <(String src, AudioTarget target, String dst, String id)>[];

  /// Runs a conversion instead of finishing it at once.
  Stream<JobProgress> Function(String jobId, File dst)? onConvert;

  /// When false, [cancel] only records the call and the test ends the run.
  bool endOnCancel = true;

  @override
  Stream<JobProgress> download(DownloadRequest req) {
    final id = req.jobId;
    if (runs.containsKey(id)) {
      return Stream.error(StateError('job $id is already running'));
    }
    started.add(id);
    // Closed in _end.
    // ignore: close_sinks
    final controller = runs[id] = StreamController<JobProgress>();
    controller.onCancel = () => _end(id);
    return controller.stream;
  }

  @override
  Stream<JobProgress> convert(
    File src,
    AudioTarget target,
    File dst, {
    required String jobId,
  }) {
    converts.add((src.path, target, dst.path, jobId));
    if (onConvert case final run?) return run(jobId, dst);
    return Stream.value(
      JobProgress(
        jobId: jobId,
        phase: JobPhase.finished,
        fraction: 1,
        outputPath: dst.path,
      ),
    );
  }

  @override
  Future<void> cancel(String jobId) async {
    cancelled.add(jobId);
    if (endOnCancel) fail(jobId, const Cancelled());
  }

  @override
  Future<void> pause(String jobId) async {
    paused.add(jobId);
    if (endOnCancel) fail(jobId, const Paused());
  }

  /// Answers [fetchInfo]; the default throws [Network].
  Future<MediaInfo> Function(String url) onFetch = (_) async =>
      throw const Network();
  final fetched = <String>[];

  @override
  Future<MediaInfo> fetchInfo(String url) {
    fetched.add(url);
    return onFetch(url);
  }

  bool isRunning(String id) => runs.containsKey(id);

  void progress(String id, double fraction) => runs[id]!.add(
    JobProgress(
      jobId: id,
      phase: JobPhase.downloadingVideo,
      fraction: fraction,
    ),
  );

  void finish(String id, [String path = '/out/a.mp4']) {
    runs[id]!.add(
      JobProgress(
        jobId: id,
        phase: JobPhase.finished,
        fraction: 1,
        outputPath: path,
      ),
    );
    _end(id);
  }

  /// Ends the run without a finished update.
  void close(String id) => _end(id);

  void fail(String id, Object error) {
    // Closed in _end.
    // ignore: close_sinks
    final c = runs[id];
    if (c == null) return;
    c.addError(error);
    _end(id);
  }

  void _end(String id) {
    final c = runs.remove(id);
    if (c != null) unawaited(c.close());
  }
}
