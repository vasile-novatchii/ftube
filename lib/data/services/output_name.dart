import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Names and places finished downloads on every platform (spec-v0.3 D-39).
abstract final class OutputName {
  /// Look-alikes for the characters Windows, macOS, Android and FAT forbid
  /// in file names, as yt-dlp uses without `--restrict-filenames`.
  static const _lookAlikes = {
    '/': '⧸',
    r'\': '⧹',
    ':': '：',
    '*': '＊',
    '?': '？',
    '"': '＂',
    '<': '＜',
    '>': '＞',
    '|': '｜',
  };

  static const _reserved = {
    'CON', 'PRN', 'AUX', 'NUL', //
    'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
    'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
  };

  /// Longest name in UTF-8 bytes, leaving room for ` (99)` and an
  /// extension under the usual 255-byte limit.
  static const maxBytes = 200;

  /// [title] as a file name: spaces, case and Unicode are kept; forbidden
  /// characters become look-alikes; control characters, leading dots and
  /// trailing dots or spaces are dropped.
  static String fromTitle(String title) {
    final buf = StringBuffer();
    for (final rune in title.runes) {
      final ch = String.fromCharCode(rune);
      if (rune < 0x20 || rune == 0x7f) {
        buf.write(' ');
      } else {
        buf.write(_lookAlikes[ch] ?? ch);
      }
    }
    var name = buf
        .toString()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceFirst(RegExp(r'^\.+'), '');
    name = _truncate(name).replaceFirst(RegExp(r'[. ]+$'), '');
    if (name.isEmpty) return 'video';
    if (_reserved.contains(name.split('.').first.toUpperCase())) {
      return '${name}_';
    }
    return name;
  }

  static String _truncate(String name) {
    if (utf8.encode(name).length <= maxBytes) return name;
    final out = StringBuffer();
    var bytes = 0;
    for (final rune in name.runes) {
      final ch = String.fromCharCode(rune);
      final size = utf8.encode(ch).length;
      if (bytes + size > maxBytes) break;
      bytes += size;
      out.write(ch);
    }
    return out.toString();
  }

  /// Moves [src] into [dir] as `<name><ext>`, or `<name> (2)<ext>`,
  /// `<name> (3)<ext>`... when taken. Never replaces an existing file:
  /// the name is reserved by creating it exclusively first.
  static Future<File> place(File src, Directory dir, String name) async {
    final ext = p.extension(src.path);
    for (var n = 1; ; n++) {
      final dst = File(
        p.join(dir.path, n == 1 ? '$name$ext' : '$name ($n)$ext'),
      );
      try {
        dst.createSync(exclusive: true);
      } on FileSystemException {
        if (dst.existsSync()) continue;
        rethrow;
      }
      try {
        await _move(src, dst);
      } on Object {
        _deleteQuietly(dst);
        rethrow;
      }
      return dst;
    }
  }

  /// Renames [src] over the reserved [dst], copying when they are on
  /// different volumes (app cache to shared storage).
  static Future<void> _move(File src, File dst) async {
    try {
      await src.rename(dst.path);
    } on FileSystemException {
      await src.copy(dst.path);
      _deleteQuietly(src);
    }
  }

  static void _deleteQuietly(File f) {
    try {
      if (f.existsSync()) f.deleteSync();
    } on FileSystemException {
      // Best effort.
    }
  }
}
