import 'dart:convert';

import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:ncm_api/ncm_api.dart';
import 'package:test/test.dart';

/// Verifies the login cookie capture chain WITHOUT a live account:
/// a mocked 803 QR-check response carrying Set-Cookie: MUSIC_U must land in
/// the jar and survive toMap/fromMap persistence.
void main() {
  test('QR check 803 captures MUSIC_U into the jar', () async {
    // Server returns the authorized code + login cookies.
    final mock = MockClient((req) async {
      return http.Response.bytes(
        utf8.encode('{"code":803,"message":"authorized"}'),
        200,
        headers: {
          // http's MockClient joins these; the pipeline must still split them.
          'set-cookie':
              'MUSIC_U=abc123deftoken; Max-Age=1234567890; Expires=Wed, 01 Jan 2031 00:00:00 GMT; Path=/; HTTPOnly, '
                  '__csrf=csrftok123; Max-Age=1234567890; Path=/; HTTPOnly',
        },
      );
    });
    final client = NcmClient(httpClient: mock);
    final resp = await client.loginQrCheck('some-unikey');

    expect(resp.body['code'], 803);
    expect(client.cookieJar.isLoggedIn, isTrue,
        reason: 'MUSIC_U should be captured from Set-Cookie');
    expect(client.cookieJar['MUSIC_U'], 'abc123deftoken');

    // Persistence round-trip keeps the session.
    final restored = CookieJar.fromMap(client.cookieJar.toMap());
    expect(restored.isLoggedIn, isTrue);
    expect(restored['MUSIC_U'], 'abc123deftoken');

    client.close();
  });

  test('logged-in loginStatus profile lives at the top level', () async {
    // Mock account/get returning a profile (as the live server does).
    final mock = MockClient((req) async {
      return http.Response(
        '{"code":200,"account":{"id":42},"profile":{"userId":42,"nickname":"tester"}}',
        200,
      );
    });
    final client = NcmClient(httpClient: mock);
    final body = await client.loginStatus();
    // This is the shape refreshProfile relies on: profile at top level.
    expect(body['profile'], isNotNull);
    expect((body['profile'] as Map)['userId'], 42);
    client.close();
  });
}
