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
// Used for development (FTUBE_BIN_DIR, spec D-3). The app itself installs
// the binaries on first launch from the catalog (D-17, D-18).
//
// Downloads are cached by checksum in .dart_tool/ftube_binaries/. Universal
// macOS binaries are built with lipo, so --platform macos needs a Mac.
import 'dart:io';
import 'dart:typed_data';

import 'src/binaries_manifest.dart';
import 'src/fetch.dart';

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
  final files = await fetchPlatform(
    platform,
    cacheDir: Directory('.dart_tool/ftube_binaries'),
  );
  await outDir.create(recursive: true);

  // Output name -> slices to merge with lipo (arch -> bytes).
  final slices = <String, Map<String, Uint8List>>{};
  for (final file in files) {
    if (file.arch == null) {
      await _writeExecutable(File('${outDir.path}/${file.name}'), file.bytes);
    } else {
      (slices[file.name] ??= {})[file.arch!] = file.bytes;
    }
  }
  for (final MapEntry(key: name, value: byArch) in slices.entries) {
    await _lipo(outDir, name, byArch);
  }

  final names = {for (final f in files) f.name}.toList()..sort();
  stdout.writeln(
    'Binaries for $platform in ${outDir.path}: ${names.join(', ')}',
  );
  if (args.contains('--smoke')) await _smoke(outDir, names);
}

Future<void> _writeExecutable(File file, List<int> content) async {
  await file.writeAsBytes(content, flush: true);
  if (!Platform.isWindows) await exec('chmod', ['755', file.path]);
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
    await exec('lipo', ['-create', ...inputs, '-output', out]);
    await exec('chmod', ['755', out]);
    final archs = (await exec('lipo', ['-archs', out])).trim().split(' ');
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
    final out = await exec('${outDir.path}/$name', [flag]);
    stdout.writeln('$name: ${out.split('\n').first.trim()}');
  }
}
