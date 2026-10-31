import 'dart:convert';
import 'dart:ffi' show Abi;

import '../binary_service.dart';

/// CPU architectures the binaries are published for (D-18).
enum CpuArch {
  arm64,
  x86_64;

  /// The architecture of [abi], or null when no binaries exist for it.
  static CpuArch? fromAbi(Abi abi) => switch (abi) {
    Abi.macosArm64 => arm64,
    Abi.macosX64 || Abi.windowsX64 || Abi.linuxX64 => x86_64,
    _ => null,
  };

  static CpuArch? get current => fromAbi(Abi.current());
}

/// One downloadable binary for one OS and CPU.
final class CatalogEntry {
  const CatalogEntry({
    required this.binary,
    required this.os,
    required this.arch,
    required this.url,
    required this.sha256,
    required this.size,
  });

  final Binary binary;
  final DesktopOs os;
  final CpuArch arch;

  /// The gzip file to download.
  final Uri url;

  /// SHA-256 of the gzip file, lowercase hex.
  final String sha256;

  /// Size of the gzip file in bytes.
  final int size;

  Map<String, Object> toJson() => {
    'binary': binary.label,
    'os': os.name,
    'arch': arch.name,
    'url': '$url',
    'sha256': sha256,
    'size': size,
  };
}

/// Thrown when `assets/binaries/catalog.json` is malformed.
final class CatalogException implements Exception {
  const CatalogException(this.message);

  final String message;

  @override
  String toString() => 'CatalogException: $message';
}

/// The binaries the app installs on first launch, from
/// `assets/binaries/catalog.json` (D-17).
final class BinaryCatalog {
  const BinaryCatalog({required this.release, required this.entries});

  /// Parses and validates the catalog JSON.
  factory BinaryCatalog.parse(String source) {
    final Object? doc;
    try {
      doc = jsonDecode(source);
    } on FormatException catch (e) {
      throw CatalogException('invalid JSON: ${e.message}');
    }
    if (doc is! Map<String, Object?>) {
      throw const CatalogException('top level must be an object');
    }
    final release = doc['release'];
    final list = doc['entries'];
    if (release is! String || release.isEmpty) {
      throw const CatalogException('release must be a non-empty string');
    }
    if (list is! List<Object?>) {
      throw const CatalogException('entries must be a list');
    }
    final entries = [
      for (final (i, e) in list.indexed) _entry(e, 'entries[$i]'),
    ];
    final seen = <(Binary, DesktopOs, CpuArch)>{};
    for (final e in entries) {
      if (!seen.add((e.binary, e.os, e.arch))) {
        throw CatalogException(
          'duplicate entry ${e.binary.label} ${e.os.name} ${e.arch.name}',
        );
      }
    }
    return BinaryCatalog(release: release, entries: entries);
  }

  /// Release tag that hosts the files, for example `binaries-r1`.
  final String release;

  final List<CatalogEntry> entries;

  /// The entries to install on [os] with [arch].
  List<CatalogEntry> entriesFor(DesktopOs os, CpuArch arch) => [
    for (final e in entries)
      if (e.os == os && e.arch == arch) e,
  ];

  String toJson() => const JsonEncoder.withIndent('  ').convert({
    'release': release,
    'entries': [for (final e in entries) e.toJson()],
  });
}

final _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

CatalogEntry _entry(Object? e, String where) {
  if (e is! Map<String, Object?>) {
    throw CatalogException('$where must be an object');
  }
  T pick<T extends Enum>(List<T> values, String key, String Function(T) name) {
    final v = e[key];
    for (final value in values) {
      if (name(value) == v) return value;
    }
    throw CatalogException('$where: unknown $key "$v"');
  }

  final url = Uri.tryParse('${e['url']}');
  if (url == null || !url.isScheme('https') || url.host.isEmpty) {
    throw CatalogException('$where: url must be https');
  }
  final sha = e['sha256'];
  if (sha is! String || !_sha256Pattern.hasMatch(sha)) {
    throw CatalogException('$where: sha256 must be 64 lowercase hex chars');
  }
  final size = e['size'];
  if (size is! int || size <= 0) {
    throw CatalogException('$where: size must be a positive integer');
  }
  return CatalogEntry(
    binary: pick(Binary.values, 'binary', (b) => b.label),
    os: pick(DesktopOs.values, 'os', (o) => o.name),
    arch: pick(CpuArch.values, 'arch', (a) => a.name),
    url: url,
    sha256: sha,
    size: size,
  );
}
