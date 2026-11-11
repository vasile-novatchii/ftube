import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import '../../tool/src/changelog.dart';

const _changelog = '''
# Changelog

## Unreleased

### Added
- Next

## 0.6.0 - 2026-11-20

### Added
- Update notice

### Fixed
- A bug

## 0.5.0
- Playlists

## 0.4.0 - 2026-11-10

## 0.3.0 - 2026-11-05
- Old
''';

void main() {
  group('changelogSection (D-101)', () {
    test('returns the body up to the next version', () {
      expect(
        changelogSection(_changelog, '0.6.0'),
        '### Added\n- Update notice\n\n### Fixed\n- A bug',
      );
      expect(changelogSection(_changelog, '0.5.0'), '- Playlists');
      expect(changelogSection(_changelog, '0.3.0'), '- Old');
    });

    test('a missing or empty section is null', () {
      expect(changelogSection(_changelog, '0.4.0'), isNull);
      expect(changelogSection(_changelog, '0.7.0'), isNull);
      expect(changelogSection(_changelog, '0.6'), isNull);
      expect(changelogSection(_changelog, '0.6.0.1'), isNull);
      expect(changelogSection('', '0.6.0'), isNull);
    });

    test('version dots are literal and CRLF files work', () {
      expect(changelogSection('## 0x6y0\n- x', '0.6.0'), isNull);
      expect(changelogSection('## 0.6.0\r\n- x\r\n', '0.6.0'), '- x');
    });
  });

  test('CHANGELOG.md has an entry for the pubspec version (D-102)', () {
    final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as Map;
    final version = (pubspec['version'] as String).split('+').first;
    expect(
      changelogSection(File('CHANGELOG.md').readAsStringSync(), version),
      isNotNull,
      reason: 'Add a "## $version - YYYY-MM-DD" section to CHANGELOG.md',
    );
  });
}
