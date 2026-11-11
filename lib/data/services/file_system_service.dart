import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../domain/exceptions/ftube_exception.dart';
import '../../domain/models/library_item.dart';
import 'android/android_file_launcher.dart';
import 'binary_service.dart';
import 'process_runner.dart';

/// Lists, renames and trashes files, and opens them with the system apps.
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

  /// Deletes everything inside [dir], keeping [dir] itself. Entries that
  /// can't be deleted, for example while in use, are skipped.
  Future<void> emptyDir(Directory dir) async {
    if (!dir.existsSync()) return;
    await for (final entity in dir.list(followLinks: false)) {
      try {
        await entity.delete(recursive: true);
      } on FileSystemException {
        // In use or already gone.
      }
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

  /// Reaches the bin through native code on macOS, Windows and Android
  /// (docs/spec-v0.2.md D-23).
  static const trashChannel = MethodChannel('io.github.infvyr.ftube/trash');

  /// Moves [paths] to the system bin and returns the ones moved. Missing
  /// files are skipped. On Android the user may cancel the system dialog,
  /// and then nothing moves. Every file is tried; a failure is thrown as
  /// [FileError] at the end.
  Future<List<String>> trash(List<String> paths) async {
    final existing = [
      for (final path in paths)
        if (File(path).existsSync()) path,
    ];
    if (existing.isEmpty) return const [];
    if (os == DesktopOs.linux) return _gioTrash(existing);
    final Map<Object?, Object?>? reply;
    try {
      reply = await trashChannel.invokeMapMethod<Object?, Object?>('trash', {
        'paths': existing,
      });
    } on PlatformException catch (e) {
      throw FileError(e.message ?? e.code);
    } on MissingPluginException {
      throw const Unsupported('trash');
    }
    final moved = [...?(reply?['moved'] as List<Object?>?)?.cast<String>()];
    if (reply?['error'] case final String error) throw FileError(error);
    return moved;
  }

  Future<List<String>> _gioTrash(List<String> paths) async {
    final moved = <String>[];
    FtubeException? firstError;
    for (final path in paths) {
      try {
        final out = await _runner.run('gio', ['trash', '--', path]);
        if (out.exitCode == 0) {
          moved.add(path);
        } else {
          firstError ??= FileError('gio trash exited with ${out.exitCode}');
        }
      } on ProcessException catch (e) {
        throw Unsupported('gio: ${e.message}');
      }
    }
    if (firstError != null) throw firstError;
    return moved;
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

  /// Opens an https [url] in the default browser (docs/spec-v0.6.md D-94).
  /// No shell parses the URL on any platform.
  Future<void> openUrl(Uri url) async {
    if (!url.isScheme('https')) throw Unsupported('openUrl: $url');
    final link = url.toString();
    return switch (os) {
      DesktopOs.macos => _launch('open', [link]),
      DesktopOs.windows => _launch('rundll32', [
        'url.dll,FileProtocolHandler',
        link,
      ], checkExit: false),
      DesktopOs.linux => _launch('xdg-open', [link]),
      null => _androidLauncher('openUrl').openUrl(link),
    };
  }

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
