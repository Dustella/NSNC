import 'package:flutter/material.dart';

import '../models/media_item.dart';
import 'charts_screen.dart';
import 'cloud_screen.dart';
import 'fm_screen.dart';
import 'playlist_screen.dart';
import 'radio_screen.dart';
import 'track_list_screen.dart';

Future<void> _push(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

/// Open whatever [item] points at.
Future<void> openMedia(BuildContext context, MediaItem item, {int? uid}) =>
    switch (item.kind) {
      MediaKind.playlist || MediaKind.chart => _push(
        context,
        PlaylistDetailScreen(
          playlistId: item.id,
          title: item.title,
          coverUrl: item.coverUrl,
          likedSongsUid: item.isLikedPlaylist ? uid : null,
          isChart: item.kind == MediaKind.chart,
        ),
      ),
      MediaKind.album => openAlbum(context, item.id, item.title),
      MediaKind.artist => openArtist(context, item.id, item.title),
      MediaKind.radio => _push(
        context,
        RadioDetailScreen(radioId: item.id, title: item.title),
      ),
    };

Future<void> openAlbum(BuildContext context, int id, String title) => _push(
  context,
  TrackListScreen(
    title: title.isEmpty ? '专辑' : title,
    barTitle: '专辑',
    numbered: true,
    headerIcon: Icons.album_rounded,
    loader: (client) async {
      final body = await client.album(id);
      final album = Map<String, dynamic>.from((body['album'] as Map?) ?? {});
      final artist = album['artist'] as Map?;
      final published = (album['publishTime'] as num?)?.toInt();
      final tracks = parseTracks((body['songs'] as List?) ?? const []);
      return TrackListData(
        tracks: [
          for (final t in tracks)
            t.albumArtUrl == null
                ? t.copyWith(albumArtUrl: album['picUrl']?.toString())
                : t,
        ],
        title: album['name']?.toString(),
        subtitle: artist?['name']?.toString(),
        description: (album['description'] ?? album['briefDesc'])?.toString(),
        coverUrl: album['picUrl']?.toString(),
        meta: [
          if (published != null && published > 0)
            _date(DateTime.fromMillisecondsSinceEpoch(published)),
          if ((album['company'] ?? '').toString().isNotEmpty)
            album['company'].toString(),
          '${tracks.length} 首',
        ],
      );
    },
  ),
);

Future<void> openArtist(BuildContext context, int id, String name) => _push(
  context,
  TrackListScreen(
    title: name.isEmpty ? '歌手' : name,
    barTitle: '歌手',
    circleCover: true,
    headerIcon: Icons.person_rounded,
    loader: (client) async {
      final body = await client.artist(id);
      final artist = Map<String, dynamic>.from((body['artist'] as Map?) ?? {});
      final alias = (artist['alias'] as List?)?.join(' / ') ?? '';
      return TrackListData(
        tracks: parseTracks((body['hotSongs'] as List?) ?? const []),
        title: artist['name']?.toString(),
        subtitle: alias.isEmpty ? '热门 50 首' : alias,
        description: artist['briefDesc']?.toString(),
        coverUrl: (artist['picUrl'] ?? artist['img1v1Url'])?.toString(),
        meta: [
          if ((artist['musicSize'] as num? ?? 0) > 0)
            '${artist['musicSize']} 首歌曲',
          if ((artist['albumSize'] as num? ?? 0) > 0)
            '${artist['albumSize']} 张专辑',
        ],
      );
    },
  ),
);

Future<void> openDailySongs(BuildContext context) => _push(
  context,
  TrackListScreen(
    title: '每日推荐',
    headerIcon: Icons.today_rounded,
    loader: (client) async {
      final tracks = parseTracks(await client.recommendSongs());
      final now = DateTime.now();
      return TrackListData(
        tracks: tracks,
        subtitle: '${now.month} 月 ${now.day} 日 · 根据你的口味生成',
        meta: const ['每天 6:00 更新'],
      );
    },
  ),
);

Future<void> openRecentSongs(BuildContext context) => _push(
  context,
  TrackListScreen(
    title: '最近播放',
    headerIcon: Icons.history_rounded,
    emptyMessage: '还没有播放记录',
    loader: (client) async {
      final items = await client.recentSongs(limit: 200);
      final tracks = parseTracks(
        items.whereType<Map>().map((e) => e['data']).whereType<Map>(),
      );
      return TrackListData(tracks: tracks, subtitle: '最近 ${tracks.length} 首');
    },
  ),
);

Future<void> openCharts(BuildContext context) =>
    _push(context, const ChartsScreen());

Future<void> openRadioHub(BuildContext context) =>
    _push(context, const RadioHubScreen());

Future<void> openCloud(BuildContext context) =>
    _push(context, const CloudScreen());

Future<void> openPersonalFm(BuildContext context) =>
    _push(context, const PersonalFmScreen());

String _date(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
