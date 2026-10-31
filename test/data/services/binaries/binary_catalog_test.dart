import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/data/services/binaries/binary_catalog.dart';
import 'package:ftube/data/services/binary_service.dart';

void main() {
  group('assets/binaries/catalog.json', () {
    final catalog = BinaryCatalog.parse(
      File('assets/binaries/catalog.json').readAsStringSync(),
    );

    test('every supported OS and CPU gets all four binaries', () {
      for (final (os, arch) in [
        (DesktopOs.macos, CpuArch.arm64),
        (DesktopOs.macos, CpuArch.x86_64),
        (DesktopOs.windows, CpuArch.x86_64),
        (DesktopOs.linux, CpuArch.x86_64),
      ]) {
        expect(
          catalog.entriesFor(os, arch).map((e) => e.binary).toSet(),
          Binary.values.toSet(),
          reason: '${os.name} ${arch.name}',
        );
      }
      expect(catalog.entriesFor(DesktopOs.windows, CpuArch.arm64), isEmpty);
      expect(catalog.entriesFor(DesktopOs.linux, CpuArch.arm64), isEmpty);
    });

    test('files come from the catalog release of the ftube repo', () {
      expect(catalog.release, matches(RegExp(r'^binaries-r\d+$')));
      for (final e in catalog.entries) {
        expect(
          '${e.url}',
          startsWith(
            'https://github.com/vasile-novatchii/ftube/releases/download/'
            '${catalog.release}/',
          ),
        );
      }
    });

    test('the universal yt-dlp serves both Mac CPUs', () {
      CatalogEntry yt(CpuArch a) => catalog
          .entriesFor(DesktopOs.macos, a)
          .firstWhere((e) => e.binary == Binary.ytDlp);
      expect(yt(CpuArch.arm64).url, yt(CpuArch.x86_64).url);
      expect(yt(CpuArch.arm64).sha256, yt(CpuArch.x86_64).sha256);
    });

    test('round-trips through toJson', () {
      final again = BinaryCatalog.parse(catalog.toJson());
      expect(again.toJson(), catalog.toJson());
    });
  });

  group('parse', () {
    Map<String, Object?> entry() => {
      'binary': 'ffmpeg',
      'os': 'linux',
      'arch': 'x86_64',
      'url': 'https://x.test/ffmpeg.gz',
      'sha256': 'a' * 64,
      'size': 10,
    };
    String doc(List<Map<String, Object?>> entries, {Object? release = 'r'}) =>
        jsonEncode({'release': release, 'entries': entries});

    test('parses a valid entry', () {
      final e = BinaryCatalog.parse(doc([entry()])).entries.single;
      expect(e.binary, Binary.ffmpeg);
      expect(e.os, DesktopOs.linux);
      expect(e.arch, CpuArch.x86_64);
      expect(e.size, 10);
    });

    test('rejects bad input', () {
      Map<String, Object?> with_(String k, Object? v) => entry()..[k] = v;
      for (final bad in [
        'nope',
        '[]',
        doc([entry()], release: ''),
        jsonEncode({'release': 'r', 'entries': 1}),
        doc([with_('url', 'http://x.test/f.gz')]),
        doc([with_('sha256', 'A' * 64)]),
        doc([with_('size', 0)]),
        doc([with_('binary', 'ffplay')]),
        doc([with_('os', 'beos')]),
        doc([with_('arch', 'riscv')]),
        doc([entry(), entry()]),
      ]) {
        expect(
          () => BinaryCatalog.parse(bad),
          throwsA(isA<CatalogException>()),
          reason: bad,
        );
      }
    });
  });

  test('CpuArch.fromAbi maps the supported hosts only', () {
    expect(CpuArch.fromAbi(Abi.macosArm64), CpuArch.arm64);
    expect(CpuArch.fromAbi(Abi.macosX64), CpuArch.x86_64);
    expect(CpuArch.fromAbi(Abi.windowsX64), CpuArch.x86_64);
    expect(CpuArch.fromAbi(Abi.linuxX64), CpuArch.x86_64);
    expect(CpuArch.fromAbi(Abi.linuxArm64), isNull);
    expect(CpuArch.fromAbi(Abi.windowsArm64), isNull);
  });
}
