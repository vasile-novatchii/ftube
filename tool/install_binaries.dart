// Installs the binaries from assets/binaries/catalog.json the way the app
// does on first launch (spec D-18), then runs each one's version command.
//
//   dart run tool/install_binaries.dart [--dir <dir>]
//
// --dir defaults to build/installed. CI runs this on every OS after a
// binaries-rN release is published.
import 'dart:io';

import 'package:ftube/data/services/binaries/binary_catalog.dart';
import 'package:ftube/data/services/binaries/binary_installer.dart';
import 'package:ftube/data/services/binary_service.dart';
import 'package:ftube/data/services/process_runner.dart';

Future<void> main(List<String> args) async {
  try {
    await _run(args);
  } on Object catch (e) {
    stderr.writeln('install_binaries: $e');
    exitCode = 1;
  }
}

Future<void> _run(List<String> args) async {
  final i = args.indexOf('--dir');
  final dir = Directory(
    i >= 0 && i + 1 < args.length ? args[i + 1] : 'build/installed',
  );
  final os = DesktopOs.current ?? (throw UnsupportedError('not a desktop OS'));
  const runner = SystemProcessRunner();
  final installer = BinaryInstaller(
    catalog: BinaryCatalog.parse(
      await File('assets/binaries/catalog.json').readAsString(),
    ),
    os: os,
    arch: CpuArch.current,
    binDir: dir,
    runner: runner,
  );

  var lastPercent = -10;
  await for (final progress in installer.install()) {
    final percent = (progress.fraction * 100).floor();
    if (percent >= lastPercent + 10 ||
        progress.phase == InstallPhase.unpacking) {
      lastPercent = percent;
      stdout.writeln(
        '$percent% ${progress.phase.name} ${progress.binary.label}',
      );
    }
  }
  if ((await installer.missing()).isNotEmpty) {
    throw StateError('binaries still missing after install');
  }

  final service = BinaryService(os: os, binDir: dir, runner: runner);
  for (final binary in Binary.values) {
    final version = await service.version(binary);
    if (version == null) throw StateError('${binary.label} does not run');
    stdout.writeln('${binary.label}: $version');
  }
}
