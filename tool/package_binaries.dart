// Builds the mirrored binaries and the app catalog (spec D-17).
//
//   dart run tool/package_binaries.dart --release binaries-rN
//       [--repo owner/name] [--out <dir>] [--catalog <file>] [--check]
//
// Fetches every platform from tool/binaries.yaml, writes one gzip per
// binary, OS and CPU to --out (default build/binaries/release), and writes
// the catalog (default assets/binaries/catalog.json) with their GitHub
// release URLs, SHA-256 and sizes.
//
// --check compares the result with the existing catalog instead of
// writing it, and fails when any file differs. The release workflow uses
// it to make sure the published files are the ones the app expects.
import 'dart:io';

import 'package:ftube/data/services/binaries/binary_catalog.dart';
import 'package:ftube/data/services/binary_service.dart';

import 'src/binaries_manifest.dart';
import 'src/fetch.dart';

Future<void> main(List<String> args) async {
  try {
    await _run(args);
  } on Object catch (e) {
    stderr.writeln('package_binaries: $e');
    exitCode = 1;
  }
}

Future<void> _run(List<String> args) async {
  String? option(String name) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final release = option('--release');
  if (release == null || !RegExp(r'^binaries-r\d+$').hasMatch(release)) {
    throw ArgumentError('--release binaries-rN is required');
  }
  final repo = option('--repo') ?? 'vasile-novatchii/ftube';
  final outDir = Directory(option('--out') ?? 'build/binaries/release');
  final catalogFile = File(
    option('--catalog') ?? 'assets/binaries/catalog.json',
  );
  final check = args.contains('--check');
  final cacheDir = Directory('.dart_tool/ftube_binaries');

  await outDir.create(recursive: true);
  final entries = <CatalogEntry>[];
  for (final os in DesktopOs.values) {
    for (final file in await fetchPlatform(os.name, cacheDir: cacheDir)) {
      final binary = Binary.values.firstWhere(
        (b) => b.fileName(os) == file.name,
        orElse: () => throw StateError('unknown binary ${file.name}'),
      );
      final arches = switch ((os, file.arch)) {
        (_, final String arch) => [CpuArch.values.byName(arch)],
        // yt-dlp_macos is universal and serves both CPUs.
        (DesktopOs.macos, null) => CpuArch.values,
        (_, null) => [CpuArch.x86_64],
      };
      final suffix = file.arch == null && os == DesktopOs.macos
          ? 'universal'
          : arches.single.name;
      final name = '${binary.label}-${os.name}-$suffix.gz';
      final gz = GZipCodec(level: 9).encode(file.bytes);
      // Byte 9 is the OS that wrote the file. Pin it to 255 ("unknown") so
      // the output does not depend on the build machine.
      gz[9] = 255;
      await File('${outDir.path}/$name').writeAsBytes(gz, flush: true);
      final sha = sha256Hex(gz);
      stdout.writeln('$name  ${gz.length} bytes  $sha');
      for (final arch in arches) {
        entries.add(
          CatalogEntry(
            binary: binary,
            os: os,
            arch: arch,
            url: Uri.parse(
              'https://github.com/$repo/releases/download/$release/$name',
            ),
            sha256: sha,
            size: gz.length,
          ),
        );
      }
    }
  }

  final json =
      '${BinaryCatalog(release: release, entries: entries).toJson()}\n';
  if (check) {
    final existing = catalogFile.existsSync()
        ? await catalogFile.readAsString()
        : '';
    if (existing != json) {
      throw StateError(
        '${catalogFile.path} does not match the built files.\n'
        'Built catalog:\n$json',
      );
    }
    stdout.writeln('${catalogFile.path} matches the built files.');
  } else {
    await catalogFile.parent.create(recursive: true);
    await catalogFile.writeAsString(json);
    stdout.writeln('Wrote ${catalogFile.path}');
  }
  await File('${outDir.path}/catalog.json').writeAsString(json);
}
