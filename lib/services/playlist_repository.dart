import 'package:ncm_api/ncm_api.dart';

import 'cache_service.dart';

class PlaylistPage {
  const PlaylistPage({required this.songs, required this.total});

  final List<Map<String, dynamic>> songs;
  final int total;
}

/// Cached, page-bounded access to playlist metadata and tracks.
class PlaylistRepository {
  factory PlaylistRepository({
    required NcmClient client,
    required PlaylistCache cache,
  }) => PlaylistRepository._(client, cache);

  PlaylistRepository._(this._client, this._cache);

  static const pageSize = 100;

  final NcmClient _client;
  final PlaylistCache _cache;

  Future<List<Map<String, dynamic>>> userPlaylists(
    int uid, {
    bool refresh = false,
  }) async {
    final key = 'user:$uid:playlists';
    if (!refresh) {
      final cached = await _cache.read(key);
      final playlists = cached?['playlists'] as List?;
      if (playlists != null) return _maps(playlists);
    }
    final playlists = _maps(await _client.userPlaylists(uid, limit: 1000));
    await _cache.write(key, {'playlists': playlists});
    return playlists;
  }

  Future<PlaylistPage> page({
    required int playlistId,
    required int page,
    int? likedSongsUid,
    bool refresh = false,
  }) async {
    if (page < 0) throw RangeError.value(page, 'page');
    final prefix = 'playlist:$playlistId:';
    if (refresh) await _cache.removePrefix(prefix);

    final ids = await _trackIds(playlistId, likedSongsUid: likedSongsUid);
    final offset = page * pageSize;
    if (offset >= ids.length) {
      return PlaylistPage(songs: const [], total: ids.length);
    }

    final pageKey = '${prefix}page:$page';
    final expectedIds = ids.skip(offset).take(pageSize).toList(growable: false);
    final cached = await _cache.read(pageKey);
    final cachedIds = (cached?['ids'] as List?)
        ?.map((id) => (id as num).toInt())
        .toList(growable: false);
    if (_sameIds(cachedIds, expectedIds)) {
      final songs = cached?['songs'] as List?;
      if (songs != null) {
        return PlaylistPage(songs: _maps(songs), total: ids.length);
      }
    }

    final songs = _maps(await _client.songDetail(expectedIds));
    await _cache.write(pageKey, {'ids': expectedIds, 'songs': songs});
    return PlaylistPage(songs: songs, total: ids.length);
  }

  Future<List<int>> _trackIds(int playlistId, {int? likedSongsUid}) async {
    final key = 'playlist:$playlistId:index';
    final cached = await _cache.read(key);
    final rawIds = cached?['ids'] as List?;
    final expectedOrderVersion = likedSongsUid == null ? 1 : 2;
    if (rawIds != null && cached?['orderVersion'] == expectedOrderVersion) {
      return rawIds.map((id) => (id as num).toInt()).toList(growable: false);
    }

    final List<int> ids;
    if (likedSongsUid == null) {
      final detail = await _client.playlistDetail(playlistId);
      await _writeMeta(playlistId, detail);
      ids = _idsOf(detail);
    } else {
      final responses = await Future.wait<Object>([
        _client.playlistDetail(playlistId),
        _client.likedSongIds(likedSongsUid),
      ]);
      final detail = responses[0] as Map<String, dynamic>;
      await _writeMeta(playlistId, detail);
      ids = _orderedLikedIds(_idsOf(detail), responses[1] as List<int>);
    }
    await _cache.write(key, {'orderVersion': expectedOrderVersion, 'ids': ids});
    return ids;
  }

  /// Display metadata (name, cover, description, creator, counts).
  Future<Map<String, dynamic>> meta(
    int playlistId, {
    bool refresh = false,
  }) async {
    final key = 'playlist:$playlistId:meta';
    if (!refresh) {
      final cached = await _cache.read(key);
      if (cached != null) return cached;
    }
    final detail = await _client.playlistDetail(playlistId);
    return _writeMeta(playlistId, detail);
  }

  Future<Map<String, dynamic>> _writeMeta(
    int playlistId,
    Map<String, dynamic> detail,
  ) async {
    final p = (detail['playlist'] as Map?) ?? const {};
    final creator = p['creator'] as Map?;
    final meta = <String, dynamic>{
      'name': p['name'],
      'coverImgUrl': p['coverImgUrl'],
      'description': p['description'],
      'creator': creator?['nickname'],
      'creatorAvatar': creator?['avatarUrl'],
      'trackCount': p['trackCount'],
      'playCount': p['playCount'],
      'subscribedCount': p['subscribedCount'],
      'updateTime': p['updateTime'] ?? p['trackUpdateTime'],
      'tags': p['tags'],
    };
    await _cache.write('playlist:$playlistId:meta', meta);
    return meta;
  }

  static List<int> _idsOf(Map<String, dynamic> detail) {
    final trackIds = (detail['playlist']?['trackIds'] as List?) ?? const [];
    return trackIds
        .map((item) => ((item as Map)['id'] as num).toInt())
        .toList(growable: false);
  }

  static List<int> _orderedLikedIds(
    List<int> playlistOrder,
    List<int> authoritativeIds,
  ) {
    final remaining = authoritativeIds.toSet();
    final ordered = <int>[];
    for (final id in playlistOrder) {
      if (remaining.remove(id)) ordered.add(id);
    }
    for (final id in authoritativeIds) {
      if (remaining.remove(id)) ordered.add(id);
    }
    return ordered;
  }

  static List<Map<String, dynamic>> _maps(List<dynamic> values) => values
      .map((value) => Map<String, dynamic>.from(value as Map))
      .toList(growable: false);

  static bool _sameIds(List<int>? left, List<int> right) {
    if (left == null || left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }
}
