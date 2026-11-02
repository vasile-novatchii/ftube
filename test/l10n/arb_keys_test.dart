import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/domain/models/app_settings.dart';

Map<String, Object?> _arb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, Object?>;

Set<String> _messages(Map<String, Object?> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

Set<String> _placeholders(Object? text) =>
    RegExp(r'\{(\w+)\}').allMatches('$text').map((m) => m.group(1)!).toSet();

void main() {
  final en = _arb('en');
  final translations = [
    for (final l in AppLanguage.values)
      if (l != AppLanguage.en) l.code,
  ];

  test('every language has an ARB file', () {
    expect(translations, ['ro', 'ru', 'es', 'de', 'ar']);
  });

  for (final code in translations) {
    group(code, () {
      final arb = _arb(code);

      test('declares its locale', () {
        expect(arb['@@locale'], code);
      });

      test('has exactly the English messages', () {
        final missing = _messages(en).difference(_messages(arb));
        final unknown = _messages(arb).difference(_messages(en));
        expect(missing, isEmpty, reason: 'missing in app_$code.arb');
        expect(unknown, isEmpty, reason: 'unknown in app_$code.arb');
      });

      test('keeps the placeholders of the template', () {
        for (final key in _messages(en)) {
          expect(_placeholders(arb[key]), _placeholders(en[key]), reason: key);
        }
      });

      test('gives every plural an other form', () {
        for (final key in _messages(arb)) {
          final text = '${arb[key]}';
          if (text.contains(', plural,')) {
            expect(text, contains('other{'), reason: key);
          }
        }
      });

      test('names every language natively', () {
        for (final l in AppLanguage.values) {
          final key = 'language${l.name[0].toUpperCase()}${l.name[1]}';
          expect(arb[key], en[key], reason: key);
        }
      });
    });
  }
}
