import 'package:flutter_test/flutter_test.dart';

import '../../ui/helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reads, writes and removes values', () async {
    final prefs = await testPrefs({'s': 'a', 'i': 1, 'b': true});
    expect(prefs.getString('s'), 'a');
    expect(prefs.getInt('i'), 1);
    expect(prefs.getBool('b'), isTrue);

    await prefs.setString('s', 'z');
    await prefs.setInt('i', 7);
    await prefs.setBool('b', value: false);
    expect(
      (prefs.getString('s'), prefs.getInt('i'), prefs.getBool('b')),
      ('z', 7, false),
    );

    await prefs.remove('s');
    expect(prefs.getString('s'), isNull);
  });
}
