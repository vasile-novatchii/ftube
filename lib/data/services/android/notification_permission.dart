import 'package:permission_handler/permission_handler.dart';

import '../prefs_service.dart';

/// Android 13+ notification permission, asked once on the first download
/// (spec-v0.4 D-44). Downloads run whether it is granted or not.
class NotificationPermission {
  const NotificationPermission(this._prefs);

  final PrefsService _prefs;

  static const askedKey = 'notifications.asked';

  /// Asks for the permission unless it was asked before.
  Future<void> requestOnce() async {
    if (_prefs.getBool(askedKey) ?? false) return;
    await _prefs.setBool(askedKey, value: true);
    try {
      await Permission.notification.request();
    } on Object {
      // No activity to ask from, or the plugin is missing: try no more.
    }
  }
}
