import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/main.dart';

void main() {
  testWidgets('FtubeApp starts and follows the system theme', (tester) async {
    await tester.pumpWidget(const FtubeApp());

    expect(find.text('Ftube'), findsOneWidget);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.system);
  });
}
