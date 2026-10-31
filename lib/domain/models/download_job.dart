import 'package:freezed_annotation/freezed_annotation.dart';

import '../exceptions/ftube_exception.dart';
import 'download_request.dart';
import 'job_progress.dart';
import 'job_status.dart';

part 'download_job.freezed.dart';

/// A download in the in-memory queue.
@freezed
abstract class DownloadJob with _$DownloadJob {
  const factory DownloadJob({
    required DownloadRequest request,
    required String title,
    required DateTime createdAt,
    @Default(JobStatus.queued) JobStatus status,
    JobProgress? progress,
    FtubeException? error,
  }) = _DownloadJob;

  const DownloadJob._();

  String get id => request.jobId;

  String? get outputPath => progress?.outputPath;
}
