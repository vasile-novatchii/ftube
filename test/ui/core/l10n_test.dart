import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/domain/models/models.dart';
import 'package:ftube/l10n/generated/app_localizations_en.dart';
import 'package:ftube/ui/core/l10n.dart';

void main() {
  test('activeLabel names a queued, running or paused video', () {
    final l10n = AppLocalizationsEn();
    expect(l10n.activeLabel(JobStatus.queued), 'Waiting...');
    expect(l10n.activeLabel(JobStatus.running), 'Downloading');
    expect(l10n.activeLabel(JobStatus.paused), 'Paused');
  });
}
