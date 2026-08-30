import 'dart:convert';

import 'package:crypto/crypto.dart' as c;
import 'package:http/http.dart' as http;

import 'cookie_jar.dart';
import 'device.dart';
import 'request.dart';

/// Song audio quality tiers for the v1 player URL endpoint.
enum SongLevel {
  standard,
  higher,
  exhigh,
  lossless,
  hires,
  jyeffect, // 高清环绕声
  sky, // 沉浸环绕声
  jymaster, // 超清母带
}

extension on SongLevel {
  String get wire => switch (this) {
    SongLevel.standard => 'standard',
    SongLevel.higher => 'higher',
    SongLevel.exhigh => 'exhigh',
    SongLevel.lossless => 'lossless',
    SongLevel.hires => 'hires',
    SongLevel.jyeffect => 'jyeffect',
    SongLevel.sky => 'sky',
    SongLevel.jymaster => 'jymaster',
  };
}

/// Search result categories (Netease `type` codes).
enum SearchType {
  song, // 1
  album, // 10
  artist, // 100
  playlist, // 1000
  user, // 1002
  mv, // 1004
  lyric, // 1006
  radio, // 1009
  video, // 1014
}

extension on SearchType {
  int get code => switch (this) {
    SearchType.song => 1,
    SearchType.album => 10,
    SearchType.artist => 100,
    SearchType.playlist => 1000,
    SearchType.user => 1002,
    SearchType.mv => 1004,
    SearchType.lyric => 1006,
    SearchType.radio => 1009,
    SearchType.video => 1014,
  };
}

/// High-level Netease Cloud Music API client.
///
/// Wraps the encrypted request pipeline and exposes typed methods for the
/// endpoints NSNC needs. Session state lives in [cookieJar]; after any login
/// call, persist `cookieJar.toMap()` and restore it on next launch.
///
/// Every method returns the decoded response `body` (a JSON map). Callers
/// check `body['code'] == 200` or use the convenience wrappers that throw.
class NcmClient {
  NcmClient._(this.cookieJar, this._request);

  factory NcmClient({
    CookieJar? cookieJar,
    Device? device,
    http.Client? httpClient,
  }) {
    final jar = cookieJar ?? CookieJar();
    // The public jar and the request pipeline MUST share one instance so
    // that Set-Cookie ingestion is visible to subsequent encrypted calls.
    final request = NcmRequest(
      cookieJar: jar,
      device: device,
      client: httpClient,
    );
    return NcmClient._(jar, request);
  }

  final CookieJar cookieJar;
  final NcmRequest _request;

  /// The device identity backing this client's fingerprint. Persist
  /// `device.toMap()` and restore via `NcmClient(device: Device.fromMap(...))`
  /// so the fingerprint stays stable across launches.
  Device get device => _request.device;

  void close() => _request.close();

  /// Ingest cookies a response returned into the persistent jar.
  void _absorb(ApiResponse resp) => cookieJar.ingestSetCookies(resp.cookies);

  // ============================================================
  // Login
  // ============================================================

  /// Step 1 of QR login: obtain a unikey.
  ///
  /// MUST use eapi @ interface.music.163.com with type:3 — the same channel as
  /// [loginQrCheck]. A unikey minted on the weapi/music.163.com path binds to a
  /// different device/session context, so the server returns 803 on check but
  /// withholds the login cookies (MUSIC_U). Key and check must share the eapi
  /// channel.
  Future<String> loginQrKey() async {
    final resp = await _request.send(
      'POST',
      'https://interface.music.163.com/eapi/login/qrcode/unikey',
      {'type': 3},
      crypto: CryptoMode.eapi,
      eapiUrl: '/api/login/qrcode/unikey',
    );
    _absorb(resp);
    final key = resp.body['unikey'];
    if (resp.status != 200 || key == null) {
      throw ApiException(resp.status, 'failed to get qr unikey', resp.body);
    }
    return key as String;
  }

  /// Step 2 of QR login: build the URL to encode into a QR image.
  String loginQrCodeUrl(String unikey) =>
      'https://music.163.com/login?codekey=$unikey';

