import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/data/services/android/share_link_service.dart';

import 'share_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('extractLink', () {
    test('finds the first http(s) link in the text', () {
      expect(extractLink('https://youtu.be/abc'), 'https://youtu.be/abc');
      expect(
        extractLink('Great song https://youtu.be/abc?t=5 via app'),
        'https://youtu.be/abc?t=5',
      );
      expect(
        extractLink('a http://x.com/1 then https://y.com/2'),
        'http://x.com/1',
      );
      expect(extractLink('HTTPS://Example.com/v'), 'HTTPS://Example.com/v');
    });

    test('drops punctuation after the link', () {
      expect(
        extractLink('Watch https://youtu.be/abc.'),
        'https://youtu.be/abc',
      );
      expect(extractLink('(https://youtu.be/abc)'), 'https://youtu.be/abc');
      expect(extractLink('"https://youtu.be/abc",'), 'https://youtu.be/abc');
      expect(extractLink('«https://youtu.be/abc»!'), 'https://youtu.be/abc');
    });

    test('returns null without a usable link', () {
      expect(extractLink(null), isNull);
      expect(extractLink(''), isNull);
      expect(extractLink('just words'), isNull);
      expect(extractLink('ftp://x.com/a'), isNull);
      expect(extractLink('https://'), isNull);
      expect(extractLink('https://...'), isNull);
    });
  });

  group('ShareLinkService', () {
    late ShareHost host;
    late List<ShareRequest?> events;

    setUp(() {
      host = ShareHost()..install();
      events = [];
      host.service.requests.listen(events.add);
    });

    tearDown(() async {
      host.uninstall();
      await host.service.dispose();
    });

    test('takes a share that arrived before Dart started, once', () async {
      host.pending = 'Look https://youtu.be/abc';
      await host.service.start();
      expect(host.service.current?.url, 'https://youtu.be/abc');
      await pumpEventQueue();
      expect(events.single?.url, 'https://youtu.be/abc');
      expect(host.calls.single.method, 'pending');
      expect(host.pending, isNull);
    });

    test('has no share when none is pending', () async {
      await host.service.start();
      expect(host.service.current, isNull);
      expect(events, isEmpty);
    });

    test('ignores a missing channel', () async {
      host.uninstall();
      await host.service.start();
      expect(host.service.current, isNull);
    });

    test('a share replaces the open one, even with the same link', () async {
      await host.service.start();
      await host.show('https://youtu.be/abc');
      final first = host.service.current;
      await host.show('https://youtu.be/abc');
      expect(host.service.current, isNot(same(first)));
      await pumpEventQueue();
      expect(events.map((e) => e?.url), [
        'https://youtu.be/abc',
        'https://youtu.be/abc',
      ]);
    });

    test('a share without a link opens the popup with no url', () async {
      await host.service.start();
      await host.show('no link here');
      expect(host.service.current, isNotNull);
      expect(host.service.current!.url, isNull);
      await host.show(null);
      expect(host.service.current!.url, isNull);
    });

    test('dismissed ends the share', () async {
      await host.service.start();
      await host.show('https://youtu.be/abc');
      await host.dismissed();
      expect(host.service.current, isNull);
      await pumpEventQueue();
      expect(events.last, isNull);
    });

    test('rejects unknown calls', () async {
      await host.service.start();
      // MethodChannel answers MissingPluginException with no reply.
      expect(await host.send('nope'), isNull);
      expect(host.service.current, isNull);
    });

    test('close and openApp reach the host', () async {
      await host.service.start();
      host.dismissOnClose = false;
      expect(await host.service.close(toast: 'Download started'), isTrue);
      expect(await host.service.close(), isTrue);
      expect(await host.service.openApp(), isTrue);
      expect(host.calls.skip(1).map((c) => '${c.method} ${c.arguments}'), [
        'close {toast: Download started}',
        'close {toast: null}',
        'openApp null',
      ]);
    });

    test('close and openApp report a failure', () async {
      await host.service.start();
      host.fail = true;
      expect(await host.service.close(), isFalse);
      expect(await host.service.openApp(), isFalse);
    });

    test('stops listening once disposed', () async {
      await host.service.start();
      await host.service.dispose();
      await host.show('https://youtu.be/abc');
      expect(host.service.current, isNull);
    });
  });
}
