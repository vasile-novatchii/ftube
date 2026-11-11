import 'package:flutter/services.dart';

import '../../../domain/models/app_update.dart';
import 'background_downloads.dart';

/// Posts the Android "new version" notification through
/// `DownloadsChannel.kt` (docs/spec-v0.6.md D-93).
class AndroidUpdateNotifier {
  const AndroidUpdateNotifier([this._channel = BackgroundDownloads.channel]);

  final MethodChannel _channel;

  /// Returns whether the notification was posted; false when notifications
  /// are off or the channel is missing.
  Future<bool> notify(
    AppRelease release, {
    required String title,
    required String text,
    required String channelName,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('updateAvailable', {
            'url': release.pageUrl.toString(),
            'title': title,
            'text': text,
            'channel': channelName,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
