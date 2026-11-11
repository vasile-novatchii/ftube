import '../../domain/exceptions/ftube_exception.dart';
import '../../domain/models/app_update.dart';
import '../services/app_update_service.dart';
import '../services/prefs_service.dart';

/// Compares the latest release with the running version, limits automatic
/// checks to one a day and remembers a skipped version (docs/spec-v0.6.md
/// D-89, D-90, D-91, D-93).
class AppUpdateRepository {
  AppUpdateRepository({
    required this._service,
    required this._prefs,
    required this._currentVersion,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AppUpdateService _service;
  final PrefsService _prefs;
  final Future<String> Function() _currentVersion;
  final DateTime Function() _now;

  static const lastCheckKey = 'appUpdate.lastCheck';
  static const skippedKey = 'appUpdate.skipped';
  static const notifiedKey = 'appUpdate.notified';

  static const interval = Duration(hours: 24);

  /// Checks GitHub for a newer release. Without [force], returns null and
  /// sends no request when the last successful check was under 24h ago.
  /// Never throws: failures are [CheckFailed].
  Future<UpdateCheck?> check({bool force = false}) async {
    if (!force && !_due()) return null;
    final String current;
    try {
      current = await _currentVersion();
    } on Object catch (e) {
      return CheckFailed('app version: $e');
    }
    final AppRelease release;
    try {
      release = await _service.latestRelease();
    } on FtubeException catch (e) {
      return CheckFailed('$e');
    }
    await _prefs.setInt(lastCheckKey, _now().millisecondsSinceEpoch);
    return isNewer(release.version, current)
        ? UpdateAvailable(current, release)
        : UpToDate(current);
  }

  bool _due() {
    final last = _prefs.getInt(lastCheckKey);
    if (last == null) return true;
    final elapsed = _now().difference(
      DateTime.fromMillisecondsSinceEpoch(last),
    );
    // A clock set back counts as due, so a bad timestamp can't stop checks.
    return elapsed.isNegative || elapsed >= interval;
  }

  String? get skipped => _prefs.getString(skippedKey);

  Future<void> skip(String version) => _prefs.setString(skippedKey, version);

  /// Whether Android already posted a notification for [version].
  bool wasNotified(String version) => _prefs.getString(notifiedKey) == version;

  Future<void> markNotified(String version) =>
      _prefs.setString(notifiedKey, version);

  /// `major.minor.patch` as integers, ignoring a leading `v` and a `+build`
  /// suffix (D-90). Null when [version] doesn't parse.
  static List<int>? parseVersion(String version) {
    final core = version.split('+').first.trim();
    final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$').firstMatch(core);
    if (match == null) return null;
    return [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
  }

  /// Whether [latest] is a higher version than [current]. An unparseable
  /// version is never newer.
  static bool isNewer(String latest, String current) {
    final l = parseVersion(latest);
    final c = parseVersion(current);
    if (l == null || c == null) return false;
    for (var i = 0; i < 3; i++) {
      if (l[i] != c[i]) return l[i] > c[i];
    }
    return false;
  }
}
