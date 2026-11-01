import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/data/services/android/android_file_launcher.dart';
import 'package:ftube/domain/exceptions/ftube_exception.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const launcher = AndroidFileLauncher();
  late List<MethodCall> calls;
  Object? error;

  setUp(() {
    calls = [];
    error = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidFileLauncher.channel, (call) async {
          calls.add(call);
          if (error case final e?) throw e;
          return null;
        });
  });

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidFileLauncher.channel, null),
  );

  test('open and share pass the path', () async {
    await launcher.open('/d/a.mp4');
    await launcher.share('/d/b.mp3');
    expect(calls.map((c) => '${c.method} ${c.arguments}'), [
      'open {path: /d/a.mp4}',
      'share {path: /d/b.mp3}',
    ]);
  });

  test('no app for the file is Unsupported', () async {
    error = PlatformException(code: 'no_app');
    await expectLater(launcher.open('/d/a.mp4'), throwsA(isA<Unsupported>()));
  });

  test('other platform errors are FileError', () async {
    error = PlatformException(code: 'not_found', message: '/d/a.mp4');
    await expectLater(launcher.share('/d/a.mp4'), throwsA(isA<FileError>()));
  });

  test('a missing channel is Unsupported', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidFileLauncher.channel, null);
    await expectLater(launcher.open('/d/a.mp4'), throwsA(isA<Unsupported>()));
  });
}
