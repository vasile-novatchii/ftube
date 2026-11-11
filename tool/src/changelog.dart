/// The body of the `## <version>` section of a CHANGELOG.md, without its
/// heading and trimmed, or null when the section is missing or empty
/// (docs/spec-v0.6.md D-101). The heading may carry a date:
/// `## 0.6.0 - 2026-11-20`.
String? changelogSection(String changelog, String version) {
  final heading = RegExp('^## ${RegExp.escape(version)}(\\s|\$)');
  final lines = changelog.replaceAll('\r\n', '\n').split('\n');
  final start = lines.indexWhere(heading.hasMatch);
  if (start < 0) return null;
  final rest = lines.skip(start + 1);
  final body = rest.takeWhile((l) => !l.startsWith('## ')).join('\n').trim();
  return body.isEmpty ? null : body;
}
