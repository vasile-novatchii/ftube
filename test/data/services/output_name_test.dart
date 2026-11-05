import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/data/services/output_name.dart';
import 'package:path/path.dart' as p;

void main() {
  group('fromTitle', () {
    test('keeps the title as is when it is already valid', () {
      const title =
          'Big Buck Bunny 60fps 4K - Official Blender Foundation Short Film';
      expect(OutputName.fromTitle(title), title);
      expect(OutputName.fromTitle('Café — été, 日本語 #1'), 'Café — été, 日本語 #1');
    });

    test('swaps forbidden characters for look-alikes', () {
      expect(
        OutputName.fromTitle(r'a/b\c:d*e?f"g<h>i|j'),
        'a⧸b⧹c：d＊e？f＂g＜h＞i｜j',
      );
    });

    test('drops control characters, leading dots and trailing dots', () {
      expect(OutputName.fromTitle('  line\none\ttwo  '), 'line one two');
      expect(OutputName.fromTitle('.hidden'), 'hidden');
      expect(OutputName.fromTitle('Wait...'), 'Wait');
      expect(OutputName.fromTitle('...'), 'video');
      expect(OutputName.fromTitle(''), 'video');
    });

    test('avoids Windows device names', () {
      expect(OutputName.fromTitle('con'), 'con_');
      expect(OutputName.fromTitle('NUL.txt'), 'NUL.txt_');
      expect(OutputName.fromTitle('Console'), 'Console');
    });

    test('cuts long titles at a character boundary', () {
      final ascii = OutputName.fromTitle('x' * 300);
      expect(ascii.length, OutputName.maxBytes);
      final wide = OutputName.fromTitle('日' * 100);
      expect(utf8.encode(wide).length, lessThanOrEqualTo(OutputName.maxBytes));
      expect(wide, '日' * (OutputName.maxBytes ~/ 3));
    });
  });

  group('place', () {
    late Directory root;
    late Directory out;

    setUp(() {
      root = Directory.systemTemp.createTempSync('ftube_name_test');
      out = Directory(p.join(root.path, 'out'))..createSync();
    });

    tearDown(() => root.deleteSync(recursive: true));

    File src(String content, [String ext = '.mp4']) =>
        File(p.join(root.path, 'media$ext'))..writeAsStringSync(content);

    test('moves the file under the name with its extension', () async {
      final dst = await OutputName.place(src('new'), out, 'My video');
      expect(dst.path, p.join(out.path, 'My video.mp4'));
      expect(dst.readAsStringSync(), 'new');
      expect(File(p.join(root.path, 'media.mp4')).existsSync(), isFalse);
    });

    test('numbers the name instead of replacing a file', () async {
      File(p.join(out.path, 'My video.mp4')).writeAsStringSync('one');
      File(p.join(out.path, 'My video (2).mp4')).writeAsStringSync('two');
      final dst = await OutputName.place(src('new'), out, 'My video');
      expect(p.basename(dst.path), 'My video (3).mp4');
      expect(File(p.join(out.path, 'My video.mp4')).readAsStringSync(), 'one');
      expect(dst.readAsStringSync(), 'new');
    });

    test('another extension is not a clash', () async {
      File(p.join(out.path, 'Song.mp4')).writeAsStringSync('video');
      final dst = await OutputName.place(src('a', '.mp3'), out, 'Song');
      expect(p.basename(dst.path), 'Song.mp3');
    });

    test('two jobs with one title get different names', () async {
      final a = File(p.join(root.path, 'a.mp4'))..writeAsStringSync('a');
      final b = File(p.join(root.path, 'b.mp4'))..writeAsStringSync('b');
      final dsts = await Future.wait([
        OutputName.place(a, out, 'Same'),
        OutputName.place(b, out, 'Same'),
      ]);
      expect(dsts.map((f) => p.basename(f.path)).toSet(), {
        'Same.mp4',
        'Same (2).mp4',
      });
      expect(dsts.map((f) => f.readAsStringSync()).toSet(), {'a', 'b'});
    });

    test('removes the reserved name when the move fails', () async {
      final missing = File(p.join(root.path, 'gone.mp4'));
      await expectLater(
        OutputName.place(missing, out, 'X'),
        throwsA(isA<FileSystemException>()),
      );
      expect(out.listSync(), isEmpty);
    });
  });
}
