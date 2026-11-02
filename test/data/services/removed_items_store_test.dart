import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/data/services/removed_items_store.dart';
import 'package:ftube/domain/models/models.dart';

import '../../ui/helpers.dart';

LibraryItem item(String path, {int size = 10, int day = 1}) => LibraryItem(
  path: path,
  name: path.split('/').last,
  sizeBytes: size,
  modified: DateTime(2026, 1, day),
  kind: LibraryKind.fromPath(path),
);

void main() {
  final a = item('/dl/a.mp4');
  final b = item('/dl/b.mp3');

  test('starts empty and remembers removed items across restarts', () async {
    final store = RemovedItemsStore(await testPrefs());
    expect(store.contains(a), isFalse);
    await store.addAll([a, b]);
    expect(store.contains(a), isTrue);

    final reloaded = RemovedItemsStore(await reloadPrefs());
    expect(reloaded.length, 2);
    expect(reloaded.contains(b), isTrue);
  });

  test(
    'a file with the same path but a new size or time is not removed',
    () async {
      final store = RemovedItemsStore(await testPrefs());
      await store.addAll([a]);
      expect(store.contains(item('/dl/a.mp4', size: 11)), isFalse);
      expect(store.contains(item('/dl/a.mp4', day: 2)), isFalse);
    },
  );

  test('prune drops entries of the folder whose file is gone', () async {
    final store = RemovedItemsStore(await testPrefs());
    final other = item('/elsewhere/c.mp4');
    await store.addAll([a, b, other]);
    await store.prune('/dl', [a]);
    expect(store.contains(a), isTrue);
    expect(store.contains(b), isFalse);
    expect(store.contains(other), isTrue, reason: 'other folder kept');
    expect(RemovedItemsStore(await reloadPrefs()).length, 2);
  });

  test('a corrupt entry list reads as empty', () async {
    final store = RemovedItemsStore(
      await testPrefs({RemovedItemsStore.key: '{not json'}),
    );
    expect(store.length, 0);
  });
}
