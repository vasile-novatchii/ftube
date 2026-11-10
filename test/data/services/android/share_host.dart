import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/data/services/android/share_link_service.dart';

/// Stands in for `ShareChannel.kt` and `ShareActivity.kt`.
class ShareHost {
  ShareHost({this.pending, this.subject});

  /// Text shared before Dart started; handed out once.
  String? pending;

  /// The title shared with [pending].
  String? subject;

  /// Like Android, ends the session once [ShareLinkService.close] or
  /// [ShareLinkService.openApp] closed the popup.
  bool dismissOnClose = true;

  /// Makes `close` and `openApp` fail.
  bool fail = false;

  final calls = <MethodCall>[];
  final service = ShareLinkService();

  static const _channel = ShareLinkService.channel;

  TestDefaultBinaryMessenger get _messenger =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void install() => _messenger.setMockMethodCallHandler(_channel, (call) async {
    calls.add(call);
    switch (call.method) {
      case 'pending':
        final text = pending;
        pending = null;
        return text == null ? null : {'text': text, 'subject': subject};
      case 'close' || 'openApp':
        if (fail) throw PlatformException(code: 'gone');
        if (dismissOnClose) await dismissed();
    }
    return null;
  });

  void uninstall() => _messenger.setMockMethodCallHandler(_channel, null);

  /// Shares [text] into the running app.
  Future<ByteData?> show(String? text) => send('show', {'text': text});

  /// The popup window was destroyed.
  Future<ByteData?> dismissed() => send('dismissed');

  Future<ByteData?> send(String method, [Object? args]) async {
    ByteData? reply;
    await _messenger.handlePlatformMessage(
      _channel.name,
      _channel.codec.encodeMethodCall(MethodCall(method, args)),
      (data) => reply = data,
    );
    return reply;
  }
}
