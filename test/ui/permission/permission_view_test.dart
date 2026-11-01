import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/config/providers.dart';
import 'package:ftube/data/services/android/storage_permission_service.dart';
import 'package:ftube/ui/permission/widgets/permission_view.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers.dart';

void main() {
  late TestEnv env;
  late ProviderContainer container;

  setUp(() {
    env = TestEnv.android();
    when(() => env.storage.status())
        .thenAnswer((_) async => StorageAccess.denied);
    when(() => env.storage.request())
        .thenAnswer((_) async => StorageAccess.permanentlyDenied);
  });

  Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    ThemeMode themeMode = ThemeMode.light,
  }) async {
    container = await env.container();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: localized(
          const PermissionView(),
          locale: locale,
          themeMode: themeMode,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final (locale, title) in [
    (const Locale('en'), 'Allow access to files'),
    (const Locale('ro'), 'Permite accesul la fișiere'),
  ]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('renders in ${locale.languageCode} ${mode.name}', (
        tester,
      ) async {
        await pump(tester, locale: locale, themeMode: mode);
        expect(find.text(title), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('a blocked request explains and offers settings', (tester) async {
    await pump(tester);
    expect(find.text('Grant access'), findsOneWidget);
    await tester.tap(find.byKey(const Key('permission.grant')));
    await tester.pumpAndSettle();
    expect(find.text('Open settings'), findsOneWidget);
    expect(find.textContaining('Access was refused'), findsOneWidget);
    verify(() => env.storage.openSettings()).called(1);
  });

  testWidgets('re-checks on resume and Not now ends the prompt', (
    tester,
  ) async {
    await pump(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    verify(() => env.storage.status()).called(2);

    await tester.tap(find.byKey(const Key('permission.later')));
    await tester.pumpAndSettle();
    expect(
      container.read(settingsRepositoryProvider).permissionPromptDone,
      isTrue,
    );
  });
}
