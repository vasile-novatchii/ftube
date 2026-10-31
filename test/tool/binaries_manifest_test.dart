import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/binaries_manifest.dart';

void main() {
  group('tool/binaries.yaml', () {
    final manifest = parseManifest(
      File('tool/binaries.yaml').readAsStringSync(),
    );

    test('every platform yields yt-dlp, ffmpeg, ffprobe and deno', () {
      final expected = {
        'macos': {'yt-dlp_macos', 'ffmpeg', 'ffprobe', 'deno'},
        'windows': {'yt-dlp.exe', 'ffmpeg.exe', 'ffprobe.exe', 'deno.exe'},
        'linux': {'yt-dlp_linux', 'ffmpeg', 'ffprobe', 'deno'},
      };
      expect(manifest.keys.toSet(), expected.keys.toSet());
      for (final MapEntry(key: platform, value: names) in expected.entries) {
        expect(
          {for (final a in manifest[platform]!) ...a.files.values},
          names,
          reason: platform,
        );
      }
    });

    test('macOS slices come in arm64 + x86_64 pairs (D-14)', () {
      final byName = <String, Set<String>>{};
      for (final a in manifest['macos']!.where((a) => a.arch != null)) {
        for (final name in a.files.values) {
          (byName[name] ??= {}).add(a.arch!);
        }
      }
      expect(byName.keys.toSet(), {'ffmpeg', 'ffprobe', 'deno'});
      expect(byName.values, everyElement({'arm64', 'x86_64'}));
    });

    test('Windows and Linux have no arch slices', () {
      for (final platform in ['windows', 'linux']) {
        expect(manifest[platform]!.map((a) => a.arch), everyElement(isNull));
      }
    });
  });

  group('parseManifest', () {
    final valid =
        '''
linux:
  - url: https://x.test/tool.zip
    sha256: ${'a' * 64}
    files: { bin/tool: tool }
''';

    test('parses a valid entry', () {
      final a = parseManifest(valid)['linux']!.single;
      expect(a.url.toString(), 'https://x.test/tool.zip');
      expect(a.kind, ArchiveKind.zip);
      expect(a.files, {'bin/tool': 'tool'});
      expect(a.arch, isNull);
    });

    test('rejects bad input', () {
      for (final bad in [
        '- a',
        'beos: []',
        'linux: {}',
        valid.replaceFirst('https', 'http'),
        valid.replaceFirst('a' * 64, 'A' * 64),
        valid.replaceFirst('a' * 64, 'abc'),
        valid.replaceFirst('{ bin/tool: tool }', '{}'),
        valid.replaceFirst('tool.zip', 'tool').replaceFirst('bin/tool', 'x'),
      ]) {
        expect(
          () => parseManifest(bad),
          throwsA(isA<ManifestException>()),
          reason: bad,
        );
      }
    });

    test('detects the archive kind from the file name', () {
      Artifact a(String name) => Artifact(
        url: Uri.parse('https://x.test/$name'),
        sha256: '',
        files: const {},
      );
      expect(a('f.zip').kind, ArchiveKind.zip);
      expect(a('f.tar.xz').kind, ArchiveKind.tarXz);
      expect(a('yt-dlp_linux').kind, ArchiveKind.plain);
    });
  });

  group('checksums and extraction', () {
    final payload = Uint8List.fromList(utf8.encode('binary'));

    Artifact artifact(String name, Map<String, String> files) => Artifact(
      url: Uri.parse('https://x.test/$name'),
      sha256: sha256Hex(payload),
      files: files,
    );

    test('sha256Hex matches a known vector', () {
      expect(
        sha256Hex(utf8.encode('abc')),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('verifyChecksum rejects other bytes', () {
      final a = artifact('t', const {'.': 't'});
      verifyChecksum(a, payload);
      expect(
        () => verifyChecksum(a, [1, 2, 3]),
        throwsA(isA<ManifestException>()),
      );
    });

    test('plain files pass through under their output name', () {
      final files = extractFiles(artifact('t', const {'.': 'tool'}), payload);
      expect(files, {'tool': payload});
    });

    Uint8List archiveWith(String member) => Uint8List.fromList(
      ZipEncoder().encode(
        Archive()..addFile(ArchiveFile.bytes(member, payload)),
      ),
    );

    test('zip members are extracted and renamed', () {
      final zip = archiveWith('dir/bin/tool');
      final files = extractFiles(
        artifact('t.zip', const {'dir/bin/tool': 'tool'}),
        zip,
      );
      expect(files['tool'], payload);
    });

    test('tar.xz members are extracted', () {
      final tar = TarEncoder().encode(
        Archive()..addFile(ArchiveFile.bytes('d/ffmpeg', payload)),
      );
      final xz = XZEncoder().encodeBytes(tar);
      final files = extractFiles(
        artifact('t.tar.xz', const {'d/ffmpeg': 'ffmpeg'}),
        Uint8List.fromList(xz),
      );
      expect(files['ffmpeg'], payload);
    });

    test('a missing member is an error', () {
      expect(
        () => extractFiles(
          artifact('t.zip', const {'nope': 'x'}),
          archiveWith('other'),
        ),
        throwsA(isA<ManifestException>()),
      );
    });
  });
}
