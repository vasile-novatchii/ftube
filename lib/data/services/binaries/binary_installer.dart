import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../domain/exceptions/ftube_exception.dart';
import '../binary_service.dart';
import '../process_runner.dart';
import 'binary_catalog.dart';

/// What the installer is doing with [InstallProgress.binary].
enum InstallPhase { downloading, unpacking }

/// Progress of [BinaryInstaller.install], in bytes over everything missing.
final class InstallProgress {
  const InstallProgress({
    required this.binary,
    required this.phase,
    required this.receivedBytes,
    required this.totalBytes,
  });

  final Binary binary;
  final InstallPhase phase;
  final int receivedBytes;
  final int totalBytes;

  double get fraction =>
      totalBytes == 0 ? 1 : (receivedBytes / totalBytes).clamp(0.0, 1.0);

  @override
  String toString() =>
      'InstallProgress(${binary.label}, ${phase.name}, '
      '$receivedBytes/$totalBytes)';
}

/// Downloads, verifies and unpacks the desktop binaries on first launch
/// (spec D-18).
///
/// `binDir/installed.json` maps each file name to the catalog SHA-256 it
/// was installed from. A binary is installed when its file exists and the
/// stamp matches the catalog, so a catalog change reinstalls it.
class BinaryInstaller {
  BinaryInstaller({
    required this._catalog,
    required this.os,
    required this.arch,
    required this.binDir,
    required this._runner,
    HttpClient Function()? httpClient,
  }) : _httpClient = httpClient ?? HttpClient.new;

  final BinaryCatalog _catalog;
  final DesktopOs os;

  /// Host CPU, or null when no binaries are published for it.
  final CpuArch? arch;

  final Directory binDir;
  final ProcessRunner _runner;
  final HttpClient Function() _httpClient;

  static const stampName = 'installed.json';

  /// Progress is reported at most once per this many bytes.
  static const progressStep = 1 << 20;

  File get _stamp => File(p.join(binDir.path, stampName));

  File _target(CatalogEntry e) =>
      File(p.join(binDir.path, e.binary.fileName(os)));

  /// The catalog entries for this OS and CPU. Throws [Unsupported] when
  /// there are none.
  List<CatalogEntry> get entries {
    final a = arch;
    final list = a == null
        ? const <CatalogEntry>[]
        : _catalog.entriesFor(os, a);
    if (list.isEmpty) {
      throw Unsupported('no binaries for ${os.name} ${a?.name ?? 'this CPU'}');
    }
    return list;
  }

  /// Entries that are not installed or were installed from an older catalog.
  Future<List<CatalogEntry>> missing() async {
    final stamp = await _readStamp();
    return [
      for (final e in entries)
        if (!_target(e).existsSync() ||
            stamp[e.binary.fileName(os)] != e.sha256)
          e,
    ];
  }

  /// Installs every [missing] binary, one at a time.
  ///
  /// Errors are [Network], [ChecksumMismatch] or [ProcessFailed] (chmod).
  /// Cancelling the subscription stops the download. Nothing partial is
  /// left behind in either case, and binaries finished so far stay
  /// installed.
  Stream<InstallProgress> install() async* {
    final todo = await missing();
    if (todo.isEmpty) return;
    await binDir.create(recursive: true);
    final total = todo.fold(0, (sum, e) => sum + e.size);
    var done = 0;
    final client = _httpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..userAgent = 'Ftube';
    try {
      for (final entry in todo) {
        final target = _target(entry);
        final part = File('${target.path}.gz.part');
        final tmp = File('${target.path}.tmp');
        try {
          final response = await _get(client, entry);
          final digest = _DigestSink();
          final hasher = sha256.startChunkedConversion(digest);
          final sink = part.openWrite();
          var received = 0;
          var reported = 0;
          try {
            await for (final chunk in response) {
              sink.add(chunk);
              hasher.add(chunk);
              received += chunk.length;
              if (received - reported >= progressStep) {
                reported = received;
                yield InstallProgress(
                  binary: entry.binary,
                  phase: InstallPhase.downloading,
                  receivedBytes: done + math.min(received, entry.size),
                  totalBytes: total,
                );
              }
            }
          } finally {
            await sink.close();
          }
          hasher.close();
          if (digest.value.toString() != entry.sha256) {
            throw ChecksumMismatch(entry.binary.label);
          }

          yield InstallProgress(
            binary: entry.binary,
            phase: InstallPhase.unpacking,
            receivedBytes: done + entry.size,
            totalBytes: total,
          );
          await part.openRead().transform(gzip.decoder).pipe(tmp.openWrite());
          if (target.existsSync()) await target.delete();
          await tmp.rename(target.path);
          if (os != DesktopOs.windows) {
            final out = await _runner.run('chmod', ['755', target.path]);
            if (out.exitCode != 0) {
              throw ProcessFailed.fromStderr(out.exitCode, out.stderr);
            }
          }
          await _writeStamp(entry);
          done += entry.size;
        } finally {
          for (final f in [part, tmp]) {
            if (f.existsSync()) await f.delete();
          }
        }
      }
    } on SocketException catch (e) {
      throw Network('$e');
    } on HttpException catch (e) {
      throw Network('$e');
    } on TlsException catch (e) {
      throw Network('$e');
    } finally {
      client.close(force: true);
    }
  }

  Future<HttpClientResponse> _get(HttpClient client, CatalogEntry e) async {
    final response = await (await client.getUrl(e.url)).close();
    if (response.statusCode != HttpStatus.ok) {
      throw Network('HTTP ${response.statusCode} for ${e.url}');
    }
    return response;
  }

  Future<Map<String, Object?>> _readStamp() async {
    if (!_stamp.existsSync()) return {};
    try {
      final Object? json = jsonDecode(await _stamp.readAsString());
      return json is Map<String, Object?> ? json : {};
    } on FormatException {
      return {};
    }
  }

  Future<void> _writeStamp(CatalogEntry e) async {
    final stamp = await _readStamp();
    stamp[e.binary.fileName(os)] = e.sha256;
    final tmp = File('${_stamp.path}.tmp');
    await tmp.writeAsString(jsonEncode(stamp), flush: true);
    if (_stamp.existsSync()) await _stamp.delete();
    await tmp.rename(_stamp.path);
  }
}

final class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
