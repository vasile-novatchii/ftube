import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:yaml/yaml.dart';

/// Platforms listed in `tool/binaries.yaml`.
const manifestPlatforms = ['macos', 'windows', 'linux'];

/// One pinned download from `tool/binaries.yaml`.
class Artifact {
  const Artifact({
    required this.url,
    required this.sha256,
    required this.files,
    this.arch,
  });

  final Uri url;

  /// Expected SHA-256 of the download, lowercase hex.
  final String sha256;

  /// Archive member path (or `.` for a plain file) to output file name.
  final Map<String, String> files;

  /// CPU architecture for slices merged with `lipo`, or null.
  final String? arch;

  String get fileName => url.pathSegments.last;

  ArchiveKind get kind => switch (fileName) {
    final n when n.endsWith('.zip') => ArchiveKind.zip,
    final n when n.endsWith('.tar.xz') => ArchiveKind.tarXz,
    _ => ArchiveKind.plain,
  };
}

enum ArchiveKind { plain, zip, tarXz }

/// Thrown for a malformed manifest or a download that fails verification.
class ManifestException implements Exception {
  ManifestException(this.message);

  final String message;

  @override
  String toString() => 'ManifestException: $message';
}

final _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

/// Parses and validates `tool/binaries.yaml`.
Map<String, List<Artifact>> parseManifest(String source) {
  final Object? doc = loadYaml(source);
  if (doc is! YamlMap) throw ManifestException('top level must be a map');
  final result = <String, List<Artifact>>{};
  for (final MapEntry(:key, :value) in doc.entries) {
    if (!manifestPlatforms.contains(key)) {
      throw ManifestException('unknown platform "$key"');
    }
    if (value is! YamlList) throw ManifestException('$key must be a list');
    result[key as String] = [
      for (final (i, entry) in value.indexed) _artifact(entry, '$key[$i]'),
    ];
  }
  return result;
}

Artifact _artifact(Object? entry, String where) {
  if (entry is! YamlMap) throw ManifestException('$where must be a map');
  final url = Uri.tryParse('${entry['url']}');
  if (url == null || !url.isScheme('https') || url.pathSegments.isEmpty) {
    throw ManifestException('$where: url must be https');
  }
  final sha = '${entry['sha256']}';
  if (!_sha256Pattern.hasMatch(sha)) {
    throw ManifestException('$where: sha256 must be 64 lowercase hex chars');
  }
  final files = entry['files'];
  if (files is! YamlMap || files.isEmpty) {
    throw ManifestException('$where: files must be a non-empty map');
  }
  final artifact = Artifact(
    url: url,
    sha256: sha,
    arch: entry['arch'] as String?,
    files: {
      for (final MapEntry(:key, :value) in files.entries) '$key': '$value',
    },
  );
  if (artifact.kind == ArchiveKind.plain &&
      (artifact.files.length != 1 || artifact.files.keys.single != '.')) {
    throw ManifestException('$where: a plain file must map "." only');
  }
  return artifact;
}

/// Lowercase hex SHA-256 of [bytes].
String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// Throws when [bytes] do not match [artifact]'s checksum.
void verifyChecksum(Artifact artifact, List<int> bytes) {
  final actual = sha256Hex(bytes);
  if (actual != artifact.sha256) {
    throw ManifestException(
      'checksum mismatch for ${artifact.url}\n'
      '  expected ${artifact.sha256}\n  actual   $actual',
    );
  }
}

/// Returns output name to content for every file [artifact] lists.
Map<String, Uint8List> extractFiles(Artifact artifact, Uint8List bytes) {
  if (artifact.kind == ArchiveKind.plain) {
    return {artifact.files['.']!: bytes};
  }
  final archive = switch (artifact.kind) {
    ArchiveKind.zip => ZipDecoder().decodeBytes(bytes, verify: true),
    ArchiveKind.tarXz => TarDecoder().decodeBytes(
      XZDecoder().decodeBytes(bytes, verify: true, throwOnError: true),
    ),
    ArchiveKind.plain => throw StateError('unreachable'),
  };
  return {
    for (final MapEntry(key: member, value: name) in artifact.files.entries)
      name: switch (archive.findFile(member)) {
        final f? when f.isFile => f.content,
        _ => throw ManifestException('$member not found in ${artifact.url}'),
      },
  };
}
