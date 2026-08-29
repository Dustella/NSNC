/// In-memory cookie store for the Netease session.
///
/// Holds the flat name→value map the API needs (MUSIC_U, __csrf, os, appver,
/// device fields, …). Persistence is the caller's concern: [toMap]/[fromMap]
/// serialize the whole jar so it can be written to disk and restored.
class CookieJar {
  CookieJar([Map<String, String>? initial]) {
    if (initial != null) _store.addAll(initial);
  }

  final Map<String, String> _store = {};

  Map<String, String> get entries => Map.unmodifiable(_store);

  String? operator [](String key) => _store[key];
  void operator []=(String key, String value) => _store[key] = value;

  bool get isLoggedIn => _store.containsKey('MUSIC_U');

  void remove(String key) => _store.remove(key);
  void clear() => _store.clear();

  /// Merge `Set-Cookie` response headers back into the jar. Each entry is a
  /// full cookie line; we keep only the leading `name=value` pair and drop
  /// attributes (Domain/Path/Expires/…). Empty values (deletions) are honored.
  void ingestSetCookies(Iterable<String> setCookies) {
    for (final line in setCookies) {
      final first = line.split(';').first.trim();
      if (first.isEmpty) continue;
      final eq = first.indexOf('=');
      if (eq <= 0) continue;
      final name = first.substring(0, eq).trim();
      final value = first.substring(eq + 1).trim();
      if (value.isEmpty) {
        _store.remove(name);
      } else {
        _store[name] = value;
      }
    }
  }

  Map<String, String> toMap() => Map<String, String>.from(_store);

  factory CookieJar.fromMap(Map<String, dynamic> map) =>
      CookieJar(map.map((k, v) => MapEntry(k, v.toString())));
}
