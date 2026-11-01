/// Line coverage from an lcov file, limited to the files the coverage gate
/// covers (docs/spec.md section 6).
library;

/// Whether [path] counts toward the gate: hand-written code in `lib/data/`
/// and in `lib/ui/**/view_model*`.
bool gated(String path) {
  final p = path.replaceAll(r'\', '/');
  if (p.endsWith('.g.dart') || p.endsWith('.freezed.dart')) return false;
  return p.startsWith('lib/data/') ||
      (p.startsWith('lib/ui/') && p.contains('/view_model'));
}

/// Lines found and hit in the gated files of [lcov].
({int found, int hit}) gatedLines(String lcov) {
  var found = 0;
  var hit = 0;
  var counting = false;
  for (final line in lcov.split('\n')) {
    if (line.startsWith('SF:')) {
      counting = gated(line.substring(3).trim());
    } else if (counting && line.startsWith('DA:')) {
      final parts = line.substring(3).split(',');
      found++;
      if ((int.tryParse(parts[1].trim()) ?? 0) > 0) hit++;
    } else if (line.startsWith('end_of_record')) {
      counting = false;
    }
  }
  return (found: found, hit: hit);
}
