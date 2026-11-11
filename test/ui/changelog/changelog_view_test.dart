import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/ui/core/markdown_view.dart';
import 'package:ftube/ui/settings/widgets/settings_view.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers.dart';

void main() {
  late TestEnv env;

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view
      ..physicalSize = const Size(1200, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = await env.container();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: localized(child)),
    );
    await tester.pumpAndSettle();
  }

  setUp(() => env = TestEnv.desktop());

  testWidgets('App version opens the bundled changelog (DoD-62)', (
    tester,
  ) async {
    await pump(tester, const SettingsView());
    final tile = find.byKey(const Key('settings.version'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    // The asset loads on a real isolate.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Changelog'), findsOneWidget);
    expect(find.byKey(const Key('changelog.text')), findsOneWidget);
    // The file's own "# Changelog" heading is dropped, and the oldest
    // release is rendered as a heading.
    expect(find.text('Changelog'), findsOneWidget);
    expect(find.textContaining('0.1.0 - ', findRichText: true), findsOne);
    expect(find.textContaining('##'), findsNothing);
  });

  testWidgets('MarkdownView renders lists and opens https links only', (
    tester,
  ) async {
    await pump(
      tester,
      const Scaffold(
        body: MarkdownView(
          '# Title\n\n- one\n- [docs](https://example.com/d)\n'
          '- [local](file:///etc/passwd)\n\n![logo](https://x.com/a.png)',
        ),
      ),
    );
    expect(find.text('Title'), findsOneWidget);
    expect(find.textContaining('one', findRichText: true), findsOne);
    expect(find.byType(Image), findsNothing);
    expect(find.text('logo'), findsOneWidget);

    final onTapLink = tester
        .widget<MarkdownBody>(find.byType(MarkdownBody))
        .onTapLink!;
    onTapLink('docs', 'https://example.com/d', '');
    onTapLink('local', 'file:///etc/passwd', '');
    onTapLink('none', null, '');
    verify(() => env.files.openUrl(Uri.parse('https://example.com/d')))
        .called(1);
    verifyNoMoreInteractions(env.files);
  });
}
