import 'dart:io';

import '../../domain/models/models.dart';
import '../services/android/storage_permission_service.dart';
import 'download_repository.dart';

/// The download folder could not be resolved, so nothing can be saved.
class NoDownloadFolder implements Exception {
  const NoDownloadFolder();
}

/// Android: storage access is missing, so nothing can be saved.
class StorageBlocked implements Exception {
  const StorageBlocked();
}

/// Queues a fetched video, from Home or the share popup
/// (spec-v0.4-share D-53).
class DownloadStarter {
  const DownloadStarter({
    required DownloadRepository repository,
    required this._downloadDir,
    this._storage,
  }) : _repo = repository;

  final DownloadRepository _repo;
  final Future<Directory?> Function() _downloadDir;
  final StoragePermissionService? _storage;

  /// Queues [info] with [preset], or with [format] when it is set.
  ///
  /// Throws [StorageBlocked] or [NoDownloadFolder] when it can't.
  Future<DownloadJob> start(
    MediaInfo info,
    QualityPreset preset, {
    MediaFormat? format,
  }) async {
    final dir = await _outDir();
    return _repo.enqueue(
      url: info.url,
      title: info.title,
      preset: format == null ? preset : QualityPreset.custom,
      formatId: selector(format),
      outDir: dir,
    );
  }

  /// Queues one job per entry with [preset] (spec-v0.5 D-58). Entries that
  /// can't be downloaded are skipped.
  ///
  /// Throws [StorageBlocked] or [NoDownloadFolder] when it can't.
  Future<List<DownloadJob>> startAll(
    List<PlaylistEntry> entries,
    QualityPreset preset,
  ) async {
    final dir = await _outDir();
    return _repo.enqueueAll(
      [
        for (final e in entries)
          if (e.downloadable) (url: e.url, title: e.title),
      ],
      preset: preset,
      outDir: dir,
    );
  }

  Future<Directory> _outDir() async {
    final storage = _storage;
    if (storage != null && await storage.status() != StorageAccess.granted) {
      throw const StorageBlocked();
    }
    final dir = await _downloadDir().catchError((Object _) => null);
    if (dir == null) throw const NoDownloadFolder();
    return dir;
  }

  /// The `formatId` for the request. yt-dlp downloads a video-only format
  /// without sound, so the best audio is added (`+ba`, spec D-16). Android
  /// runs yt-dlp too since v0.3 (spec-v0.3 D-38).
  static String? selector(MediaFormat? format) {
    if (format == null) return null;
    return format.kind == FormatKind.videoOnly ? '${format.id}+ba' : format.id;
  }
}
