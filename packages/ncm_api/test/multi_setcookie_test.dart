import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:ncm_api/ncm_api.dart';
import 'package:test/test.dart';

/// Reproduces the real login response shape — MANY Set-Cookie headers whose
/// Expires attribute contains a comma — and drives the actual NcmRequest
/// pipeline against a local server. Verifies MUSIC_U survives capture.
///
/// This isolates whether package:http's IOClient collapses repeated
/// Set-Cookie headers (comma-joining them, which corrupts comma-bearing
/// Expires dates) and whether our extraction recovers MUSIC_U regardless.
void main() {
  test('pipeline captures MUSIC_U from many comma-bearing Set-Cookie headers',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4.address, 0);
    // Mimic Netease's 803: a pile of Set-Cookie lines, Expires has a comma.
    const setCookies = [
      'MUSIC_R_T=111; Max-Age=2147483647; Expires=Wed, 01 Jan 2031 00:00:00 GMT; Path=/nresource',
      'MUSIC_A_T=222; Max-Age=2147483647; Expires=Wed, 01 Jan 2031 00:00:00 GMT; Path=/eapi',
      '__csrf=csrftok; Max-Age=1296000; Expires=Fri, 01 Jan 2027 00:00:00 GMT; Path=/',
      'MUSIC_U=THE_REAL_SESSION_TOKEN_834_CHARS; Max-Age=1296000; Expires=Fri, 01 Jan 2027 00:00:00 GMT; Path=/',
      'MUSIC_R_U=333; Max-Age=2147483647; Expires=Wed, 01 Jan 2031 00:00:00 GMT; Path=/nresource',
    ];

    server.listen((req) {
      final r = req.response;
      r.statusCode = 200;
      r.headers.contentType = ContentType.json;
      for (final c in setCookies) {
        r.headers.add(HttpHeaders.setCookieHeader, c);
      }
      r.write(jsonEncode({'code': 803, 'message': 'ok'}));
      r.close();
    });

    final port = server.port;
    final jar = CookieJar();
    final req = NcmRequest(cookieJar: jar, client: http.Client());

    // crypto:api = plain POST, no rewrite — hits our local server directly.
    final resp = await req.send(
      'POST',
      'http://${InternetAddress.loopbackIPv4.address}:$port/check',
      {},
      crypto: CryptoMode.api,
    );

    // Diagnostic: how many Set-Cookie lines did the pipeline actually see?
    // (If IOClient collapsed them, this is 1 comma-joined blob.)
    printOnFailure('resp.cookies (${resp.cookies.length}): ${resp.cookies}');

    jar.ingestSetCookies(resp.cookies);

    req.close();
    await server.close(force: true);

    expect(jar['MUSIC_U'], 'THE_REAL_SESSION_TOKEN_834_CHARS',
        reason: 'MUSIC_U must be captured despite comma-bearing Expires and '
            'multiple Set-Cookie headers');
    expect(jar.isLoggedIn, isTrue);
  });
}
