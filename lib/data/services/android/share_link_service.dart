import 'dart:async';

import 'package:flutter/services.dart';

/// A share from another app (spec-v0.4-share). Each share is a new object,
/// so sharing the same link again still restarts the popup.
class ShareRequest {
  ShareRequest(String? text, {String? subject})
    : url = extractLink(text),
      subject = (subject?.trim().isEmpty ?? true) ? null : subject!.trim();

  /// The first http(s) link in the shared text, or null when it has none.
  final String? url;

  /// The shared title (`EXTRA_SUBJECT`), shown before yt-dlp has loaded
  /// (spec-v0.4-share D-63).
  final String? subject;
}

final _link = RegExp(r'https?://\S+', caseSensitive: false);
final _trailing = RegExp('''[.,;:!?)\\]}>»"'”’]+\$''');

/// The first http(s) link in [text], without the punctuation that often
/// follows it in a sentence. Apps share "Title https://..." or add text
/// around the link.
String? extractLink(String? text) {
  final match = text == null ? null : _link.firstMatch(text);
  if (match == null) return null;
  final url = match[0]!.replaceFirst(_trailing, '');
  return Uri.tryParse(url)?.host.isNotEmpty == true ? url : null;
}

final _youtubeId = RegExp(r'^[\w-]{11}$');

/// The thumbnail of a YouTube video link, derived from its id without a
/// network call (spec-v0.4-share D-64), or null for other links.
String? youtubeThumbnail(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^(www|m)\.'), '');
  final segments = uri.pathSegments;
  final id = switch (host) {
    'youtu.be' => segments.firstOrNull,
    'youtube.com' || 'music.youtube.com' => switch (segments) {
      ['watch', ...] => uri.queryParameters['v'],
      ['shorts' || 'live' || 'embed', final id, ...] => id,
      _ => null,
    },
    _ => null,
  };
  if (id == null || !_youtubeId.hasMatch(id)) return null;
  return 'https://i.ytimg.com/vi/$id/hqdefault.jpg';
}

/// Talks to `ShareChannel.kt`: receives shares and closes the popup
/// (spec-v0.4-share D-52).
class ShareLinkService {
  ShareLinkService([this._channel = channel]);

  static const channel = MethodChannel('io.github.infvyr.ftube/share');

  final MethodChannel _channel;
  final _requests = StreamController<ShareRequest?>.broadcast();

  /// The open share, or null when the popup isn't shown.
  ShareRequest? get current => _current;
  ShareRequest? _current;

  /// Every change of [current].
  Stream<ShareRequest?> get requests => _requests.stream;

  /// Starts listening and takes a share that arrived before Dart did.
  Future<void> start() async {
    _channel.setMethodCallHandler(_onCall);
    try {
      final pending = await _channel.invokeMapMethod<String, Object?>(
        'pending',
      );
      if (pending != null) _set(_request(pending));
    } on Object {
      // No share target on this platform.
    }
  }

  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    await _requests.close();
  }

  /// Closes the popup, with [toast] shown over the sharing app. Returns
  /// false when there is no popup to close.
  Future<bool> close({String? toast}) => _invoke('close', {'toast': toast});

  /// Opens the app and closes the popup.
  Future<bool> openApp() => _invoke('openApp');

  Future<Object?> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'show':
        _set(_request(call.arguments as Map<Object?, Object?>?));
      case 'dismissed':
        _set(null);
      default:
        throw MissingPluginException(call.method);
    }
    return null;
  }

  static ShareRequest _request(Map<Object?, Object?>? args) => ShareRequest(
    args?['text'] as String?,
    subject: args?['subject'] as String?,
  );

  void _set(ShareRequest? request) {
    _current = request;
    _requests.add(request);
  }

  Future<bool> _invoke(String method, [Object? args]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
      return true;
    } on Object {
      return false;
    }
  }
}
