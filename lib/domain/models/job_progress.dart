import 'package:freezed_annotation/freezed_annotation.dart';

part 'job_progress.freezed.dart';

/// Step a running job is in.
enum JobPhase {
  downloadingVideo,
  downloadingAudio,
  merging,
  converting,
  finished,
}

/// One progress update emitted by a `MediaService` stream.
@freezed
abstract class JobProgress with _$JobProgress {
  @Assert(
    'fraction == null || (fraction >= 0 && fraction <= 1)',
    'fraction must be within 0..1',
  )
  const factory JobProgress({
    required String jobId,
    required JobPhase phase,

    /// Overall progress across all phases, 0..1, or null when unknown.
    double? fraction,
    int? downloadedBytes,
    int? totalBytes,
    double? speedBps,
    Duration? eta,

    /// Set on the `finished` update.
    String? outputPath,
  }) = _JobProgress;
}
