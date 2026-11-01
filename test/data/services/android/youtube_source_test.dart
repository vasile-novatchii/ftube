import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/data/services/android/youtube_source.dart';
import 'package:ftube/domain/exceptions/ftube_exception.dart';
import 'package:ftube/domain/models/media_format.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

void main() {
  group('parseVideoId', () {
    final source = ExplodeYoutubeSource();
    tearDownAll(source.close);

    test('accepts the usual YouTube URL shapes', () {
      for (final url in [
        'https://www.youtube.com/watch?v=jNQXAC9IVRw',
        ' https://youtu.be/jNQXAC9IVRw?t=3 ',
        'https://m.youtube.com/watch?v=jNQXAC9IVRw&list=x',
        'https://www.youtube.com/shorts/jNQXAC9IVRw',
        'https://www.youtube.com/embed/jNQXAC9IVRw',
      ]) {
        expect(source.parseVideoId(url), 'jNQXAC9IVRw', reason: url);
      }
    });

    test('returns null for other sites and playlists', () {
      for (final url in [
        'https://vimeo.com/76979871',
        'https://www.youtube.com/playlist?list=PL123',
        'https://www.youtube.com/',
      ]) {
        expect(source.parseVideoId(url), isNull, reason: url);
      }
    });
  });

  test('open rejects streams that do not come from streams()', () {
    final source = ExplodeYoutubeSource();
    addTearDown(source.close);
    expect(
      () => source.open(
        const YtStream(tag: 1, kind: FormatKind.videoAudio, container: 'mp4'),
      ),
      throwsArgumentError,
    );
  });

  test('mapError maps package and I/O errors', () {
    final cases = <Object, Matcher>{
      yt.VideoUnavailableException('gone'): isA<Unsupported>(),
      yt.VideoUnplayableException('private'): isA<Unsupported>(),
      yt.RequestLimitExceededException('429'): isA<Network>(),
      yt.TransientFailureException('5xx'): isA<Network>(),
      yt.FatalFailureException('bad', 403): isA<Network>(),
      const SocketException('offline'): isA<Network>(),
      const HttpException('reset'): isA<Network>(),
      TimeoutException('slow'): isA<Network>(),
      http.ClientException('closed'): isA<Network>(),
      ArgumentError('id'): isA<InvalidUrl>(),
      const Cancelled(): isA<Cancelled>(),
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      expect(ExplodeYoutubeSource.mapError(key), value, reason: '$key');
    }
    final other = StateError('x');
    expect(ExplodeYoutubeSource.mapError(other), same(other));
  });
}
