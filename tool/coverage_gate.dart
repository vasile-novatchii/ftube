// Fails when line coverage of lib/data/ and lib/ui/**/view_model* is below
// the minimum (docs/spec.md section 6).
//
//   flutter test --coverage
//   dart run tool/coverage_gate.dart [--min 85] [--lcov coverage/lcov.info]
import 'dart:io';

import 'src/coverage.dart';

void main(List<String> args) {
  String? option(String name) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final min = double.parse(option('--min') ?? '85');
  final file = File(option('--lcov') ?? 'coverage/lcov.info');
  if (!file.existsSync()) {
    stderr.writeln('coverage_gate: ${file.path} not found');
    exitCode = 1;
    return;
  }
  final (:found, :hit) = gatedLines(file.readAsStringSync());
  if (found == 0) {
    stderr.writeln('coverage_gate: no gated lines in ${file.path}');
    exitCode = 1;
    return;
  }
  final percent = hit * 100 / found;
  stdout.writeln(
    'Gated line coverage: ${percent.toStringAsFixed(1)}% '
    '($hit of $found lines, minimum $min%)',
  );
  if (percent < min) exitCode = 1;
}
