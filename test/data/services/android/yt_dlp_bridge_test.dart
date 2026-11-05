import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/data/services/android/yt_dlp_bridge.dart';
import 'package:ftube/domain/exceptions/ftube_exception.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('io.github.infvyr.ftube/ytdlp');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  /// Sends a `line` call from the platform side, like YtDlpChannel.kt.
  Future<void> sendLine(String id, String line) =>
      messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('line', {'id': id, 'line': line}),
        ),
        (_) {},
      );

  late ChannelYtDlpBridge bridge;

  setUp(() {
    calls.clear();
    bridge = ChannelYtDlpBridge();
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  void answer(Future<Object?> Function(MethodCall call) handler) =>
      messenger.setMockMethodCallHandler(channel, (call) {
        calls.add(call);
        return handler(call);
      });

  test('version and update return the version', () async {
    answer((call) async => call.method == 'version' ? '2025.11.12' : '2026.1');
    expect(await bridge.version(), '2025.11.12');
    expect(await bridge.update(), '2026.1');
    expect(calls.map((c) => c.method), ['version', 'update']);
  });

  test('run sends id and args and routes lines by id', () async {
    final a = <String>[];
    final b = <String>[];
    answer((call) async {
      final id = (call.arguments as Map)['id'] as String;
      await sendLine(id, 'line for $id');
      await sendLine('other', 'stray');
      return {'exitCode': 0, 'stderr': '', 'cancelled': false};
    });
    final r = await bridge.run('a', ['-J', '--', 'u'], onLine: a.add);
    await bridge.run('b', ['x'], onLine: b.add);
    expect(r.exitCode, 0);
    expect(r.cancelled, isFalse);
    expect(a, ['line for a']);
    expect(b, ['line for b']);
    expect(calls.first.arguments, {
      'id': 'a',
      'args': ['-J', '--', 'u'],
    });

    // The listener is gone after the run.
    await sendLine('a', 'late');
    expect(a, ['line for a']);
  });

  test('run reads a failure and a cancel', () async {
    answer((call) async => {'exitCode': 1, 'stderr': 'ERROR: 403'});
    final failed = await bridge.run('a', ['u']);
    expect(failed.exitCode, 1);
    expect(failed.stderr, 'ERROR: 403');

    answer((call) async => {'exitCode': -1, 'cancelled': true});
    expect((await bridge.run('a', ['u'])).cancelled, isTrue);

    answer((call) async => null);
    expect((await bridge.run('a', ['u'])).exitCode, -1);
  });

  test('cancel sends the id', () async {
    answer((call) async => true);
    await bridge.cancel('j1');
    expect(calls.single.method, 'cancel');
    expect(calls.single.arguments, {'id': 'j1'});
  });

  test('a platform error becomes Unexpected', () async {
    answer((call) async => throw PlatformException(code: 'ytdlp_failed'));
    expect(
      bridge.update(),
      throwsA(
        isA<Unexpected>().having(
          (e) => e.toString(),
          'message',
          contains('ytdlp_failed'),
        ),
      ),
    );
  });

  test('ignores unknown calls and lines without a listener', () async {
    await sendLine('nobody', 'x');
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(const MethodCall('other')),
      (_) {},
    );
  });
}
