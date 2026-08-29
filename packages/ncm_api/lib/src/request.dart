import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'cookie_jar.dart';
import 'crypto.dart';
import 'device.dart';

/// Encryption scheme selector for a request.
enum CryptoMode { weapi, eapi, linuxapi, api }

/// Anonymous guest token. Sent as MUSIC_A when no MUSIC_U (logged-in) cookie
/// is present. The classic weapi/api register/anonimous endpoints now reject
/// this path (code 400); a fresh token requires the xeapi register flow. Kept
/// as a last-resort fallback for guest reads that still accept it.
const String kAnonymousToken =
    'bf8bfeabb1aa84f9c8c3906c04a04fb864322804c83f5d607e91a04eae463c94'
    '36bd1a17ec353cf780b396507a3f7464e8a60f4bbc019437993166e004087dd3'
    '2d1490298caf655c2353e58daa0bc13cc7d5c198250968580b12c1b8817e3f5c'
    '807e650dd04abd3fb8130b7ae43fcc5b';

/// Result of an API call: decoded JSON body + any cookies the server set.
class ApiResponse {
  ApiResponse({
    required this.status,
    required this.body,
    required this.cookies,
  });

  /// Netease business code (body['code']) when present, else HTTP status.
  final int status;
  final Map<String, dynamic> body;

  /// Raw `Set-Cookie` lines from the response, for the caller to ingest.
  final List<String> cookies;

  bool get ok => status == 200;
}

/// Thrown when a request fails at the transport level or returns a non-200
/// business code the caller wants surfaced.
class ApiException implements Exception {
  ApiException(this.status, this.message, [this.body]);
  final int status;
  final String message;
  final Map<String, dynamic>? body;

  @override
  String toString() => 'ApiException($status): $message';
}

/// Low-level Netease request pipeline. Builds headers + a full device
/// fingerprint cookie set, applies the selected crypto scheme, rewrites the
/// URL, posts form-encoded params, and decodes the response (with the EAPI
/// plaintext/ciphertext fallback the live servers now require).
class NcmRequest {
  NcmRequest({
    required this.cookieJar,
    Device? device,
    http.Client? client,
  })  : device = device ?? Device.generate(),
        _client = client ?? http.Client();

  final CookieJar cookieJar;

  /// Stable device identity used to build the fingerprint cookie set.
  final Device device;

  final http.Client _client;
  final Random _rng = Random.secure();

  void close() => _client.close();

  Future<ApiResponse> send(
    String method,
    String url,
    Map<String, dynamic> data, {
    required CryptoMode crypto,
    String? eapiUrl,
    String? realIP,
    String? userAgent,
  }) async {
    final headers = <String, String>{
      'User-Agent': userAgent ??
          (crypto == CryptoMode.eapi ? device.apiUserAgent : device.weapiUserAgent),
    };
    if (method.toUpperCase() == 'POST') {
      headers['Content-Type'] = 'application/x-www-form-urlencoded';
    }
    if (url.contains('music.163.com')) {
      headers['Referer'] = 'https://music.163.com';
    }
    if (realIP != null && realIP.isNotEmpty) {
      headers['X-Real-IP'] = realIP;
      headers['X-Forwarded-For'] = realIP;
    }

    // Base cookie set: session jar + full device fingerprint. A complete,
    // stable set (deviceId, _ntes_nuid/_nnid, WNMCID, WEVNSM, osver, channel,
    // appver …) is what keeps login off the "device risk" path.
    final cookies = Map<String, String>.from(cookieJar.entries);
    cookies.putIfAbsent('NMTID', () => _randomHex(16));
    device.augmentCookies(cookies);
    if (!cookies.containsKey('MUSIC_U') && !cookies.containsKey('MUSIC_A')) {
      cookies['MUSIC_A'] = kAnonymousToken;
    }

    var payload = Map<String, dynamic>.from(data);
    var requestUrl = url;

    switch (crypto) {
      case CryptoMode.weapi:
        final csrf = cookies['__csrf'] ?? cookies['_csrf'] ?? '';
        payload['csrf_token'] = csrf;
        headers['Cookie'] = _encodeCookies(cookies);
        payload = {...NcmCrypto.weapi(payload)};
        requestUrl = _rewriteApi(url, 'weapi');
        break;

      case CryptoMode.linuxapi:
        headers['Cookie'] = _encodeCookies(cookies);
        headers['User-Agent'] = device.profile == OsProfile.linux
            ? device.apiUserAgent
            : 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/60.0.3112.90 Safari/537.36';
        payload = {
          ...NcmCrypto.linuxapi({
            'method': method,
            'url': _rewriteApi(url, 'api'),
            'params': payload,
          })
        };
        requestUrl = 'https://music.163.com/api/linux/forward';
        break;

      case CryptoMode.eapi:
        final header = _buildEapiHeader(cookies);
        // eapi sends its device header both as a cookie and inside the body.
        headers['Cookie'] = _encodeCookies(header);
        payload['header'] = header;
        payload = {...NcmCrypto.eapi(eapiUrl ?? url, payload)};
        requestUrl = _rewriteApi(url, 'eapi');
        break;

      case CryptoMode.api:
        headers['Cookie'] = _encodeCookies(cookies);
        break;
    }

    final http.Response resp;
    try {
      resp = await _client.post(
        Uri.parse(requestUrl),
        headers: headers,
        body: _formEncode(payload),
      );
    } catch (e) {
      throw ApiException(502, 'transport error: $e');
    }

    final setCookies = _extractSetCookies(resp);
    final body = _decodeBody(resp, crypto);

    var status = (body['code'] is int) ? body['code'] as int : resp.statusCode;
    // Netease "special" codes that still carry a usable payload.
    const passthrough = {201, 302, 400, 502, 800, 801, 802, 803};
    if (passthrough.contains(body['code'])) status = 200;
    if (status <= 100 || status >= 600) status = 400;

    return ApiResponse(status: status, body: body, cookies: setCookies);
  }

