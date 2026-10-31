import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/data/services/binaries/binary_catalog.dart';
import 'package:ftube/data/services/binaries/binary_installer.dart';
import 'package:ftube/data/services/binary_service.dart';
import 'package:ftube/data/services/process_runner.dart';
import 'package:ftube/domain/exceptions/ftube_exception.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;

import '../desktop/fakes.dart';

/// Serves gzip files from [files] on the loopback interface.
class _Server {
  _Server._(this._server) {
    _server.listen(_handle);
  }

  static Future<_Server> start() async =>
      _Server._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  final files = <String, List<int>>{};
  final redirects = <String, String>{};
  final requests = <String>[];

  /// When set, `/slow` sends half of its file and then waits for this.
  Completer<void>? slowGate;

  Uri url(String path) => Uri.parse('http://127.0.0.1:${_server.port}$path');

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    requests.add(path);
    final res = req.response;
    final to = redirects[path];
    if (to != null) {
      await res.redirect(url(to), status: HttpStatus.found);
      return;
    }
    final body = files[path];
    if (body == null) {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    res.contentLength = body.length;
    if (path == '/slow' && slowGate != null) {
      res.add(body.sublist(0, body.length ~/ 2));
      await res.flush();
      await slowGate!.future;
      res.add(body.sublist(body.length ~/ 2));
    } else {
      res.add(body);
    }
    await res.close();
  }

  Future<void> close() => _server.close(force: true);
}

