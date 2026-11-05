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
  /// `Cancelled` error. Unknown ids are ignored.
  Future<void> cancel(String jobId);
}
