import 'dart:io';
import 'dart:typed_data';

import 'binaries_manifest.dart';

/// One unpacked binary from `tool/binaries.yaml`.
class FetchedFile {
  const FetchedFile(this.name, this.arch, this.bytes);

  /// Output file name, for example `ffmpeg` or `yt-dlp.exe`.
  final String name;

  /// CPU of an arch slice, or null for a file that serves every CPU.
  final String? arch;

  final Uint8List bytes;
}

/// Downloads (or reads from [cacheDir]) and unpacks every artifact of
/// [platform], verifying each checksum.
Future<List<FetchedFile>> fetchPlatform(
  String platform, {
  required Directory cacheDir,
  String manifestPath = 'tool/binaries.yaml',
}) async {
  final manifest = parseManifest(await File(manifestPath).readAsString());
  await cacheDir.create(recursive: true);
  return [
    for (final artifact in manifest[platform] ?? const <Artifact>[])
      for (final MapEntry(key: name, value: bytes) in extractFiles(
        artifact,
        await _download(artifact, cacheDir),
      ).entries)
        FetchedFile(name, artifact.arch, bytes),
  ];
}

Future<Uint8List> _download(Artifact artifact, Directory cacheDir) async {
  final cached = File('${cacheDir.path}/${artifact.sha256}');
  if (cached.existsSync()) {
    final bytes = await cached.readAsBytes();
    if (sha256Hex(bytes) == artifact.sha256) return bytes;
  }
  stdout.writeln('Downloading ${artifact.url}');
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(artifact.url)).close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode}', uri: artifact.url);
    }
    final builder = BytesBuilder(copy: false);
    await response.forEach(builder.add);
    final bytes = builder.takeBytes();
    verifyChecksum(artifact, bytes);
    await cached.writeAsBytes(bytes, flush: true);
    return bytes;
  } finally {
    client.close();
  }
}

/// Runs [executable] and returns stdout, throwing on a non-zero exit.
Future<String> exec(String executable, List<String> args) async {
  final result = await Process.run(executable, args);
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      args,
      '${result.stderr}'.trim(),
      result.exitCode,
    );
  }
  return '${result.stdout}';
}
