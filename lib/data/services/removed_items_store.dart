import 'dart:convert';

import 'package:path/path.dart' as p;

import '../../domain/models/models.dart';
import 'prefs_service.dart';

/// Library items removed by "Clear app data" (docs/spec-v0.2.md D-27).
///
/// The files stay on disk; the library just never shows them again. An item
/// is matched by path, size and modified time, so a new file with the same
/// name still shows.
class RemovedItemsStore {
  RemovedItemsStore(this._prefs) : _entries = _read(_prefs);

  static const key = 'library.removed';

  final PrefsService _prefs;
  final Set<RemovedEntry> _entries;

  int get length => _entries.length;

  bool contains(LibraryItem item) => _entries.contains(_entryOf(item));

  /// Removes [items] from the library for good.
  Future<void> addAll(Iterable<LibraryItem> items) async {
    final before = _entries.length;
    _entries.addAll(items.map(_entryOf));
    if (_entries.length != before) await _save();
  }

  /// Drops the entries of [dir] that match none of [listed], the files now
  /// in [dir]: their file was deleted or replaced (R-16).
  Future<void> prune(String dir, Iterable<LibraryItem> listed) async {
    final present = {for (final i in listed) _entryOf(i)};
    final before = _entries.length;
    _entries.removeWhere(
      (e) => p.equals(p.dirname(e.$1), dir) && !present.contains(e),
    );
    if (_entries.length != before) await _save();
  }

  Future<void> _save() => _prefs.setString(
    key,
    jsonEncode([
      for (final (path, size, modified) in _entries) [path, size, modified],
    ]),
  );

  static Set<RemovedEntry> _read(PrefsService prefs) {
    try {
      final raw = jsonDecode(prefs.getString(key) ?? '[]') as List<Object?>;
      return {
        for (final e in raw.cast<List<Object?>>())
          (e[0]! as String, e[1]! as int, e[2]! as int),
      };
    } on Object {
      return {};
    }
  }
}

/// A removed file: its path, size and modified time in milliseconds.
typedef RemovedEntry = (String path, int sizeBytes, int modifiedMs);

RemovedEntry _entryOf(LibraryItem i) =>
    (i.path, i.sizeBytes, i.modified.millisecondsSinceEpoch);
