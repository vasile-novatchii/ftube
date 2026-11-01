import 'package:shared_preferences/shared_preferences.dart';

/// Key-value storage backed by `shared_preferences`.
///
/// Reads are synchronous from the cache loaded at startup.
class PrefsService {
  const PrefsService(this._prefs);

  final SharedPreferences _prefs;

  /// Loads the stored values. Call once at startup.
  static Future<PrefsService> load() async =>
      PrefsService(await SharedPreferences.getInstance());

  String? getString(String key) => _prefs.getString(key);

  int? getInt(String key) => _prefs.getInt(key);

  bool? getBool(String key) => _prefs.getBool(key);

  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);

  Future<void> setInt(String key, int value) => _prefs.setInt(key, value);

  Future<void> setBool(String key, {required bool value}) =>
      _prefs.setBool(key, value);

  Future<void> remove(String key) => _prefs.remove(key);
}