  // --- helpers ---

  Map<String, dynamic> _decodeBody(http.Response resp, CryptoMode crypto) {
    final bytes = resp.bodyBytes;
    if (crypto == CryptoMode.eapi) {
      // Live servers return either AES-ECB ciphertext OR plaintext JSON for
      // eapi endpoints. Try decrypt first, then fall back to raw parse.
      try {
        final dec = NcmCrypto.eapiDecrypt(bytes);
        final parsed = jsonDecode(utf8.decode(dec));
        if (parsed is Map<String, dynamic>) return parsed;
      } catch (_) {/* fall through to plaintext */}
    }
    try {
      final parsed = jsonDecode(utf8.decode(bytes));
      if (parsed is Map<String, dynamic>) return parsed;
      return {'data': parsed};
    } catch (_) {
      return {
        'code': resp.statusCode,
        'raw': utf8.decode(bytes, allowMalformed: true),
      };
    }
  }

  /// Rewrite the first `<word>api` segment of the path to the target scheme,
  /// e.g. `/api/v3/song/detail` -> `/weapi/v3/song/detail`.
  static String _rewriteApi(String url, String target) =>
      url.replaceFirst(RegExp(r'\w*api'), target);

  Map<String, String> _buildEapiHeader(Map<String, String> cookies) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final header = <String, String>{
      'osver': cookies['osver'] ?? device.osver,
      'deviceId': cookies['deviceId'] ?? device.deviceId,
      'appver': cookies['appver'] ?? device.appver,
      'versioncode': cookies['versioncode'] ?? '140',
      'mobilename': cookies['mobilename'] ?? '',
      'buildver': cookies['buildver'] ?? (now ~/ 1000).toString(),
      'resolution': cookies['resolution'] ?? '1920x1080',
      '__csrf': cookies['__csrf'] ?? '',
      'os': cookies['os'] ?? device.os,
      'channel': cookies['channel'] ?? device.channel,
      'requestId': '${now}_${_rng.nextInt(1000).toString().padLeft(4, '0')}',
    };
    if (cookies.containsKey('MUSIC_U')) header['MUSIC_U'] = cookies['MUSIC_U']!;
    if (cookies.containsKey('MUSIC_A')) header['MUSIC_A'] = cookies['MUSIC_A']!;
    return header;
  }

  static String _encodeCookies(Map<String, String> cookies) => cookies.entries
      .map((e) =>
          '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
      .join('; ');

  static String _formEncode(Map<String, dynamic> data) => data.entries
      .map((e) =>
          '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value.toString())}')
      .join('&');

  static List<String> _extractSetCookies(http.Response resp) {
    // dart:io strips repeated Set-Cookie into one comma-joined header; the
    // http package exposes it via headersSplitValues on modern versions.
    final split = resp.headersSplitValues['set-cookie'];
    if (split != null && split.isNotEmpty) return split;
    final raw = resp.headers['set-cookie'];
    return raw == null ? const [] : [raw];
  }

  String _randomHex(int bytes) {
    final sb = StringBuffer();
    for (var i = 0; i < bytes; i++) {
      sb.write(_rng.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}
