import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/exceptions/ftube_exception.dart';
import '../../domain/models/library_item.dart';
import 'android/android_file_launcher.dart';
import 'binary_service.dart';
import 'process_runner.dart';

/// Lists, renames and deletes files, and opens them with the system apps.
///
/// File system failures are reported as [FileError].
class FileSystemService {
  const FileSystemService({required this._runner, this.os, this._android});

  final ProcessRunner _runner;

  /// The desktop OS, or null on Android.
  final DesktopOs? os;

  /// Opens and shares files on Android; null on desktop.
  final AndroidFileLauncher? _android;

  /// Suffixes of partial files left by yt-dlp, ffmpeg or a crash.
  static const _partialSuffixes = ['.part', '.ytdl', '.tmp'];

  /// Whether [open] is available.
  bool get canOpen => os != null || _android != null;

  /// Whether [share] is available (Android only).
  bool get canShare => os == null && _android != null;

  /// Whether [reveal] is available. Android has no file manager to point at.
  bool get canReveal => os != null;

  /// Files directly in [dir], newest first. Hidden and partial files are
  /// skipped. A missing folder is an empty list.
  Future<List<LibraryItem>> list(Directory dir) async {
    try {
      if (!dir.existsSync()) return const [];
      final items = <LibraryItem>[];
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File || !_isVisible(entity.path)) continue;
        try {
          items.add(await _item(entity));
        } on FileSystemException {
          // Removed while listing.
        }
      }
      items.sort((a, b) => b.modified.compareTo(a.modified));
      return items;
    } on FileSystemException catch (e) {
      throw FileError(_detail(e));
    }
  }

  /// The [LibraryItem] for the file at [path].
  Future<LibraryItem> stat(String path) async {
    try {
      return await _item(File(path));
    } on FileSystemException catch (e) {
      throw FileError(_detail(e));
    }
  }

  /// Deletes the file at [path]. A missing file is not an error.
  Future<void> delete(String path) async {
    final file = File(path);
    try {
      if (file.existsSync()) await file.delete();
    } on FileSystemException catch (e) {
      throw FileError(_detail(e));
    }
  }

  /// Renames [path] to [newPath]. Throws [FileExists] when [newPath] is
  /// taken, so a rename never overwrites another file.
  Future<void> rename(String path, String newPath) async {
    if (FileSystemEntity.typeSync(newPath, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw FileExists(p.basename(newPath));
    }
    try {
      await File(path).rename(newPath);
    } on FileSystemException catch (e) {
      throw FileError(_detail(e));
    }
  }

  /// Opens [path] with the system default app.
  Future<void> open(String path) async => switch (os) {
    DesktopOs.macos => _launch('open', [path]),
    // explorer.exe exits with 1 even when it worked.
    DesktopOs.windows => _launch('explorer.exe', [path], checkExit: false),
    DesktopOs.linux => _launch('xdg-open', [path]),
    null => _androidLauncher('open').open(path),
  };

  /// Shows the system share sheet for [path] (Android only).
  Future<void> share(String path) async => switch (os) {
    null => _androidLauncher('share').share(path),
    _ => throw const Unsupported('share on desktop'),
  };

  /// Shows [path] in the system file manager (desktop only).
  Future<void> reveal(String path) async => switch (os) {
    DesktopOs.macos => _launch('open', ['-R', path]),
    DesktopOs.windows => _launch('explorer.exe', [
      '/select,$path',
    ], checkExit: false),
    DesktopOs.linux => _launch('xdg-open', [p.dirname(path)]),
    null => throw const Unsupported('reveal on Android'),
  };

  AndroidFileLauncher _androidLauncher(String action) =>
      _android ?? (throw Unsupported('$action without a launcher'));

  Future<void> _launch(
    String executable,
    List<String> args, {
    bool checkExit = true,
  }) async {
    final ProcessOutput out;
    try {
      out = await _runner.run(executable, args);
    } on ProcessException catch (e) {
      throw Unsupported('$executable: ${e.message}');
    }
    if (checkExit && out.exitCode != 0) {
      throw FileError('$executable exited with ${out.exitCode}');
    }
  }

  static bool _isVisible(String path) {
    final name = p.basename(path);
    if (name.startsWith('.')) return false;
    final lower = name.toLowerCase();
    return !_partialSuffixes.any(lower.endsWith);
  }

  static Future<LibraryItem> _item(File file) async {
    final stat = file.statSync();
    if (stat.type == FileSystemEntityType.notFound) {
      throw FileSystemException('not found', file.path);
    }
    return LibraryItem(
      path: file.path,
      name: p.basename(file.path),
      sizeBytes: stat.size,
      modified: stat.modified,
      kind: LibraryKind.fromPath(file.path),
    );
  }

  static String _detail(FileSystemException e) =>
      [e.message, e.path, e.osError?.message].whereType<String>().join(': ');
}
