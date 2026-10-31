// Downloads, verifies and unpacks the desktop binaries from
// tool/binaries.yaml (spec D-2).
//
//   dart run tool/fetch_binaries.dart [--platform macos|windows|linux]
//       [--out <dir>] [--smoke]
//
// --platform  defaults to the host OS.
// --out       defaults to build/binaries/<platform>.
// --smoke     runs each binary's version command afterwards (host platform
//             only).
//
// Downloads are cached by checksum in .dart_tool/ftube_binaries/. Universal
// macOS binaries are built with lipo, so --platform macos needs a Mac.
import 'dart:io';
import 'dart:typed_data';

import 'src/binaries_manifest.dart';

Future<void> main(List<String> args) async {
  try {
    await _run(args);
  } on Object catch (e) {
    stderr.writeln('fetch_binaries: $e');
    exitCode = 1;
  }
}

Future<void> _run(List<String> args) async {
  String? option(String name) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final platform = option('--platform') ?? Platform.operatingSystem;
  if (!manifestPlatforms.contains(platform)) {
    throw ArgumentError('unsupported platform "$platform"');
  }
  final outDir = Directory(option('--out') ?? 'build/binaries/$platform');
  final cacheDir = Directory('.dart_tool/ftube_binaries');
  final manifest = parseManifest(
    await File('tool/binaries.yaml').readAsString(),
  );
  final artifacts = manifest[platform] ?? const [];

  await outDir.create(recursive: true);
  await cacheDir.create(recursive: true);

  // Output name -> slices to merge with lipo (arch -> bytes).
  final slices = <String, Map<String, Uint8List>>{};
  for (final artifact in artifacts) {
    final bytes = await _download(artifact, cacheDir);
    final files = extractFiles(artifact, bytes);
    for (final MapEntry(key: name, value: content) in files.entries) {
      final arch = artifact.arch;
      if (arch == null) {
        await _writeExecutable(File('${outDir.path}/$name'), content);
      } else {
        (slices[name] ??= {})[arch] = content;
      }
    }
  }
  for (final MapEntry(key: name, value: byArch) in slices.entries) {
    await _lipo(outDir, name, byArch);
  }

  final names = {for (final a in artifacts) ...a.files.values}.toList()..sort();
  stdout.writeln(
    'Binaries for $platform in ${outDir.path}: ${names.join(', ')}',
  );
  if (args.contains('--smoke')) await _smoke(outDir, names);
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

Future<void> _writeExecutable(File file, List<int> content) async {
  await file.writeAsBytes(content, flush: true);
  if (!Platform.isWindows) await _exec('chmod', ['755', file.path]);
}

Future<void> _lipo(
  Directory outDir,
  String name,
  Map<String, Uint8List> byArch,
) async {
  if (!Platform.isMacOS) {
    throw UnsupportedError('universal $name needs lipo, run on macOS');
  }
  final tmp = await Directory.systemTemp.createTemp('ftube_lipo');
  try {
    final inputs = <String>[];
    for (final MapEntry(key: arch, value: bytes) in byArch.entries) {
      final slice = File('${tmp.path}/$name.$arch');
      await slice.writeAsBytes(bytes, flush: true);
      inputs.add(slice.path);
    }
    final out = '${outDir.path}/$name';
    await _exec('lipo', ['-create', ...inputs, '-output', out]);
    await _exec('chmod', ['755', out]);
    final archs = (await _exec('lipo', ['-archs', out])).trim().split(' ');
    for (final arch in byArch.keys) {
      if (!archs.contains(arch)) {
        throw StateError('$name is missing $arch after lipo: $archs');
      }
    }
  } finally {
    await tmp.delete(recursive: true);
  }
}

Future<void> _smoke(Directory outDir, List<String> names) async {
  for (final name in names) {
    final flag = name.startsWith('ff') ? '-version' : '--version';
    final out = await _exec('${outDir.path}/$name', [flag]);
    stdout.writeln('$name: ${out.split('\n').first.trim()}');
  }
}

Future<String> _exec(String executable, List<String> args) async {
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
