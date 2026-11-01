import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _arb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, Object?>;

Set<String> _messages(Map<String, Object?> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

void main() {
  test('every English message exists in Romanian and vice versa', () {
    final en = _messages(_arb('en'));
    final ro = _messages(_arb('ro'));
    expect(en.difference(ro), isEmpty, reason: 'missing in app_ro.arb');
    expect(ro.difference(en), isEmpty, reason: 'unknown in app_ro.arb');
  });

  test('translations keep the placeholders of the template', () {
    final en = _arb('en');
    final ro = _arb('ro');
    final placeholder = RegExp(r'\{(\w+)\}');
    for (final key in _messages(en)) {
      Set<String> names(Object? text) =>
          placeholder.allMatches('$text').map((m) => m.group(1)!).toSet();
      expect(names(ro[key]), names(en[key]), reason: key);
    }
  });
}
