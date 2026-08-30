import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ncm_api/ncm_api.dart';
import 'package:nsnc/services/cache_service.dart';
import 'package:nsnc/services/playlist_repository.dart';

void main() {
  test('liked playlist keeps playlist order and appends authoritative-only ids', () async {
    final directory = await Directory.systemTemp.createTemp(
      'nsnc_liked_order_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final cache = await PlaylistCache.open(
      directory: directory,
      maxBytes: 100000,
    );
    await cache.write('playlist:7:index', {
      'orderVersion': 1,
      'ids': [999],
    });

    final requestedPaths = <String>[];
    final client = NcmClient(
      httpClient: MockClient((request) async {
        requestedPaths.add(request.url.path);
        final body = switch (request.url.path) {
          '/api/v6/playlist/detail' =>
            '{"code":200,"playlist":{"trackIds":['
                '{"id":3},{"id":1},{"id":4}]}}',
          '/weapi/song/like/get' => '{"code":200,"ids":[4,3,2]}',
          '/weapi/v3/song/detail' =>
            '{"code":200,"songs":[{"id":3},{"id":4},{"id":2}]}',
          _ => throw StateError('Unexpected request: ${request.url}'),
        };
        return http.Response.bytes(utf8.encode(body), 200);
      }),
    );
    addTearDown(client.close);
    final repository = PlaylistRepository(client: client, cache: cache);

    final page = await repository.page(
      playlistId: 7,
      page: 0,
      likedSongsUid: 42,
    );

    expect(page.songs.map((song) => song['id']), [3, 4, 2]);
    expect(requestedPaths, contains('/api/v6/playlist/detail'));
    expect(requestedPaths, contains('/weapi/song/like/get'));
    expect((await cache.read('playlist:7:index'))?['orderVersion'], 2);
    expect((await cache.read('playlist:7:index'))?['ids'], [3, 4, 2]);
  });
}
