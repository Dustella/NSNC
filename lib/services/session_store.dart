import 'dart:convert';

import 'package:ncm_api/ncm_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the Netease session across app launches: the cookie jar (auth)
/// and the device identity (fingerprint). Both are stored as JSON blobs.
///
/// The device is persisted so the fingerprint stays stable — a client whose
/// deviceId changes every launch reads as suspicious to Netease's risk control.
class SessionStore {
  SessionStore(this._prefs);

  static const _cookieKey = 'ncm_session_cookies_v1';
  static const _deviceKey = 'ncm_device_v1';
  final SharedPreferences _prefs;

  static Future<SessionStore> open() async =>
      SessionStore(await SharedPreferences.getInstance());

  /// Load a saved jar, or an empty one on first run.
  CookieJar loadJar() {
    final raw = _prefs.getString(_cookieKey);
    if (raw == null || raw.isEmpty) return CookieJar();
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return CookieJar.fromMap(map);
    } catch (_) {
      return CookieJar();
    }
  }

  Future<void> saveJar(CookieJar jar) =>
      _prefs.setString(_cookieKey, jsonEncode(jar.toMap()));

  /// Load the persisted device identity, or generate + persist a fresh one on
  /// first run so it's stable from then on.
  Future<Device> loadOrCreateDevice() async {
    final raw = _prefs.getString(_deviceKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        return Device.fromMap(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {/* regenerate below */}
    }
    final device = Device.generate();
    await _prefs.setString(_deviceKey, jsonEncode(device.toMap()));
    return device;
  }

  /// Clear the auth session only. The device identity is intentionally kept
  /// across logout so the same install keeps a stable fingerprint.
  Future<void> clear() => _prefs.remove(_cookieKey);
}
