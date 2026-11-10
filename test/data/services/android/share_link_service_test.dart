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

  group('youtubeThumbnail', () {
    const thumb = 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg';

    test('derives the thumbnail from YouTube video links', () {
      for (final url in [
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=5',
        'https://m.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://youtu.be/dQw4w9WgXcQ?si=x',
        'https://youtube.com/shorts/dQw4w9WgXcQ',
        'https://www.youtube.com/live/dQw4w9WgXcQ',
        'https://music.youtube.com/watch?v=dQw4w9WgXcQ',
      ]) {
        expect(youtubeThumbnail(url), thumb, reason: url);
      }
    });

    test('has none for other links', () {
      for (final url in [
        'https://vimeo.com/1',
        'https://www.youtube.com/playlist?list=PL1',
        'https://www.youtube.com/watch',
        'https://youtu.be/short',
        'https://youtu.be/',
        'not a url ::',
      ]) {
        expect(youtubeThumbnail(url), isNull, reason: url);
      }
    });
  });

  group('videoKey', () {
    test('matches YouTube links by video id', () {
      const id = 'dQw4w9WgXcQ';
      expect(youtubeVideoId('https://youtu.be/$id'), id);
      expect(videoKey('https://youtu.be/$id'), id);
      expect(videoKey(' https://www.youtube.com/watch?v=$id&t=3 '), id);
      expect(videoKey('https://vimeo.com/1 '), 'https://vimeo.com/1');
      expect(youtubeVideoId('https://vimeo.com/1'), isNull);
    });
  });

  group('isPlaylistLink', () {
    test('knows YouTube playlist and channel links', () {
      for (final url in [
        'https://www.youtube.com/playlist?list=PLztm2TugcV9QvWcb7LWVT0jIdNRdtx_fV',
        'https://m.youtube.com/playlist?list=PL1',
        'https://music.youtube.com/playlist?list=OLAK1',
        'https://www.youtube.com/watch?list=PL1',
        'https://www.youtube.com/@BlenderOfficial',
        'https://www.youtube.com/@BlenderOfficial/videos',
        'https://www.youtube.com/channel/UC1',
        'https://www.youtube.com/c/Name',
        'https://www.youtube.com/user/Name/videos',
      ]) {
        expect(isPlaylistLink(url), isTrue, reason: url);
      }
    });

    test('treats videos and other links as not playlists', () {
      for (final url in [
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL1',
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://www.youtube.com/playlist',
        'https://www.youtube.com/shorts/dQw4w9WgXcQ',
        'https://www.youtube.com/channel',
        'https://www.youtube.com/',
        'https://youtu.be/dQw4w9WgXcQ?list=PL1',
        'https://vimeo.com/channels/staffpicks',
        'not a url ::',
      ]) {
        expect(isPlaylistLink(url), isFalse, reason: url);
      }
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

    test('keeps the shared subject, trimmed, or null when empty', () async {
      await host.service.start();
      await host.send('show', {'text': 'https://youtu.be/a', 'subject': ' T '});
      expect(host.service.current?.subject, 'T');
      await host.send('show', {'text': 'https://youtu.be/a', 'subject': ' '});
      expect(host.service.current?.subject, isNull);
      await host.show('https://youtu.be/a');
      expect(host.service.current?.subject, isNull);
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
