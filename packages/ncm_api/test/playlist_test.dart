import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ncm_api/ncm_api.dart';
import 'package:test/test.dart';

void main() {
  test('playlistTrackIds preserves the server playlist order', () async {
    late Uri seen;
    final client = NcmClient(
      httpClient: MockClient((request) async {
        seen = request.url;
        return http.Response.bytes(
          utf8.encode(
            '{"code":200,"playlist":{"trackIds":['
            '{"id":31},{"id":12},{"id":99}]}}',
          ),
          200,
        );
      }),
    );

    final ids = await client.playlistTrackIds(1234);

    expect(ids, [31, 12, 99]);
    expect(seen.host, 'music.163.com');
    expect(seen.path, '/api/v6/playlist/detail');
    client.close();
  });

  test('likedSongIds uses the authoritative account endpoint', () async {
    late Uri seen;
    final client = NcmClient(
      httpClient: MockClient((request) async {
        seen = request.url;
        return http.Response.bytes(
          utf8.encode('{"code":200,"ids":[8,5,3,2,1]}'),
          200,
        );
      }),
    );

    final ids = await client.likedSongIds(42);

    expect(ids, [8, 5, 3, 2, 1]);
    expect(seen.host, 'music.163.com');
    expect(seen.path, '/weapi/song/like/get');
    client.close();
  });
}
