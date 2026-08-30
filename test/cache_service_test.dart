import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsnc/services/cache_service.dart';

void main() {
  test('playlist cache evicts the least recently used bytes', () async {
    final directory = await Directory.systemTemp.createTemp('nsnc_cache_test_');
    addTearDown(() => directory.delete(recursive: true));

    Map<String, dynamic> value(String marker) => {
      'marker': marker,
      'payload': marker * 64,
    };
    int size(Map<String, dynamic> value) =>
        utf8.encode(jsonEncode(value)).length;

    final first = value('a');
    final second = value('b');
    final third = value('c');
    final cache = await PlaylistCache.open(
      directory: directory,
      maxBytes: 100000,
    );

    await cache.write('first', first);
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await cache.write('second', second);
    await Future<void>.delayed(const Duration(milliseconds: 2));
    expect(await cache.read('first'), first);
    await Future<void>.delayed(const Duration(milliseconds: 2));

    cache.maxBytes = size(first) + size(third);
    await cache.write('third', third);

    expect(await cache.read('first'), first);
    expect(await cache.read('second'), isNull);
    expect(await cache.read('third'), third);
  });

  test('playlist cache index survives reopening', () async {
    final directory = await Directory.systemTemp.createTemp('nsnc_cache_test_');
    addTearDown(() => directory.delete(recursive: true));

    final cache = await PlaylistCache.open(
      directory: directory,
      maxBytes: 100000,
    );
    await cache.write('playlist:7:index', {
      'ids': [1, 2, 3],
    });

    final reopened = await PlaylistCache.open(
      directory: directory,
      maxBytes: 100000,
    );
    expect(await reopened.read('playlist:7:index'), {
      'ids': [1, 2, 3],
    });
  });
}
