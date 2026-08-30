import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ncm_api/ncm_api.dart';
import 'package:nsnc/services/audio_store.dart';

void main() {
  late Directory root;
  late HttpServer server;
  late Uri baseUri;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('nsnc_audio_store_test_');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUri = Uri.parse('http://${server.address.host}:${server.port}');
    server.listen((request) async {
      final size =
          int.tryParse(request.uri.queryParameters['size'] ?? '') ?? 64;
      request.response.headers.contentType = ContentType.binary;
      request.response.contentLength = size;
      request.response.add(List<int>.generate(size, (i) => i % 251));
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await root.delete(recursive: true);
  });

  test('audio cache evicts least recently used bytes', () async {
    final store = await AudioStore.open(
      rootDirectory: root,
      maxCacheBytes: 130,
    );
    await store.cacheFromUrl(
      trackId: 1,
      level: SongLevel.standard,
      url: '$baseUri/one.mp3?size=60',
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await store.cacheFromUrl(
      trackId: 2,
      level: SongLevel.standard,
      url: '$baseUri/two.mp3?size=60',
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));
    expect(await store.localForPlayback(1, SongLevel.standard), isNotNull);
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await store.cacheFromUrl(
      trackId: 3,
      level: SongLevel.standard,
      url: '$baseUri/three.mp3?size=60',
    );

    expect(await store.localForPlayback(1, SongLevel.standard), isNotNull);
    expect(await store.localForPlayback(2, SongLevel.standard), isNull);
    expect(await store.localForPlayback(3, SongLevel.standard), isNotNull);
  });

  test(
    'download survives cache clear and wins across quality levels',
    () async {
      var store = await AudioStore.open(
        rootDirectory: root,
        maxCacheBytes: 1024,
      );
      final cached = await store.cacheFromUrl(
        trackId: 7,
        level: SongLevel.standard,
        url: '$baseUri/seven.mp3?size=80',
      );
      final downloaded = await store.promoteCachedDownload(
        7,
        SongLevel.standard,
      );
      expect(downloaded, isNotNull);
      expect(downloaded!.path, isNot(cached.path));

      await store.clearCache();
      expect(await cached.exists(), isFalse);
      expect(await downloaded.exists(), isTrue);
      expect(
        (await store.localForPlayback(7, SongLevel.hires))?.path,
        downloaded.path,
      );

      store = await AudioStore.open(rootDirectory: root, maxCacheBytes: 1024);
      expect(store.isDownloaded(7), isTrue);
      expect(
        (await store.localForPlayback(7, SongLevel.lossless))?.path,
        downloaded.path,
      );
    },
  );
}