  /// Step 3 of QR login: poll status.
  ///
  /// MUST use eapi @ interfacepc.music.163.com — the weapi path via
  /// music.163.com goes through a CDN (volc-dcdn) that strips the login
  /// Set-Cookie headers, so MUSIC_U never arrives. The direct interface host
  /// with eapi delivers the full cookie set (MUSIC_U, __csrf, …) on code 803.
  Future<ApiResponse> loginQrCheck(String unikey) async {
    final resp = await _request.send(
      'POST',
      'https://interfacepc.music.163.com/eapi/login/qrcode/client/login',
      {'key': unikey, 'type': 3},
      crypto: CryptoMode.eapi,
      eapiUrl: '/api/login/qrcode/client/login',
    );
    if (resp.body['code'] == 803) _absorb(resp);
    return resp;
  }

  /// Phone + password (or captcha) login.
  Future<Map<String, dynamic>> loginCellphone({
    required String phone,
    String? password,
    String? md5Password,
    String? captcha,
    String countrycode = '86',
  }) async {
    final data = <String, dynamic>{
      'type': '1',
      'https': 'true',
      'phone': phone,
      'countrycode': countrycode,
      'rememberLogin': 'true',
    };
    if (captcha != null) {
      data['captcha'] = captcha;
    } else {
      data['password'] =
          md5Password ??
          _md5(
            password ?? (throw ArgumentError('password or captcha required')),
          );
    }
    final resp = await _request.send(
      'POST',
      'https://music.163.com/weapi/login/cellphone',
      data,
      crypto: CryptoMode.weapi,
    );
    if (resp.status == 200) _absorb(resp);
    return resp.body;
  }

  /// Send an SMS captcha to a phone number.
  Future<Map<String, dynamic>> sendCaptcha(
    String phone, {
    String ctcode = '86',
  }) async {
    final resp = await _request.send(
      'POST',
      'https://music.163.com/weapi/sms/captcha/sent',
      {'cellphone': phone, 'ctcode': ctcode},
      crypto: CryptoMode.weapi,
    );
    return resp.body;
  }

  /// Current login status / account info.
  Future<Map<String, dynamic>> loginStatus() async {
    final resp = await _request.send(
      'POST',
      'https://music.163.com/weapi/w/nuser/account/get',
      {},
      crypto: CryptoMode.weapi,
    );
    return resp.body;
  }

  /// Full account object (uid lives at body['profile']['userId']).
  Future<Map<String, dynamic>> userAccount() async {
    final resp = await _request.send(
      'POST',
      'https://music.163.com/api/nuser/account/get',
      {},
      crypto: CryptoMode.weapi,
    );
    return resp.body;
  }

  /// Log out and clear the local session.
  Future<void> logout() async {
    await _request.send(
      'POST',
      'https://music.163.com/weapi/logout',
      {},
      crypto: CryptoMode.weapi,
    );
    cookieJar.clear();
  }

  // ============================================================
  // Songs
  // ============================================================

  /// Playable URL(s) for one or more song ids (v1 quality tiers).
  ///
  /// Requires a logged-in session for high tiers / member tracks. Returns the
  /// `data` list; each item has `url`, `br`, `size`, `level`, `type`, etc.
  Future<List<dynamic>> songUrl(
    List<int> ids, {
    SongLevel level = SongLevel.exhigh,
  }) async {
    cookieJar['os'] = 'pc';
    final resp = await _request.send(
      'POST',
      'https://interface.music.163.com/eapi/song/enhance/player/url/v1',
      {'ids': jsonEncode(ids), 'level': level.wire, 'encodeType': 'flac'},
      crypto: CryptoMode.eapi,
      eapiUrl: '/api/song/enhance/player/url/v1',
    );
    if (resp.status != 200) {
      throw ApiException(resp.status, 'song url failed', resp.body);
    }
    return (resp.body['data'] as List?) ?? const [];
  }

  /// Detailed metadata for song ids. Returns the `songs` list.
  Future<List<dynamic>> songDetail(List<int> ids) async {
    final c = ids.map((id) => '{"id":$id}').join(',');
    final resp = await _request.send(
      'POST',
      'https://music.163.com/api/v3/song/detail',
      {'c': '[$c]'},
      crypto: CryptoMode.weapi,
    );
    return (resp.body['songs'] as List?) ?? const [];
  }

  /// Lyrics (original + translation + romaji). Returns the raw body; the
  /// original LRC lives at body['lrc']['lyric'].
  Future<Map<String, dynamic>> lyric(int id) async {
    cookieJar['os'] = 'ios';
    final resp = await _request.send(
      'POST',
      'https://music.163.com/api/song/lyric?_nmclfl=1',
      {'id': id, 'tv': -1, 'lv': -1, 'rv': -1, 'kv': -1},
      crypto: CryptoMode.api,
    );
    return resp.body;
  }

