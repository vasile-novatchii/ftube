/// Typed failures raised by services and repositories.
///
/// ViewModels map each subclass to a localized message.
sealed class FtubeException implements Exception {
  const FtubeException([this.detail]);

  /// Technical detail for logs, never shown as-is to the user.
  final String? detail;

  @override
  String toString() =>
      detail == null ? '$runtimeType' : '$runtimeType: $detail';
}

/// The URL is empty or not a valid http(s) URL.
final class InvalidUrl extends FtubeException {
  const InvalidUrl([super.detail]);
}

/// The URL or format is not supported on this platform.
final class Unsupported extends FtubeException {
  const Unsupported([super.detail]);
}

/// The network is unreachable or the site refused the request.
final class Network extends FtubeException {
  const Network([super.detail]);
}

/// A binary (yt-dlp, ffmpeg, ffprobe, deno) could not be found or run.
final class BinaryMissing extends FtubeException {
  const BinaryMissing(this.binary) : super(binary);

  final String binary;
}

/// A downloaded binary did not match the SHA-256 in the catalog.
final class ChecksumMismatch extends FtubeException {
  const ChecksumMismatch(this.binary) : super(binary);

  final String binary;
}

/// An external process or ffmpeg session ended with a non-zero exit code.
final class ProcessFailed extends FtubeException {
  const ProcessFailed(this.exitCode, this.stderrTail) : super('exit $exitCode');

  /// Keeps only the last [maxLines] non-empty lines of [stderr].
  factory ProcessFailed.fromStderr(
    int exitCode,
    String stderr, {
    int maxLines = 20,
  }) {
    final lines = stderr
        .split(RegExp(r'\r?\n'))
        .where((l) => l.trim().isNotEmpty)
        .toList();
    final tail = lines.length > maxLines
        ? lines.sublist(lines.length - maxLines)
        : lines;
    return ProcessFailed(exitCode, tail.join('\n'));
  }

  final int exitCode;
  final String stderrTail;
}

/// Android storage access ("All files access") is not granted.
final class StoragePermission extends FtubeException {
  const StoragePermission([super.detail]);
}

/// The job was cancelled by the user.
final class Cancelled extends FtubeException {
  const Cancelled([super.detail]);
}

/// The job was paused; its partial files are kept (spec-v0.4 D-68).
final class Paused extends FtubeException {
  const Paused([super.detail]);
}

/// A new file name is empty, has a path separator or a reserved character.
final class InvalidFileName extends FtubeException {
  const InvalidFileName(this.name) : super(name);

  final String name;
}

/// A file with the target name already exists.
final class FileExists extends FtubeException {
  const FileExists(this.name) : super(name);

  final String name;
}

/// A file could not be listed, renamed, deleted or opened.
final class FileError extends FtubeException {
  const FileError([super.detail]);
}

/// A failure that is not one of the typed cases above.
final class Unexpected extends FtubeException {
  const Unexpected([super.detail]);
}
