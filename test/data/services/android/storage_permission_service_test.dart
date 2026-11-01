import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/data/services/android/storage_permission_service.dart';
import 'package:ftube/domain/exceptions/ftube_exception.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
  // permission_handler's PermissionStatus indexes.
  const denied = 0, granted = 1, restricted = 2, permanentlyDenied = 4;
  const manageExternalStorage = 22;

  late int status;
  late int requestResult;
  late List<MethodCall> permissionCalls;
  late List<MethodCall> storageCalls;
  Object? storageResult;
  late TestDefaultBinaryMessengerBinding binding;

  const service = StoragePermissionService();

  setUp(() {
    binding = TestDefaultBinaryMessengerBinding.instance;
    status = denied;
    requestResult = granted;
    permissionCalls = [];
    storageCalls = [];
    storageResult = '/storage/emulated/0/Download';
    binding.defaultBinaryMessenger
      ..setMockMethodCallHandler(permissions, (call) async {
        permissionCalls.add(call);
        return switch (call.method) {
          'checkPermissionStatus' => status,
          'requestPermissions' => {manageExternalStorage: requestResult},
          'openAppSettings' => true,
          _ => null,
        };
      })
      ..setMockMethodCallHandler(StoragePermissionService.channel, (
        call,
      ) async {
        storageCalls.add(call);
        if (storageResult case final PlatformException e) throw e;
        return storageResult;
      });
  });

  tearDown(() {
    binding.defaultBinaryMessenger
      ..setMockMethodCallHandler(permissions, null)
      ..setMockMethodCallHandler(StoragePermissionService.channel, null);
  });

  group('status', () {
    test('maps every permission status', () async {
      final cases = {
        granted: StorageAccess.granted,
        denied: StorageAccess.denied,
        permanentlyDenied: StorageAccess.permanentlyDenied,
        restricted: StorageAccess.permanentlyDenied,
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        status = key;
        expect(await service.status(), value, reason: '$key');
      }
      expect(permissionCalls.first.arguments, manageExternalStorage);
    });

    test('ensureGranted throws StoragePermission unless granted', () async {
      status = permanentlyDenied;
      await expectLater(
        service.ensureGranted(),
        throwsA(isA<StoragePermission>()),
      );
      status = granted;
      await service.ensureGranted();
    });
  });

  group('request', () {
    test('returns the status after the user comes back', () async {
      requestResult = granted;
      expect(await service.request(), StorageAccess.granted);
      requestResult = denied;
      expect(await service.request(), StorageAccess.denied);
      requestResult = permanentlyDenied;
      expect(await service.request(), StorageAccess.permanentlyDenied);
      expect(
        permissionCalls
            .where((c) => c.method == 'requestPermissions')
            .first
            .arguments,
        [manageExternalStorage],
      );
    });

    test('openSettings opens the app settings', () async {
      expect(await service.openSettings(), isTrue);
      expect(permissionCalls.single.method, 'openAppSettings');
    });
  });

  group('downloadsDir', () {
    test('is Ftube under the public Downloads folder', () async {
      final dir = await service.downloadsDir();
      expect(dir.path, '/storage/emulated/0/Download/Ftube');
      expect(storageCalls.single.method, 'downloadsDir');
    });

    test('throws StoragePermission when the folder is unknown', () async {
      for (final result in [
        null,
        '',
        PlatformException(code: 'x', message: 'no storage'),
      ]) {
        storageResult = result;
        await expectLater(
          service.downloadsDir(),
          throwsA(isA<StoragePermission>()),
          reason: '$result',
        );
      }
    });
  });

  group('scanFile', () {
    test('sends the path', () async {
      storageResult = null;
      await service.scanFile('/storage/emulated/0/Download/Ftube/a.mp4');
      expect(storageCalls.single.method, 'scanFile');
      expect(storageCalls.single.arguments, {
        'path': '/storage/emulated/0/Download/Ftube/a.mp4',
      });
    });

    test('ignores platform errors', () async {
      storageResult = PlatformException(code: 'x');
      await service.scanFile('/a.mp4');
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        StoragePermissionService.channel,
        null,
      );
      await service.scanFile('/a.mp4');
    });
  });
}
