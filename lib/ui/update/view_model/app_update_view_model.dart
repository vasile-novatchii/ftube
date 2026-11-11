import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../config/providers.dart';
import '../../../domain/models/app_update.dart';
import '../../../l10n/generated/app_localizations.dart';

part 'app_update_view_model.freezed.dart';
part 'app_update_view_model.g.dart';

@freezed
abstract class AppUpdateState with _$AppUpdateState {
  const factory AppUpdateState({
    /// The release the Home banner offers; null hides the banner.
    AppRelease? banner,

    /// Whether the Settings check is running.
    @Default(false) bool checking,

    /// The last Settings check, shown in its tile (D-92).
    UpdateCheck? manual,
  }) = _AppUpdateState;
}

/// The update notice (docs/spec-v0.6.md part A). Kept alive, so Later
/// lasts until the next launch.
@Riverpod(keepAlive: true)
class AppUpdateViewModel extends _$AppUpdateViewModel {
  var _startupChecked = false;

  @override
  AppUpdateState build() => const AppUpdateState();

  /// The automatic check, once per launch and at most once a day (D-89).
  Future<void> checkOnStartup() async {
    if (_startupChecked) return;
    _startupChecked = true;
    final repo = ref.read(appUpdateRepositoryProvider);
    final result = await repo.check();
    if (!ref.mounted) return;
    switch (result) {
      case CheckFailed(:final reason):
        debugPrint('Update check failed: $reason');
      case UpdateAvailable(:final release) when repo.skipped != release.version:
        state = state.copyWith(banner: release);
        await _notify(release);
      case _:
    }
  }

  /// The Settings check: ignores the daily limit and the skipped version,
  /// and never notifies (D-92, D-93).
  Future<void> checkNow() async {
    if (state.checking) return;
    state = state.copyWith(checking: true);
    final result = await ref
        .read(appUpdateRepositoryProvider)
        .check(force: true);
    if (!ref.mounted) return;
    if (result case CheckFailed(:final reason)) {
      debugPrint('Update check failed: $reason');
    }
    state = state.copyWith(checking: false, manual: result);
  }

  /// Hides the banner until the next launch.
  void later() => state = state.copyWith(banner: null);

  /// Hides the banner until a newer version is published.
  Future<void> skip() async {
    final release = state.banner;
    if (release == null) return;
    state = state.copyWith(banner: null);
    await ref.read(appUpdateRepositoryProvider).skip(release.version);
  }

  /// Opens the release page. Returns false when no browser could open it.
  Future<bool> download(AppRelease release) async {
    try {
      await ref.read(fileSystemServiceProvider).openUrl(release.pageUrl);
      return true;
    } on Object catch (e) {
      debugPrint('Opening ${release.pageUrl} failed: $e');
      return false;
    }
  }

  Future<void> _notify(AppRelease release) async {
    final notifier = ref.read(androidUpdateNoticeProvider);
    final repo = ref.read(appUpdateRepositoryProvider);
    if (notifier == null || repo.wasNotified(release.version)) return;
    final l10n = lookupAppLocalizations(
      Locale(ref.read(currentSettingsProvider).language.code),
    );
    final posted = await notifier.notify(
      release,
      title: l10n.updateAvailable(release.version),
      text: l10n.updateNotificationText,
      channelName: l10n.updateChannel,
    );
    if (posted) await repo.markNotified(release.version);
  }
}