  /// Song availability / playability check. Returns the raw body
  /// (body['success'] == true when playable).
  Future<Map<String, dynamic>> checkMusic(
    int id, {
    SongLevel level = SongLevel.exhigh,
  }) async {
    final urls = await songUrl([id], level: level);
    final playable = urls.isNotEmpty && urls.first['url'] != null;
    return {'success': playable, 'message': playable ? 'ok' : '亲爱的,暂无版权'};
  }

  // ============================================================
  // Search
  // ============================================================

  Future<Map<String, dynamic>> search(
    String keywords, {
    SearchType type = SearchType.song,
    int limit = 30,
    int offset = 0,
  }) async {
    final resp = await _request.send(
      'POST',
      'https://interface.music.163.com/eapi/cloudsearch/pc',
      {
        's': keywords,
        'type': type.code,
        'limit': limit,
        'offset': offset,
        'total': true,
      },
      crypto: CryptoMode.eapi,
      eapiUrl: '/api/cloudsearch/pc',
    );
    return resp.body;
  }

  /// Search suggestions as you type.
  Future<Map<String, dynamic>> searchSuggest(String keywords) async {
    final resp = await _request.send(
      'POST',
      'https://music.163.com/weapi/search/suggest/web',
      {'s': keywords},
      crypto: CryptoMode.weapi,
    );
    return resp.body;
  }

  // ============================================================
  // Playlists
  // ============================================================

  /// A user's playlists. Returns the `playlist` list.
  Future<List<dynamic>> userPlaylists(
    int uid, {
    int limit = 30,
    int offset = 0,
  }) async {
    final resp = await _request.send(
      'POST',
      'https://music.163.com/api/user/playlist',
      {'uid': uid, 'limit': limit, 'offset': offset, 'includeVideo': true},
      crypto: CryptoMode.weapi,
    );
    return (resp.body['playlist'] as List?) ?? const [];
  }

  /// Playlist metadata + ordered track ids. Returns the raw body; the
  /// playlist object is body['playlist'].
  Future<Map<String, dynamic>> playlistDetail(int id) async {
    final resp = await _request.send(
      'POST',
      'https://music.163.com/api/v6/playlist/detail',
      {'id': id, 'n': 100000, 's': 8},
      crypto: CryptoMode.api,
    );
    return resp.body;
  }

  /// Ordered ids for a playlist. Metadata is intentionally resolved a page at
  /// a time with [songDetail] so very large playlists stay bounded.
  Future<List<int>> playlistTrackIds(int id) async {
    final detail = await playlistDetail(id);
    final trackIds = (detail['playlist']?['trackIds'] as List?) ?? const [];
    return trackIds
        .map((item) => ((item as Map)['id'] as num).toInt())
        .toList(growable: false);
  }

  /// Full liked-song id set for a user. The liked playlist's normal detail
  /// route can be truncated, while this account endpoint is authoritative.
  Future<List<int>> likedSongIds(int uid) async {
    final resp = await _request.send(
      'POST',
      'https://music.163.com/api/song/like/get',
      {'uid': uid},
      crypto: CryptoMode.weapi,
    );
    final ids = (resp.body['ids'] as List?) ?? const [];
    return ids.map((id) => (id as num).toInt()).toList(growable: false);
  }

  /// Full song objects for one playlist page.
  Future<List<dynamic>> playlistTracks(
    int id, {
    int limit = 100,
    int offset = 0,
  }) async {
    final ids = await playlistTrackIds(id);
    if (offset >= ids.length) return const [];
    return songDetail(ids.skip(offset).take(limit).toList(growable: false));
  }

  // ============================================================
  // Discovery
  // ============================================================

  /// Personalized recommended playlists (requires login for best results).
  Future<List<dynamic>> recommendPlaylists({int limit = 30}) async {
    final resp = await _request.send(
      'POST',
      'https://music.163.com/weapi/personalized/playlist',
      {'limit': limit, 'total': true, 'n': 1000},
      crypto: CryptoMode.weapi,
    );
    return (resp.body['result'] as List?) ?? const [];
  }

  /// Daily recommended songs (login required). Returns the `dailySongs` list.
  Future<List<dynamic>> recommendSongs() async {
    final resp = await _request.send(
      'POST',
      'https://music.163.com/api/v3/discovery/recommend/songs',
      {},
      crypto: CryptoMode.weapi,
    );
    return (resp.body['data']?['dailySongs'] as List?) ?? const [];
  }

  static String _md5(String s) => c.md5.convert(utf8.encode(s)).toString();
}
