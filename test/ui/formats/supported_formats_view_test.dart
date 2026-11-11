import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/domain/models/audio_target.dart';
import 'package:ftube/domain/models/quality_preset.dart';
import 'package:ftube/ui/core/l10n.dart';
import 'package:ftube/ui/formats/widgets/supported_formats_view.dart';
import 'package:ftube/ui/settings/widgets/settings_view.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers.dart';

void main() {
  late TestEnv env;

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Locale locale = const Locale('en'),
    Size size = const Size(1200, 2400),
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = await env.container();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: localized(child, locale: locale),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() => env = TestEnv.desktop());

  testWidgets('Settings opens Supported formats', (tester) async {
    await pump(tester, const SettingsView());
    final tile = find.byKey(const Key('settings.formats'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.byType(SupportedFormatsView), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Supported formats'), findsOneWidget);
  });

  testWidgets('lists every preset, audio target and container (D-103)', (
    tester,
  ) async {
    await pump(tester, const SupportedFormatsView());
    final l10n = lookupAppLocalizations(const Locale('en'));
    for (final p in QualityPreset.values) {
      expect(find.text(l10n.presetLabel(p)), findsOneWidget, reason: p.name);
    }
    for (final t in AudioTarget.values) {
      expect(find.text(t.extension.toUpperCase()), findsOneWidget);
    }
    for (final c in SupportedFormatsView.videoContainers) {
      expect(find.text(c), findsOneWidget);
    }
    expect(
      find.descendant(
        of: find.byKey(const Key('formats.audioM4a')),
        matching: find.text('The original stream, not converted'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('formats.audioMp3')),
        matching: find.text('Converted from the best audio stream'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the sites link opens yt-dlp\'s list (D-104)', (tester) async {
    await pump(tester, const SupportedFormatsView());
    final link = find.byKey(const Key('formats.sites'));
    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pumpAndSettle();
    verify(() => env.files.openUrl(SupportedFormatsView.sitesUrl)).called(1);
  });

  testWidgets('fits a phone in every language (DoD-65)', (tester) async {
    for (final locale in AppLocalizations.supportedLocales) {
      await pump(
        tester,
        const SupportedFormatsView(),
        locale: locale,
        size: const Size(300, 400),
      );
      expect(tester.takeException(), isNull, reason: '$locale');
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('formats.sites')), findsOneWidget);
    }
  });
}
