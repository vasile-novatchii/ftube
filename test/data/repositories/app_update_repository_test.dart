import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/data/repositories/app_update_repository.dart';
import 'package:ftube/data/services/app_update_service.dart';
import 'package:ftube/data/services/prefs_service.dart';
import 'package:ftube/domain/exceptions/ftube_exception.dart';
import 'package:ftube/domain/models/app_update.dart';
import 'package:mocktail/mocktail.dart';

import '../../ui/helpers.dart';

class _MockService extends Mock implements AppUpdateService {}

AppRelease release(String version) => AppRelease(
  version: version,
  tag: 'v$version',
  pageUrl: Uri.parse('https://github.com/o/r/releases/tag/v$version'),
  notes: '',
);

void main() {
  group('isNewer (D-90)', () {
    test('compares major.minor.patch as numbers', () {
      expect(AppUpdateRepository.isNewer('0.10.0', '0.9.9'), isTrue);
      expect(AppUpdateRepository.isNewer('1.0.0', '0.99.99'), isTrue);
      expect(AppUpdateRepository.isNewer('0.6.1', '0.6.0'), isTrue);
      expect(AppUpdateRepository.isNewer('0.6.0', '0.6.0'), isFalse);
      expect(AppUpdateRepository.isNewer('0.5.9', '0.6.0'), isFalse);
    });

    test('ignores a v prefix and a build suffix', () {
      expect(AppUpdateRepository.isNewer('v0.6.0', '0.5.0+5'), isTrue);
      expect(AppUpdateRepository.isNewer('0.6.0', '0.6.0+9'), isFalse);
    });

    test('an unparseable version is never newer', () {
      for (final bad in ['0.6', '0.6.0-beta', 'latest', '', 'v1.2.3.4']) {
        expect(AppUpdateRepository.isNewer(bad, '0.1.0'), isFalse, reason: bad);
        expect(AppUpdateRepository.isNewer('9.9.9', bad), isFalse, reason: bad);
      }
    });
  });

  group('check', () {
    late _MockService service;
    late PrefsService prefs;
    late DateTime now;

    AppUpdateRepository repo() => AppUpdateRepository(
      service: service,
      prefs: prefs,
      currentVersion: () async => '0.5.0',
      now: () => now,
    );

    setUp(() async {
      service = _MockService();
      prefs = await testPrefs();
      now = DateTime(2026, 11, 11, 12);
      when(service.latestRelease).thenAnswer((_) async => release('0.6.0'));
    });

    test('a newer release is UpdateAvailable', () async {
      final result = await repo().check();
      expect(result, isA<UpdateAvailable>());
      result as UpdateAvailable;
      expect(result.current, '0.5.0');
      expect(result.release.version, '0.6.0');
    });

    test('the same or an older release is UpToDate', () async {
      when(service.latestRelease).thenAnswer((_) async => release('0.5.0'));
      expect(await repo().check(), isA<UpToDate>());
    });

    test('checks at most once in 24h unless forced (D-89)', () async {
      final r = repo();
      await r.check();
      now = now.add(const Duration(hours: 23));
      expect(await r.check(), isNull);
      expect(await r.check(force: true), isA<UpdateAvailable>());
      now = now.add(const Duration(hours: 24));
      expect(await r.check(), isA<UpdateAvailable>());
      verify(service.latestRelease).called(3);
    });

    test('a failed check is CheckFailed and saves no timestamp', () async {
      when(service.latestRelease).thenThrow(const Network('offline'));
      expect(await repo().check(), isA<CheckFailed>());
      expect(prefs.getInt(AppUpdateRepository.lastCheckKey), isNull);
      when(service.latestRelease).thenAnswer((_) async => release('0.6.0'));
      expect(await repo().check(), isA<UpdateAvailable>());
    });

    test('a clock set back counts as due', () async {
      await prefs.setInt(
        AppUpdateRepository.lastCheckKey,
        now.add(const Duration(days: 3)).millisecondsSinceEpoch,
      );
      expect(await repo().check(), isA<UpdateAvailable>());
    });

    test('remembers the skipped and notified versions', () async {
      final r = repo();
      expect(r.skipped, isNull);
      await r.skip('0.6.0');
      expect(repo().skipped, '0.6.0');
      expect(r.wasNotified('0.6.0'), isFalse);
      await r.markNotified('0.6.0');
      expect(repo().wasNotified('0.6.0'), isTrue);
      expect(repo().wasNotified('0.7.0'), isFalse);
    });
  });
}
