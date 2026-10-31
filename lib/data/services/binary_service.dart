import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/exceptions/ftube_exception.dart';
import 'process_runner.dart';

/// Desktop operating systems that ship bundled binaries.
enum DesktopOs {
  macos,
  windows,
  linux;

  static DesktopOs? get current {
    if (Platform.isMacOS) return macos;
    if (Platform.isWindows) return windows;
    if (Platform.isLinux) return linux;
    return null;
  }
}

/// Binaries bundled with the desktop builds (D-1).
enum Binary {
  ytDlp('yt-dlp'),
  ffmpeg('ffmpeg'),
  ffprobe('ffprobe'),
  deno('deno');

  const Binary(this.label);

  /// Name shown to the user and used in [BinaryMissing].
  final String label;

  /// File name on [os]. yt-dlp keeps its upstream release name so that
  /// `yt-dlp -U` picks the right update asset.
  String fileName(DesktopOs os) => switch ((this, os)) {
    (ytDlp, DesktopOs.macos) => 'yt-dlp_macos',
    (ytDlp, DesktopOs.linux) => 'yt-dlp_linux',
    (_, DesktopOs.windows) => '$label.exe',
    _ => label,
  };
}

/// Locates the bundled binaries, reports their versions and updates yt-dlp.
///
/// Binaries live next to the app executable (D-3). "Update yt-dlp" works on
/// a copy in [supportDir], which then takes precedence over the read-only
/// bundled copy (D-4).
class BinaryService {
  BinaryService({
    required this.os,
    required this.bundledDir,
    required this.supportDir,
    required this._runner,
  });

  final DesktopOs os;

  /// Folder with the bundled binaries.
  final Directory bundledDir;

  /// Writable app support folder for the updatable yt-dlp copy.
  final Directory supportDir;

  final ProcessRunner _runner;

  /// Env var that points at a binaries folder during development, for
  /// example `build/binaries/macos` from `tool/fetch_binaries.dart`.
  static const devOverrideEnv = 'FTUBE_BIN_DIR';

  /// Where the bundled binaries are for an app at [resolvedExecutable]:
  /// `Contents/MacOS` on macOS, the `.exe` folder on Windows and
  /// `bundle/lib` on Linux.
  static Directory bundledDirFor(
    DesktopOs os,
    String resolvedExecutable, {
    Map<String, String> environment = const {},
  }) {
    final override = environment[devOverrideEnv];
    if (override != null && override.isNotEmpty) return Directory(override);
    final exeDir = p.dirname(resolvedExecutable);
    return Directory(os == DesktopOs.linux ? p.join(exeDir, 'lib') : exeDir);
  }

  File _bundled(Binary binary) =>
      File(p.join(bundledDir.path, binary.fileName(os)));

  File get _ytDlpCopy =>
      File(p.join(supportDir.path, 'bin', Binary.ytDlp.fileName(os)));

  /// The file to run for [binary]. Throws [BinaryMissing] if it is absent.
  Future<File> locate(Binary binary) async {
    if (binary == Binary.ytDlp && _ytDlpCopy.existsSync()) return _ytDlpCopy;
    final file = _bundled(binary);
    if (file.existsSync()) return file;
    throw BinaryMissing(binary.label);
  }

  /// The version reported by [binary], or `null` if it is missing or fails.
  Future<String?> version(Binary binary) async {
    final File file;
    try {
      file = await locate(binary);
    } on BinaryMissing {
      return null;
    }
    final flag = switch (binary) {
      Binary.ffmpeg || Binary.ffprobe => '-version',
      Binary.ytDlp || Binary.deno => '--version',
    };
    try {
      final out = await _runner.run(file.path, [flag]);
      if (out.exitCode != 0) return null;
      return parseVersion(binary, out.stdout);
    } on ProcessException {
      return null;
    }
  }

  /// Extracts the version from the first line of `--version` output.
  static String? parseVersion(Binary binary, String stdout) {
    final first = stdout.trimLeft().split(RegExp(r'\r?\n')).first.trim();
    if (first.isEmpty) return null;
    final match = switch (binary) {
      // "ffmpeg version 9.0.2 Copyright (c) ..."
      Binary.ffmpeg ||
      Binary.ffprobe => RegExp(r'version\s+(\S+)').firstMatch(first),
      // "deno 2.9.8 (stable, release, aarch64-apple-darwin)"
      Binary.deno => RegExp(r'^deno\s+(\S+)').firstMatch(first),
      // "2026.10.26"
      Binary.ytDlp => RegExp(r'^(\S+)$').firstMatch(first),
    };
    return match?.group(1);
  }

  /// Runs `yt-dlp -U` on the writable copy and returns the new version.
  ///
  /// The first update copies the bundled yt-dlp into [supportDir]. Throws
  /// [BinaryMissing] when there is nothing to copy and [ProcessFailed] when
  /// the update fails.
  Future<String?> updateYtDlp() async {
    final copy = _ytDlpCopy;
    if (!copy.existsSync()) {
      final bundled = _bundled(Binary.ytDlp);
      if (!bundled.existsSync()) throw BinaryMissing(Binary.ytDlp.label);
      await copy.parent.create(recursive: true);
      await bundled.copy(copy.path);
      if (os != DesktopOs.windows) {
        await _runner.run('chmod', ['755', copy.path]);
      }
    }
    final out = await _runner.run(copy.path, ['-U']);
    if (out.exitCode != 0) {
      throw ProcessFailed.fromStderr(out.exitCode, out.stderr);
    }
    return version(Binary.ytDlp);
  }
}
