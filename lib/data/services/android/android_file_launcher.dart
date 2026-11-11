import 'package:flutter/services.dart';

import '../../../domain/exceptions/ftube_exception.dart';

/// Opens and shares files on Android through a `FileProvider` content URI.
class AndroidFileLauncher {
  const AndroidFileLauncher();

  /// Channel implemented in `MainActivity.kt`.
  static const channel = MethodChannel('io.github.infvyr.ftube/files');

  /// Opens [path] with the app the user picks for its type.
  Future<void> open(String path) => _call('open', path);

  /// Shows the system share sheet for [path].
  Future<void> share(String path) => _call('share', path);

  /// Opens a web [url] in the browser (docs/spec-v0.6.md D-94).
  Future<void> openUrl(String url) => _call('openUrl', url, key: 'url');

  Future<void> _call(String method, String path, {String key = 'path'}) async {
    try {
      await channel.invokeMethod<void>(method, {key: path});
    } on PlatformException catch (e) {
      throw switch (e.code) {
        'no_app' => Unsupported('$method: no app for $path'),
        _ => FileError('$method ${e.code}: ${e.message ?? path}'),
      };
    } on MissingPluginException {
      throw Unsupported('$method on this platform');
    }
  }
}
