import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/domain/models/models.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;

import '../helpers.dart';

/// The default download folder of [TestEnv].
const downloads = '/home/me/Downloads/Ftube';

/// Matches a [Directory] argument by its path.
Directory dirAt(String path) =>
    any(that: isA<Directory>().having((d) => d.path, 'path', path));

/// A download folder held in memory behind a [MockFileSystemService]:
/// `a.mp4` (newest, largest), `b.mp3` and `c.txt`.
class Disk {
  Disk(this._files) {
    add('a.mp4', 30, DateTime(2026, 1, 3));
    add('b.mp3', 10, DateTime(2026, 1, 2));
    add('c.txt', 20, DateTime(2026, 1, 1));
    stub();
  }

  final MockFileSystemService _files;
  final items = <String, LibraryItem>{};

  void add(String name, int size, DateTime modified) {
    final path = p.join(downloads, name);
    items[path] = LibraryItem(
      path: path,
      name: name,
      sizeBytes: size,
      modified: modified,
      kind: LibraryKind.fromPath(name),
    );
  }

  /// Answers list, stat, delete and rename from [items].
  void stub() {
    when(() => _files.list(any())).thenAnswer(
      (_) async =>
          items.values.toList()
            ..sort((a, b) => b.modified.compareTo(a.modified)),
    );
    when(
      () => _files.stat(any()),
    ).thenAnswer((i) async => items[i.positionalArguments.single as String]!);
    when(() => _files.delete(any())).thenAnswer((i) async {
      items.remove(i.positionalArguments.single as String);
    });
    when(() => _files.rename(any(), any())).thenAnswer((i) async {
      final [from as String, to as String] = i.positionalArguments;
      final item = items.remove(from)!;
      items[to] = item.copyWith(path: to, name: p.basename(to));
    });
  }
}
