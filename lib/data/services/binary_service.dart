import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/exceptions/ftube_exception.dart';
import 'process_runner.dart';

/// Desktop operating systems with their own binaries.
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

/// Binaries the desktop app runs (D-1).
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

/// Locates the desktop binaries, reports their versions and updates yt-dlp.
///
/// The binaries live in `<app support>/bin`, where `BinaryInstaller` puts
/// them on first launch (D-3, D-18).
class BinaryService {
  BinaryService({
    required this.os,
    required this.binDir,
    required this._runner,
  });

  final DesktopOs os;

  /// Folder with the installed binaries.
  final Directory binDir;

  final ProcessRunner _runner;

  /// Env var that points at a binaries folder during development, for
  /// example `build/binaries/macos` from `tool/fetch_binaries.dart`.
  static const devOverrideEnv = 'FTUBE_BIN_DIR';

  /// `<supportDir>/bin`, unless [devOverrideEnv] is set in [environment].
  static Directory binDirFor(
    Directory supportDir, {
    Map<String, String> environment = const {},
  }) {
    final override = environment[devOverrideEnv];
    if (override != null && override.isNotEmpty) return Directory(override);
    return Directory(p.join(supportDir.path, 'bin'));
  }

  /// The file to run for [binary]. Throws [BinaryMissing] if it is absent.
  Future<File> locate(Binary binary) async {
    final file = File(p.join(binDir.path, binary.fileName(os)));
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

  /// Runs `yt-dlp -U` on the installed yt-dlp and returns the new version.
  ///
  /// Throws [BinaryMissing] when yt-dlp is not installed and
  /// [ProcessFailed] when the update fails.
  Future<String?> updateYtDlp() async {
    final ytDlp = await locate(Binary.ytDlp);
    final out = await _runner.run(ytDlp.path, ['-U']);
    if (out.exitCode != 0) {
      throw ProcessFailed.fromStderr(out.exitCode, out.stderr);
    }
    return version(Binary.ytDlp);
  }
}
