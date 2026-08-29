import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ncm_api/ncm_api.dart';

import 'session_store.dart';

enum AuthStatus { unknown, loggedOut, loggedIn }

/// Central app controller: owns the [NcmClient] + session persistence and
/// tracks the current user. Login flows write cookies into the client's jar;
/// this controller persists them and refreshes the profile.
class AppState extends ChangeNotifier {
  AppState({required this.client, required SessionStore store}) : _store = store; // ignore: prefer_initializing_formals

  final NcmClient client;
  final SessionStore _store;

  AuthStatus _status = AuthStatus.unknown;
  Map<String, dynamic>? _profile;

  AuthStatus get status => _status;
  Map<String, dynamic>? get profile => _profile;
  int? get uid => (_profile?['userId'] as num?)?.toInt();
  String get nickname => (_profile?['nickname'] ?? '未登录').toString();
  String? get avatarUrl => _profile?['avatarUrl']?.toString();

  /// Restore a saved session and validate it against the server.
  Future<void> bootstrap() async {
    final jar = _store.loadJar();
    for (final e in jar.entries.entries) {
      client.cookieJar[e.key] = e.value;
    }
    if (client.cookieJar.isLoggedIn) {
      await refreshProfile();
    } else {
      _status = AuthStatus.loggedOut;
      notifyListeners();
    }
  }

  /// Pull the account profile; determines logged-in state.
  ///
  /// The account/get response carries `profile` at the TOP level
  /// (`{code, account, profile}`), not under `data`. A present MUSIC_U cookie
  /// plus a profile with `userId` means we're logged in.
  Future<void> refreshProfile() async {
    if (!client.cookieJar.isLoggedIn) {
      _status = AuthStatus.loggedOut;
      _profile = null;
      notifyListeners();
      return;
    }
    try {
      final body = await client.loginStatus();
      final profile = body['profile'] as Map<String, dynamic>?;
      if (profile != null && profile['userId'] != null) {
        _profile = profile;
        _status = AuthStatus.loggedIn;
      } else {
        // MUSIC_U present but the server didn't return a profile — the cookie
        // is stale/invalid. Treat as logged out and drop it.
        _status = AuthStatus.loggedOut;
        _profile = null;
        client.cookieJar.remove('MUSIC_U');
      }
    } catch (_) {
      // Transient network error: keep the session (MUSIC_U is present) rather
      // than forcing a logout the user didn't ask for.
      _status = AuthStatus.loggedIn;
    }
    notifyListeners();
  }

  /// Call after any successful login to persist cookies + load the profile.
  Future<void> onLoggedIn() async {
    await _store.saveJar(client.cookieJar);
    await refreshProfile();
  }

  Future<void> logout() async {
    await client.logout();
    await _store.clear();
    _profile = null;
    _status = AuthStatus.loggedOut;
    notifyListeners();
  }
}
