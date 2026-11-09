import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/data/services/android/notification_permission.dart';

import '../../../ui/helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter.baseflow.com/permissions/methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('asks once, then never again', () async {
    var requests = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'requestPermissions') requests++;
      return {17: 0};
    });
    final prefs = await testPrefs();
    final permission = NotificationPermission(prefs);

    await permission.requestOnce();
    await permission.requestOnce();
    expect(requests, 1);
    expect(prefs.getBool(NotificationPermission.askedKey), isTrue);
  });

  test('a failing plugin still counts as asked', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'no-activity'),
    );
    final prefs = await testPrefs();

    await NotificationPermission(prefs).requestOnce();
    expect(prefs.getBool(NotificationPermission.askedKey), isTrue);
  });

  test('skips when asked before', () async {
    var requests = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      requests++;
      return {17: 1};
    });
    final prefs = await testPrefs({NotificationPermission.askedKey: true});

    await NotificationPermission(prefs).requestOnce();
    expect(requests, 0);
  });
}
