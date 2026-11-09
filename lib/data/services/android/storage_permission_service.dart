import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

import '../../../domain/exceptions/ftube_exception.dart';

/// Whether Ftube may read and write the public `Download/Ftube` folder.
enum StorageAccess {
  granted,

  /// Not granted yet; [StoragePermissionService.request] may ask again.
  denied,

  /// Refused for good; only the system settings can grant it.
  permanentlyDenied,
}

/// Android "All files access" (`MANAGE_EXTERNAL_STORAGE`) and the public
/// Downloads folder (spec D-13).
class StoragePermissionService {
  const StoragePermissionService();

  /// Channel implemented in `FtubeApplication.kt`.
  static const channel = MethodChannel('io.github.infvyr.ftube/storage');

  /// Folder name under the public Downloads folder.
  static const folderName = 'Ftube';

  static const _permission = Permission.manageExternalStorage;

  Future<StorageAccess> status() async => _map(await _permission.status);

  /// Opens the system "All files access" screen and returns the status once
  /// the user comes back.
  Future<StorageAccess> request() async => _map(await _permission.request());

  /// Opens Ftube's page in the system settings.
  Future<bool> openSettings() => openAppSettings();

  /// Throws [StoragePermission] unless access is granted.
  Future<void> ensureGranted() async {
    final access = await status();
    if (access != StorageAccess.granted) throw StoragePermission(access.name);
  }

  /// The public `Download/Ftube` folder. It is not created here.
  Future<Directory> downloadsDir() async {
    final String? path;
    try {
      path = await channel.invokeMethod<String>('downloadsDir');
    } on PlatformException catch (e) {
      throw StoragePermission(e.message);
    }
    if (path == null || path.isEmpty) {
      throw const StoragePermission('no public Downloads folder');
    }
    return Directory(p.join(path, folderName));
  }

  /// Announces a new or changed file to the gallery and media apps.
  /// Failures are ignored: the file is there either way.
  Future<void> scanFile(String path) async {
    try {
      await channel.invokeMethod<void>('scanFile', {'path': path});
    } on PlatformException {
      // Best effort.
    } on MissingPluginException {
      // Best effort.
    }
  }

  static StorageAccess _map(PermissionStatus s) => switch (s) {
    PermissionStatus.granted ||
    PermissionStatus.limited => StorageAccess.granted,
    PermissionStatus.permanentlyDenied ||
    PermissionStatus.restricted => StorageAccess.permanentlyDenied,
    PermissionStatus.denied ||
    PermissionStatus.provisional => StorageAccess.denied,
  };
}
