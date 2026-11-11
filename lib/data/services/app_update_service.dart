import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../domain/exceptions/ftube_exception.dart';
import '../../domain/models/app_update.dart';

/// Reads the newest Ftube release from the GitHub REST API, without login
/// (docs/spec-v0.6.md D-88).
class AppUpdateService {
  AppUpdateService({
    required this._appVersion,
    HttpClient Function()? httpClient,
    this.timeout = const Duration(seconds: 10),
    Uri? url,
  }) : _httpClient = httpClient ?? HttpClient.new,
       url = url ?? latestUrl;

  /// The one place the repo path lives (R-39).
  static const repo = 'vasile-novatchii/ftube';

  static final latestUrl = Uri.parse(
    'https://api.github.com/repos/$repo/releases/latest',
  );

  /// The running version, sent in the `User-Agent` header.
  final Future<String> Function() _appVersion;
  final Duration timeout;

  /// [latestUrl]; tests point it at a local server.
  final Uri url;
  final HttpClient Function() _httpClient;

  /// The newest release that is not a draft or prerelease. Throws
  /// [Network] when GitHub can't be reached or answers with an error, and
  /// [Unexpected] when the reply can't be read.
  Future<AppRelease> latestRelease() async {
    final client = _httpClient()..connectionTimeout = timeout;
    try {
      final body = await _get(client).timeout(timeout);
      return parse(body);
    } on TimeoutException {
      throw const Network('GitHub API timed out');
    } on SocketException catch (e) {
      throw Network('$e');
    } on HttpException catch (e) {
      throw Network('$e');
    } on TlsException catch (e) {
      throw Network('$e');
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _get(HttpClient client) async {
    final version = await _appVersion();
    final request = await client.getUrl(url);
    request.headers
      ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
      ..set(HttpHeaders.userAgentHeader, 'Ftube/$version');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != HttpStatus.ok) {
      throw Network('HTTP ${response.statusCode} from the GitHub API');
    }
    return body;
  }

  /// Reads a `releases/latest` JSON body (docs/spec-v0.6.md A2).
  static AppRelease parse(String body) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException catch (e) {
      throw Unexpected('release JSON: ${e.message}');
    }
    if (json case {
      'tag_name': final String tag,
      'html_url': final String page,
    }) {
      final url = Uri.tryParse(page);
      // Only GitHub pages are ever opened from a reply (D-94).
      if (url == null || !url.isScheme('https') || url.host != 'github.com') {
        throw Unexpected('release html_url: $page');
      }
      final map = json as Map<String, Object?>;
      return AppRelease(
        tag: tag,
        version: tag.startsWith('v') ? tag.substring(1) : tag,
        pageUrl: url,
        publishedAt: switch (map['published_at']) {
          final String s => DateTime.tryParse(s),
          _ => null,
        },
        notes: switch (map['body']) {
          final String s => s.trim(),
          _ => '',
        },
      );
    }
    throw const Unexpected('release JSON without tag_name/html_url');
  }
}
