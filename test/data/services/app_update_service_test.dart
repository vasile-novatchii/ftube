import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/data/services/app_update_service.dart';
import 'package:ftube/domain/exceptions/ftube_exception.dart';

/// Trimmed from a real `releases/latest` reply.
const _release = {
  'tag_name': 'v0.6.0',
  'name': 'Ftube 0.6.0',
  'html_url': 'https://github.com/vasile-novatchii/ftube/releases/tag/v0.6.0',
  'published_at': '2026-11-20T10:00:00Z',
  'draft': false,
  'prerelease': false,
  'body': '## What\'s new\n\n- Update notice\n',
};

void main() {
  group('parse', () {
    test('reads the tag, page, date and notes', () {
      final r = AppUpdateService.parse(jsonEncode(_release));
      expect(r.tag, 'v0.6.0');
      expect(r.version, '0.6.0');
      expect(r.pageUrl.toString(), _release['html_url']);
      expect(r.publishedAt, DateTime.utc(2026, 11, 20, 10));
      expect(r.notes, "## What's new\n\n- Update notice");
    });

    test('a missing body or date is empty, a tag without v is kept', () {
      final r = AppUpdateService.parse(
        jsonEncode({..._release, 'tag_name': '1.2.3', 'body': null}),
      );
      expect(r.version, '1.2.3');
      expect(r.notes, '');
      final noDate = Map.of(_release)..remove('published_at');
      expect(AppUpdateService.parse(jsonEncode(noDate)).publishedAt, isNull);
    });

    test('bad JSON, missing fields and non-GitHub pages are rejected', () {
      for (final body in [
        'not json',
        '[]',
        jsonEncode({'tag_name': 'v1.0.0'}),
        jsonEncode({..._release, 'html_url': 'https://evil.example/x'}),
        jsonEncode({..._release, 'html_url': 'http://github.com/x'}),
      ]) {
        expect(
          () => AppUpdateService.parse(body),
          throwsA(isA<Unexpected>()),
          reason: body,
        );
      }
    });
  });

  group('latestRelease', () {
    late HttpServer server;
    late List<HttpRequest> requests;
    late void Function(HttpResponse) reply;

    setUp(() async {
      requests = [];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) {
        requests.add(r);
        reply(r.response);
      });
    });

    tearDown(() => server.close(force: true));

    AppUpdateService service({Duration? timeout}) => AppUpdateService(
      appVersion: () async => '0.5.0',
      url: Uri.parse('http://${server.address.host}:${server.port}/latest'),
      timeout: timeout ?? const Duration(seconds: 10),
    );

    test('sends the GitHub headers and parses the reply', () async {
      reply = (r) => r
        ..write(jsonEncode(_release))
        ..close();
      final release = await service().latestRelease();
      expect(release.version, '0.6.0');
      final headers = requests.single.headers;
      expect(headers.value('accept'), 'application/vnd.github+json');
      expect(headers.value('user-agent'), 'Ftube/0.5.0');
    });

    for (final status in [403, 404, 429, 500]) {
      test('HTTP $status is a Network error', () async {
        reply = (r) => r
          ..statusCode = status
          ..close();
        await expectLater(service().latestRelease(), throwsA(isA<Network>()));
      });
    }

    test('a slow reply times out as a Network error', () async {
      reply = (_) {};
      await expectLater(
        service(timeout: const Duration(milliseconds: 100)).latestRelease(),
        throwsA(isA<Network>()),
      );
    });

    test('an unreachable host is a Network error', () async {
      final closed = service();
      await server.close(force: true);
      await expectLater(closed.latestRelease(), throwsA(isA<Network>()));
    });
  });
}
