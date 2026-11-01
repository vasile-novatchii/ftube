import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/data/repositories/settings_repository.dart';
import 'package:ftube/domain/models/app_settings.dart';
import 'package:ftube/domain/models/quality_preset.dart';

import '../../ui/helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SettingsRepository> repo([
    Map<String, Object> values = const {},
  ]) async {
    final r = SettingsRepository(await testPrefs(values));
    addTearDown(r.dispose);
    return r;
  }

  test('starts with the defaults', () async {
    expect((await repo()).current, const AppSettings());
  });

  test('saves and reloads every field', () async {
    final first = await repo();
    const settings = AppSettings(
      theme: ThemePreference.dark,
      language: AppLanguage.ro,
      downloadDir: '/music',
      defaultPreset: QualityPreset.audioMp3,
      concurrentDownloads: 3,
    );
    await first.save(settings);
    expect(first.current, settings);

    // shared_preferences keeps the mock values between instances.
    final again = SettingsRepository(await reloadPrefs());
    expect(again.current, settings);
  });

  test('a blank download folder is stored as the default', () async {
    final r = await repo({SettingsRepository.downloadDirKey: '/old'});
    expect(r.current.downloadDir, '/old');
    await r.save(r.current.copyWith(downloadDir: '  '));
    expect(r.current.downloadDir, isNull);
    final again = SettingsRepository(await reloadPrefs());
    expect(again.current.downloadDir, isNull);
  });

  test('ignores unknown or out-of-range stored values', () async {
    final r = await repo({
      SettingsRepository.themeKey: 'sepia',
      SettingsRepository.languageKey: 'fr',
      SettingsRepository.presetKey: 'custom',
      SettingsRepository.concurrentKey: 9,
      SettingsRepository.downloadDirKey: ' ',
    });
    expect(r.current, const AppSettings());
  });

  test('changes emits only real changes', () async {
    final r = await repo();
    final seen = <AppSettings>[];
    final sub = r.changes.listen(seen.add);
    addTearDown(sub.cancel);

    await r.update((s) => s.copyWith(theme: ThemePreference.light));
    await r.update((s) => s.copyWith(theme: ThemePreference.light));
    await r.update((s) => s.copyWith(concurrentDownloads: 1));

    expect(seen.map((s) => (s.theme, s.concurrentDownloads)), [
      (ThemePreference.light, 2),
      (ThemePreference.light, 1),
    ]);
  });

  test('remembers that the permission prompt was shown', () async {
    final r = await repo();
    expect(r.permissionPromptDone, isFalse);
    await r.markPermissionPromptDone();
    expect(r.permissionPromptDone, isTrue);
  });
}
