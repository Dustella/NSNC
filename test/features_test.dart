import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ncm_api/ncm_api.dart';
import 'package:nsnc/models/media_item.dart';
import 'package:nsnc/models/track.dart';
import 'package:nsnc/services/ui_preferences.dart';
import 'package:nsnc/theme/nsnc_theme.dart';
import 'package:nsnc/ui/widgets/common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Track', () {
    test('keeps album and artist ids for navigation', () {
      final track = Track.fromJson({
        'id': 1,
        'name': 'Song',
        'ar': [
          {'id': 10, 'name': 'A'},
          {'id': 0, 'name': 'B'},
        ],
        'al': {
          'id': 20,
          'name': 'Album',
          'picUrl': 'https://p1.music.126.net/x.jpg',
        },
        'dt': 1000,
        'fee': 1,
      });
      expect(track.artistIds, [10, 0]);
      expect(track.albumId, 20);
      expect(track.isVip, isTrue);
    });

    test('treats album id 0 as unknown', () {
      final track = Track.fromJson({
        'id': 1,
        'name': 'Upload',
        'ar': const [],
        'al': {'id': 0, 'name': ''},
      });
      expect(track.albumId, isNull);
      expect(track.artists, ['未知艺术家']);
    });
  });

  group('MediaItem', () {
    test('parses playlists with liked flag and play-count badge', () {
      final item = MediaItem.playlist({
        'id': 7,
        'name': '我喜欢的音乐',
        'trackCount': 321,
        'playCount': 123456,
        'specialType': 5,
        'coverImgUrl': 'c',
        'creator': {'userId': 42, 'nickname': 'me'},
      });
      expect(item.isLikedPlaylist, isTrue);
      expect(item.subtitle, '321 首 · me');
      expect(item.badge, '12.3万');
      expect(item.creatorId, 42);
    });

    test('parses radios and charts', () {
      final radio = MediaItem.radio({
        'id': 3,
        'name': 'Radio',
        'programCount': 12,
        'category': '情感',
        'dj': {'nickname': 'DJ'},
      });
      expect(radio.kind, MediaKind.radio);
      expect(radio.subtitle, 'DJ · 12 期');
      final chart = MediaItem.chart({
        'id': 19723756,
        'name': '飙升榜',
        'updateFrequency': '每天更新',
      });
      expect(chart.kind, MediaKind.chart);
      expect(chart.badge, '每天更新');
    });

    test('radio programs play their main song under the program name', () {
      final program = RadioProgram.tryParse({
        'id': 99,
        'name': '第 1 期',
        'coverUrl': 'cover',
        'duration': 60000,
        'radio': {'name': '好电台'},
        'mainSong': {
          'id': 5,
          'name': 'raw',
          'artists': const [],
          'album': {'name': ''},
          'duration': 1,
        },
      })!;
      expect(program.track.id, 5);
      expect(program.track.name, '第 1 期');
      expect(program.track.albumArtUrl, 'cover');
      expect(program.track.artists, ['好电台']);
      expect(program.track.durationMs, 60000);
      expect(RadioProgram.tryParse({'id': 1}), isNull);
    });

    test('cloud songs fall back to file tags', () {
      final song = CloudSong.tryParse({
        'songId': 77,
        'fileName': 'a.flac',
        'fileSize': 2048,
        'artist': 'Tag Artist',
        'album': 'Tag Album',
        'simpleSong': {
          'name': 'Uploaded',
          'ar': [
            {'name': ''},
          ],
          'al': {'name': ''},
        },
      })!;
      expect(song.track.id, 77);
      expect(song.track.artists, ['Tag Artist']);
      expect(song.track.album, 'Tag Album');
      expect(formatBytes(song.fileSize), '2.0 KB');
    });
  });

  test('sizes Netease cover urls only', () {
    expect(
      sizedCoverUrl('https://p1.music.126.net/a.jpg', 200),
      'https://p1.music.126.net/a.jpg?param=200y200',
    );
    expect(
      sizedCoverUrl('https://example.com/a.jpg', 200),
      'https://example.com/a.jpg',
    );
    expect(sizedCoverUrl(null, 200), isNull);
  });

  group('UiPreferences', () {
    test('persists choices and per-surface layouts', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final ui = UiPreferences.forTesting(prefs);
      expect(ui.layoutFor(LayoutSurface.charts), CollectionLayout.grid);

      await ui.setAccent(NsncAccent.ocean);
      await ui.setThemeMode(ThemeMode.dark);
      await ui.setLayout(LayoutSurface.charts, CollectionLayout.list);
      await ui.setSection(HomeSection.radios, false);
      await ui.setLyricScale(3);

      final reloaded = UiPreferences.forTesting(prefs);
      expect(reloaded.accent, NsncAccent.ocean);
      expect(reloaded.themeMode, ThemeMode.dark);
      expect(reloaded.layoutFor(LayoutSurface.charts), CollectionLayout.list);
      expect(reloaded.layoutFor(LayoutSurface.radios), CollectionLayout.grid);
      expect(reloaded.showsSection(HomeSection.radios), isFalse);
      expect(reloaded.showsSection(HomeSection.daily), isTrue);
      expect(reloaded.lyricScale, 1.6);

      await reloaded.setDefaultLayout(CollectionLayout.list);
      expect(reloaded.layoutFor(LayoutSurface.charts), CollectionLayout.list);
      expect(
        UiPreferences.forTesting(prefs).layoutFor(LayoutSurface.radios),
        CollectionLayout.list,
      );
    });

    test('keeps recent searches unique, newest first and bounded', () async {
      SharedPreferences.setMockInitialValues({});
      final ui = UiPreferences.forTesting(
        await SharedPreferences.getInstance(),
      );
      for (var i = 0; i < 20; i++) {
        await ui.addRecentSearch('k$i');
      }
      await ui.addRecentSearch(' k5 ');
      expect(ui.recentSearches.first, 'k5');
      expect(ui.recentSearches.length, UiPreferences.maxRecentSearches);
      expect(ui.recentSearches.where((s) => s == 'k5').length, 1);
    });
  });

  group('NcmClient endpoints', () {
    NcmClient clientFor(Map<String, Object> routes, List<String> seen) =>
        NcmClient(
          httpClient: MockClient((request) async {
            seen.add(request.url.path);
            final body = routes[request.url.path];
            if (body == null) throw StateError('Unexpected ${request.url}');
            return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
          }),
        );

    test('reads cloud drive and radio programs', () async {
      final seen = <String>[];
      final client = clientFor({
        '/weapi/v1/cloud/get': {
          'code': 200,
          'count': 1,
          'size': '10',
          'maxSize': '100',
          'data': [
            {'songId': 1},
          ],
        },
        '/weapi/dj/program/byradio': {
          'code': 200,
          'count': 2,
          'more': false,
          'programs': const [],
        },
      }, seen);
      addTearDown(client.close);

      final cloud = await client.userCloud();
      expect(cloud['count'], 1);
      final programs = await client.djPrograms(3);
      expect(programs['count'], 2);
      expect(seen, ['/weapi/v1/cloud/get', '/weapi/dj/program/byradio']);
    });

    test('surfaces failed writes as ApiException', () async {
      final client = clientFor({
        '/weapi/radio/like': {'code': 301, 'msg': 'need login'},
      }, []);
      addTearDown(client.close);
      expect(
        () => client.likeSong(1),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 301)),
      );
    });

    test('rejects writes whose body code is a passthrough 400/502', () async {
      final client = clientFor({
        '/weapi/cloud/del': {'code': 400, 'msg': 'invalid'},
        '/weapi/radio/like': {'code': 502, 'msg': 'busy'},
        '/weapi/djradio/sub': {'code': 400},
        '/weapi/radio/trash/add': {'code': 502},
      }, []);
      addTearDown(client.close);
      Matcher failsWith(int code) =>
          throwsA(isA<ApiException>().having((e) => e.status, 'status', code));
      await expectLater(client.userCloudDelete([1]), failsWith(400));
      await expectLater(client.likeSong(1), failsWith(502));
      await expectLater(client.djSubscribe(1), failsWith(400));
      await expectLater(client.fmTrash(1), failsWith(502));
    });

    test('accepts writes with body code 200', () async {
      final client = clientFor({
        '/weapi/cloud/del': {'code': 200},
      }, []);
      addTearDown(client.close);
      await client.userCloudDelete([1]);
    });
  });

  test('Material theme follows the active MIUIX palette', () {
    final colors = miuixColorsFromSeed(
      seed: NsncAccent.ocean.color,
      dark: false,
    );
    final theme = NsncTheme.light(miuix: colors);
    expect(theme.colorScheme.primary, colors.primary);
    expect(theme.colorScheme.surface, colors.surface);
    expect(theme.brightness, Brightness.light);
  });

  test('describes common API errors for people', () {
    expect(describeError(ApiException(301, 'x')), '登录已过期，请重新登录');
    expect(
      describeError(ApiException(502, 'transport error: boom')),
      contains('网络'),
    );
  });
}
