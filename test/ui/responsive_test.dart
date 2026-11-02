import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/ui/app.dart';
import 'package:ftube/ui/shell/app_shell.dart';

import 'helpers.dart';
import 'library/library_fixtures.dart';

/// Every screen at phone, split-screen, pop-up and desktop window sizes
/// (spec-v0.2 D-21, DoD-12, DoD-13).
void main() {
  const sizes = {
    'portrait phone': Size(360, 640),
    'landscape phone': Size(640, 360),
    'split screen': Size(360, 300),
    'pop-up window': Size(300, 400),
    'desktop default': Size(800, 600),
    'desktop maximized': Size(1920, 1080),
  };

  for (final (name, env) in [
    ('desktop', TestEnv.desktop),
    ('android', TestEnv.android),
  ]) {
    group(name, () {
      for (final MapEntry(key: label, value: size) in sizes.entries) {
        testWidgets('$label fits on every screen', (tester) async {
          tester.view
            ..physicalSize = size
            ..devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final e = env();
          Disk(e.files);
          final container = await e.container();
          addTearDown(container.dispose);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: const FtubeApp(),
            ),
          );
          await tester.pumpAndSettle();

          final wide = size.width >= railMinWidth;
          expect(find.byType(NavigationRail), wide ? findsOne : findsNothing);
          expect(find.byType(NavigationBar), wide ? findsNothing : findsOne);

          for (final icon in [
            Icons.video_library_outlined,
            Icons.settings_outlined,
            Icons.home_outlined,
          ]) {
            await tester.tap(find.byIcon(icon).first);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final page = tester.getSize(
              find.byWidgetPredicate(
                (w) =>
                    w is ConstrainedBox &&
                    w.constraints.maxWidth == maxContentWidth,
              ),
            );
            expect(page.width, lessThanOrEqualTo(maxContentWidth));
          }
        });
      }
    });
  }
}
