// Prints the CHANGELOG.md section for a version, for the GitHub release
// notes (docs/spec-v0.6.md D-101). Fails when the section is missing.
//
//   dart tool/changelog_section.dart 0.6.0 [CHANGELOG.md]
import 'dart:io';

import 'src/changelog.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart tool/changelog_section.dart <version> [file]');
    exitCode = 64;
    return;
  }
  final version = args.first;
  final file = File(args.length > 1 ? args[1] : 'CHANGELOG.md');
  final section = file.existsSync()
      ? changelogSection(file.readAsStringSync(), version)
      : null;
  if (section == null) {
    stderr.writeln('${file.path} has no "## $version" section');
    exitCode = 1;
    return;
  }
  stdout.writeln(section);
}
