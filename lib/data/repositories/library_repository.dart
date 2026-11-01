import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/exceptions/ftube_exception.dart';
import '../../domain/models/models.dart';
import '../services/android/storage_permission_service.dart';
import '../services/file_system_service.dart';
import '../services/media_service.dart';

/// The files in the download folder: list, rename, delete, open and convert.
///
/// The folder itself is the persistent record of what was downloaded, so
/// nothing is cached here; callers list again after a change.
class LibraryRepository {
  LibraryRepository({
    required this._files,
    required this._media,
    this._storage,
  });

  final FileSystemService _files;
  final MediaService _media;

  /// Android storage access; null on desktop.
  final StoragePermissionService? _storage;

  /// Characters no file system accepts in a name, plus control characters.
  static final _reserved = RegExp(r'[<>:"/\\|?*\x00-\x1F]');

  /// Longest name a rename accepts, without the extension.
  static const maxNameLength = 200;

  bool get canOpen => _files.canOpen;

  bool get canReveal => _files.canReveal;

  bool get canShare => _files.canShare;

  /// Files in [dir], newest first.
  Future<List<LibraryItem>> list(Directory dir) async {
    await _storage?.ensureGranted();
    return _files.list(dir);
  }

  /// Deletes [items] one by one. Every item is tried; the first failure is
  /// rethrown at the end. Returns how many were deleted.
  Future<int> delete(Iterable<LibraryItem> items) async {
    await _storage?.ensureGranted();
    var deleted = 0;
    FtubeException? firstError;
    for (final item in items) {
      try {
        await _files.delete(item.path);
        deleted++;
        await _storage?.scanFile(item.path);
      } on FtubeException catch (e) {
        firstError ??= e;
      }
    }
    if (firstError != null) throw firstError;
    return deleted;
  }

  /// Renames [item] to [newName], keeping its extension. Typing the
  /// extension again is allowed and not doubled.
  Future<LibraryItem> rename(LibraryItem item, String newName) async {
    final ext = p.extension(item.name);
    var base = newName.trim();
    if (ext.isNotEmpty && base.toLowerCase().endsWith(ext.toLowerCase())) {
      base = base.substring(0, base.length - ext.length).trimRight();
    }
    if (base.isEmpty ||
        base.startsWith('.') ||
        base.endsWith('.') ||
        base.length > maxNameLength ||
        _reserved.hasMatch(base)) {
      throw InvalidFileName(newName);
    }
    final name = '$base$ext';
    if (name == item.name) return item;

    await _storage?.ensureGranted();
    final newPath = p.join(p.dirname(item.path), name);
    await _files.rename(item.path, newPath);
    await _storage?.scanFile(item.path);
    await _storage?.scanFile(newPath);
    return _files.stat(newPath);
  }

  /// Converts [item] to [target] next to the original, as `<name>.<ext>` or
  /// `<name>_2.<ext>`... when taken. Cancel with [cancelConversion].
  Stream<JobProgress> convert(
    LibraryItem item,
    AudioTarget target, {
    required String jobId,
  }) {
    final ext = p.extension(item.name).toLowerCase();
    if (item.kind == LibraryKind.other || ext == '.${target.extension}') {
      return Stream.error(Unsupported('${item.name} to ${target.extension}'));
    }
    final dst = freePath(
      Directory(p.dirname(item.path)),
      p.basenameWithoutExtension(item.name),
      '.${target.extension}',
    );
    return _media.convert(File(item.path), target, dst, jobId: jobId);
  }

  Future<void> cancelConversion(String jobId) => _media.cancel(jobId);

  Future<void> open(LibraryItem item) => _files.open(item.path);

  Future<void> reveal(LibraryItem item) => _files.reveal(item.path);

  Future<void> share(LibraryItem item) => _files.share(item.path);

  /// `<dir>/<name><ext>`, or `<name>_2<ext>`, `<name>_3<ext>`... when taken.
  static File freePath(Directory dir, String name, String ext) {
    var file = File(p.join(dir.path, '$name$ext'));
    for (var n = 2; file.existsSync(); n++) {
      file = File(p.join(dir.path, '${name}_$n$ext'));
    }
    return file;
  }
}