void main() {
  late Directory root;
  late Directory bin;
  late _Server server;
  late MockProcessRunner runner;

  /// Raw binary contents, by binary.
  late Map<Binary, List<int>> contents;

  /// A catalog entry for [binary] served at [path], with [sha] overriding
  /// the real checksum.
  CatalogEntry entry(Binary binary, {String? path, String? sha}) {
    final gz = gzip.encode(contents[binary]!);
    final at = path ?? '/${binary.label}.gz';
    server.files.putIfAbsent(at, () => gz);
    return CatalogEntry(
      binary: binary,
      os: DesktopOs.linux,
      arch: CpuArch.x86_64,
      url: server.url(at),
      sha256: sha ?? sha256.convert(gz).toString(),
      size: gz.length,
    );
  }

  BinaryInstaller installer(
    List<CatalogEntry> entries, {
    DesktopOs os = DesktopOs.linux,
    CpuArch? arch = CpuArch.x86_64,
  }) => BinaryInstaller(
    catalog: BinaryCatalog(
      release: 'binaries-r1',
      entries: [
        for (final e in entries)
          CatalogEntry(
            binary: e.binary,
            os: os,
            arch: e.arch,
            url: e.url,
            sha256: e.sha256,
            size: e.size,
          ),
      ],
    ),
    os: os,
    arch: arch,
    binDir: bin,
    runner: runner,
  );

  List<CatalogEntry> all() => [for (final b in Binary.values) entry(b)];

  File installed(Binary b, [DesktopOs os = DesktopOs.linux]) =>
      File(p.join(bin.path, b.fileName(os)));

  /// Files in [bin] other than the binaries and the stamp.
  List<String> leftovers() => [
    for (final f in bin.existsSync() ? bin.listSync() : <FileSystemEntity>[])
      if (f.path.endsWith('.part') || f.path.endsWith('.tmp')) f.path,
  ];

  setUp(() async {
    // Random bytes do not compress, so the gzip stays about 3 MB.
    final random = Random(1);
    contents = {
      for (final b in Binary.values)
        // ffmpeg is large enough to report download progress in steps.
        b: b == Binary.ffmpeg
            ? List<int>.generate(3 << 20, (_) => random.nextInt(256))
            : utf8.encode('${b.label} payload'),
    };
    root = Directory.systemTemp.createTempSync('ftube_installer_test');
    bin = Directory(p.join(root.path, 'bin'));
    server = await _Server.start();
    runner = MockProcessRunner();
    when(() => runner.run('chmod', any()))
        .thenAnswer((_) async => const ProcessOutput(0, '', ''));
  });

  tearDown(() async {
    await server.close();
    root.deleteSync(recursive: true);
  });

  test('installs every missing binary and stamps it', () async {
    final entries = all();
    final i = installer(entries);
    expect(await i.missing(), hasLength(4));

    final events = await i.install().toList();

    for (final b in Binary.values) {
      expect(installed(b).readAsBytesSync(), contents[b], reason: b.label);
      verify(() => runner.run('chmod', ['755', installed(b).path])).called(1);
    }
    final stamp = jsonDecode(
      File(p.join(bin.path, BinaryInstaller.stampName)).readAsStringSync(),
    ) as Map<String, Object?>;
    expect(stamp, {for (final e in entries) e.binary.fileName(e.os): e.sha256});
    expect(await i.missing(), isEmpty);
    expect(leftovers(), isEmpty);

    final total = entries.fold(0, (s, e) => s + e.size);
    expect(events.map((e) => e.totalBytes).toSet(), {total});
    final received = events.map((e) => e.receivedBytes).toList();
    expect(received, orderedEquals([...received]..sort()));
    expect(events.last.fraction, 1);
    expect(
      events.where(
        (e) => e.binary == Binary.ffmpeg && e.phase == InstallPhase.downloading,
      ),
      isNotEmpty,
      reason: '3 MB is over the 1 MB progress step',
    );
    expect(
      events
          .where((e) => e.phase == InstallPhase.unpacking)
          .map((e) => e.binary),
      Binary.values,
    );
  });

  test('does nothing when everything is installed', () async {
    final i = installer(all());
    await i.install().drain<void>();
    server.requests.clear();

    expect(await i.install().toList(), isEmpty);
    expect(server.requests, isEmpty);
  });

  test('reinstalls a deleted binary or a changed catalog entry', () async {
    await installer(all()).install().drain<void>();
    installed(Binary.deno).deleteSync();
    server.requests.clear();

    await installer(all()).install().drain<void>();
    expect(server.requests, ['/deno.gz']);

    contents[Binary.ffprobe] = utf8.encode('ffprobe 2');
    server.files.remove('/ffprobe.gz');
    server.requests.clear();
    await installer(all()).install().drain<void>();
    expect(server.requests, ['/ffprobe.gz']);
    expect(installed(Binary.ffprobe).readAsStringSync(), 'ffprobe 2');
  });

  test('follows redirects, as GitHub release downloads do', () async {
    final e = entry(Binary.deno, path: '/real/deno.gz');
    server.redirects['/deno.gz'] = '/real/deno.gz';
    final redirected = CatalogEntry(
      binary: e.binary,
      os: e.os,
      arch: e.arch,
      url: server.url('/deno.gz'),
      sha256: e.sha256,
      size: e.size,
    );
    await installer([redirected]).install().drain<void>();
    expect(installed(Binary.deno).readAsBytesSync(), contents[Binary.deno]);
  });

  test('Windows needs no chmod', () async {
    await installer([
      entry(Binary.deno),
    ], os: DesktopOs.windows).install().drain<void>();
    expect(installed(Binary.deno, DesktopOs.windows).existsSync(), isTrue);
    verifyNever(() => runner.run(any(), any()));
  });

  test('HTTP errors become Network and keep finished binaries', () async {
    final missing = CatalogEntry(
      binary: Binary.deno,
      os: DesktopOs.linux,
      arch: CpuArch.x86_64,
      url: server.url('/nope.gz'),
      sha256: 'a' * 64,
      size: 1,
    );
    final i = installer([entry(Binary.ytDlp), missing]);
    await expectLater(
      i.install().drain<void>(),
      throwsA(
        isA<Network>().having((e) => e.detail, 'detail', contains('404')),
      ),
    );
    expect(installed(Binary.ytDlp).existsSync(), isTrue);
    expect(installed(Binary.deno).existsSync(), isFalse);
    expect((await i.missing()).map((e) => e.binary), [Binary.deno]);
    expect(leftovers(), isEmpty);
  });

  test('an unreachable server becomes Network', () async {
    final e = entry(Binary.deno);
    await server.close();
    await expectLater(
      installer([e]).install().drain<void>(),
      throwsA(isA<Network>()),
    );
    expect(leftovers(), isEmpty);
  });

  test('a checksum mismatch installs nothing', () async {
    await expectLater(
      installer([entry(Binary.ffmpeg, sha: 'b' * 64)]).install().drain<void>(),
      throwsA(
        isA<ChecksumMismatch>().having((e) => e.binary, 'binary', 'ffmpeg'),
      ),
    );
    expect(installed(Binary.ffmpeg).existsSync(), isFalse);
    expect(leftovers(), isEmpty);
    verifyNever(() => runner.run(any(), any()));
  });

  test('a failing chmod is ProcessFailed and not stamped', () async {
    when(() => runner.run('chmod', any()))
        .thenAnswer((_) async => const ProcessOutput(1, '', 'denied'));
    final i = installer([entry(Binary.deno)]);
    await expectLater(i.install().drain<void>(), throwsA(isA<ProcessFailed>()));
    expect(await i.missing(), hasLength(1));
  });

  test('cancelling stops the download and leaves no partial files', () async {
    final e = entry(Binary.ffmpeg, path: '/slow');
    server.slowGate = Completer<void>();
    final first = Completer<InstallProgress>();
    final sub = installer([e]).install().listen(first.complete);

    expect((await first.future).phase, InstallPhase.downloading);
    await sub.cancel();
    server.slowGate!.complete();

    expect(installed(Binary.ffmpeg).existsSync(), isFalse);
    expect(leftovers(), isEmpty);
  });

  test('unsupported hosts get Unsupported', () async {
    await expectLater(
      installer(all(), arch: null).missing(),
      throwsA(isA<Unsupported>()),
    );
    await expectLater(
      installer(all(), arch: CpuArch.arm64).install().drain<void>(),
      throwsA(isA<Unsupported>()),
    );
  });
}
