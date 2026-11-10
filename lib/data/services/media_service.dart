import 'dart:io';

import '../../domain/models/models.dart';

/// Fetches, downloads and converts media.
///
/// Implemented by `DesktopMediaService` (bundled yt-dlp + ffmpeg) and
/// `AndroidMediaService` (yt-dlp via youtubedl-android + ffmpeg_kit).
/// Failures are reported as `FtubeException` subclasses, as a thrown error
/// for futures and as a stream error for streams.
abstract interface class MediaService {
  /// Reads title, duration, thumbnail and formats of [url].
  Future<MediaInfo> fetchInfo(String url);

  /// Runs [req] and emits progress until a `JobPhase.finished` update with
  /// the output path, then closes the stream.
  Stream<JobProgress> download(DownloadRequest req);

  /// Converts [src] to [target] audio at [dst], reporting under [jobId].
  Stream<JobProgress> convert(
    File src,
    AudioTarget target,
    File dst, {
    required String jobId,
  });

  /// Stops the download or conversion with [jobId]. Its stream ends with a
  /// `Cancelled` error. For a job that isn't running, deletes the partial
  /// files a [pause] kept.
  Future<void> cancel(String jobId);

  /// Stops the download with [jobId] but keeps its partial files, so a new
  /// [download] with the same id continues it (spec-v0.4 D-68). Its stream
  /// ends with a `Paused` error. Unknown ids are ignored.
  Future<void> pause(String jobId);
}
