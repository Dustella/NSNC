import 'dart:convert';

import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:ncm_api/ncm_api.dart';
import 'package:test/test.dart';

/// Regression guard for the QR login channel. The live root cause: the unikey
/// and the status check MUST both travel the eapi @ interface(pc) channel.
/// A unikey minted on weapi @ music.163.com binds to a different context, so
/// the server returns 803 on check but withholds MUSIC_U — and music.163.com's
/// CDN strips Set-Cookie anyway. These tests fail if login ever reverts to the
/// weapi/music.163.com path or drops MUSIC_U capture.
void main() {
  test('loginQrKey uses eapi @ interface host', () async {
    late Uri seen;
    final mock = MockClient((req) async {
      seen = req.url;
      return http.Response.bytes(
        utf8.encode('{"code":200,"unikey":"UK-123"}'),
        200,
      );
    });
    final client = NcmClient(httpClient: mock);
    final key = await client.loginQrKey();

    expect(key, 'UK-123');
    expect(seen.host, 'interface.music.163.com');
    expect(seen.path, contains('/eapi/login/qrcode/unikey'));
    client.close();
  });

  test('loginQrCheck uses eapi @ interfacepc host', () async {
    late Uri seen;
    final mock = MockClient((req) async {
      seen = req.url;
      return http.Response.bytes(utf8.encode('{"code":801}'), 200);
    });
    final client = NcmClient(httpClient: mock);
    await client.loginQrCheck('UK-123');

    expect(seen.host, 'interfacepc.music.163.com');
    expect(seen.path, contains('/eapi/login/qrcode/client/login'));
    client.close();
  });

  test('803 with the real multi Set-Cookie shape captures MUSIC_U', () async {
    // Mirror the live 803: many repeated Set-Cookie lines, comma-bearing
    // Expires, MUSIC_U buried in the middle. http's MockClient joins repeated
    // headers with ", " — the pipeline must still recover MUSIC_U.
    const cookies = [
      'MUSIC_R_T=1454311071243; Max-Age=2147483647; Expires=Thu, 16 Sep 2094 00:00:00 GMT; Path=/nresource',
      'MUSIC_A_T=1454310986056; Max-Age=2147483647; Expires=Thu, 16 Sep 2094 00:00:00 GMT; Path=/eapi',
      'MUSIC_SNS=; Max-Age=0; Expires=Sat, 29 Aug 2026 16:46:02 GMT; Path=/',
      'MUSIC_U=00BC8FAB5FE05A08474F765E2924DB8FAABREALTOKEN; Max-Age=1296010; Expires=Sun, 13 Sep 2026 00:00:00 GMT; Path=/',
      'MUSIC_R_U=00658BA637EDC611D176; Max-Age=2147483647; Expires=Thu, 16 Sep 2094 00:00:00 GMT; Path=/nresource',
      '__csrf=5e5e9295333442e59971183a27523c73; Max-Age=1296010; Expires=Sun, 13 Sep 2026 00:00:00 GMT; Path=/',
    ];
    final mock = MockClient((req) async {
      return http.Response.bytes(
        utf8.encode('{"code":803,"message":"authorized"}'),
        200,
        headers: {'set-cookie': cookies.join(', ')},
      );
    });
    final client = NcmClient(httpClient: mock);
    final resp = await client.loginQrCheck('UK-123');

    expect(resp.body['code'], 803);
    expect(client.cookieJar.isLoggedIn, isTrue,
        reason: 'MUSIC_U must be captured from the 803 cookie set');
    expect(client.cookieJar['MUSIC_U'],
        '00BC8FAB5FE05A08474F765E2924DB8FAABREALTOKEN');
    expect(client.cookieJar['__csrf'], '5e5e9295333442e59971183a27523c73');

    // Survives persistence (restart path).
    final restored = CookieJar.fromMap(client.cookieJar.toMap());
    expect(restored.isLoggedIn, isTrue);
    client.close();
  });
}
