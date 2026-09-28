import 'track.dart';

/// What a [MediaItem] opens when tapped.
enum MediaKind { playlist, album, artist, radio, chart }

/// A browsable collection summary (playlist, album, artist, radio, chart)
/// normalized from Netease's many response shapes so the shared card and
/// row widgets can render any of them.
class MediaItem {
  const MediaItem({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle = '',
    this.coverUrl,
    this.badge,
    this.specialType = 0,
    this.creatorId,
  });

  final MediaKind kind;
  final int id;
  final String title;
  final String subtitle;
  final String? coverUrl;

  /// Short overlay text on the cover, e.g. a play count or update cadence.
  final String? badge;

  /// Netease playlist `specialType`; 5 marks the user's liked-songs list.
  final int specialType;

  /// Owner uid for playlists, used to split created vs. collected lists.
  final int? creatorId;

  bool get isLikedPlaylist => kind == MediaKind.playlist && specialType == 5;

  static int _int(Object? value) => (value as num?)?.toInt() ?? 0;
  static String _str(Object? value) => (value ?? '').toString();

  factory MediaItem.playlist(Map<String, dynamic> json) {
    final trackCount = _int(json['trackCount']);
    final creator = json['creator'] as Map?;
    final playCount = _int(json['playCount'] ?? json['playcount']);
    return MediaItem(
      kind: MediaKind.playlist,
      id: _int(json['id']),
      title: _str(json['name']),
      subtitle: [
        if (trackCount > 0) '$trackCount 首',
        if (creator?['nickname'] != null) _str(creator!['nickname']),
      ].join(' · '),
      coverUrl: (json['coverImgUrl'] ?? json['picUrl'])?.toString(),
      badge: playCount > 0 ? formatCount(playCount) : null,
      specialType: _int(json['specialType']),
      creatorId:
          (creator?['userId'] as num?)?.toInt() ?? _nullableInt(json['userId']),
    );
  }

  factory MediaItem.chart(Map<String, dynamic> json) => MediaItem(
    kind: MediaKind.chart,
    id: _int(json['id']),
    title: _str(json['name']),
    subtitle: _str(json['updateFrequency']),
    coverUrl: json['coverImgUrl']?.toString(),
    badge: json['updateFrequency']?.toString(),
  );

  factory MediaItem.album(Map<String, dynamic> json) {
    final artists = (json['artists'] as List?) ?? const [];
    final artist =
        json['artist'] as Map? ?? (artists.isEmpty ? null : artists.first);
    final size = _int(json['size']);
    return MediaItem(
      kind: MediaKind.album,
      id: _int(json['id']),
      title: _str(json['name']),
      subtitle: [
        if (artist?['name'] != null) _str(artist!['name']),
        if (size > 0) '$size 首',
      ].join(' · '),
      coverUrl: (json['picUrl'] ?? json['blurPicUrl'])?.toString(),
    );
  }

  factory MediaItem.artist(Map<String, dynamic> json) {
    final albums = _int(json['albumSize']);
    return MediaItem(
      kind: MediaKind.artist,
      id: _int(json['id']),
      title: _str(json['name']),
      subtitle: albums > 0 ? '$albums 张专辑' : '歌手',
      coverUrl: (json['picUrl'] ?? json['img1v1Url'])?.toString(),
    );
  }

  factory MediaItem.radio(Map<String, dynamic> json) {
    final dj = json['dj'] as Map?;
    final programs = _int(json['programCount']);
    return MediaItem(
      kind: MediaKind.radio,
      id: _int(json['id']),
      title: _str(json['name']),
      subtitle: [
        if (dj?['nickname'] != null) _str(dj!['nickname']),
        if (programs > 0) '$programs 期',
      ].join(' · '),
      coverUrl: json['picUrl']?.toString(),
      badge: json['category']?.toString(),
    );
  }

  static int? _nullableInt(Object? value) => (value as num?)?.toInt();
}

/// Compact Chinese count formatting: 12345 -> 1.2万, 123456789 -> 1.2亿.
String formatCount(int value) {
  if (value >= 100000000) return '${(value / 100000000).toStringAsFixed(1)}亿';
  if (value >= 10000) return '${(value / 10000).toStringAsFixed(1)}万';
  return '$value';
}

/// One radio program, playable through its `mainSong`.
class RadioProgram {
  const RadioProgram({
    required this.id,
    required this.name,
    required this.track,
    this.coverUrl,
    this.description = '',
    this.createTime,
    this.listenerCount = 0,
  });

  final int id;
  final String name;
  final Track track;
  final String? coverUrl;
  final String description;
  final DateTime? createTime;
  final int listenerCount;

  static RadioProgram? tryParse(Map<String, dynamic> json) {
    final main = json['mainSong'];
    if (main is! Map || main['id'] == null) return null;
    final cover = json['coverUrl']?.toString();
    final base = Track.fromJson(Map<String, dynamic>.from(main));
    final radio = json['radio'] as Map?;
    final createdMs = (json['createTime'] as num?)?.toInt();
    final name = (json['name'] ?? base.name).toString();
    return RadioProgram(
      id: (json['id'] as num?)?.toInt() ?? base.id,
      name: name,
      // Programs usually lack album art, so use the episode cover instead.
      track: Track(
        id: base.id,
        name: name,
        artists: radio?['name'] != null
            ? [radio!['name'].toString()]
            : base.artists,
        album: (radio?['name'] ?? base.album).toString(),
        durationMs: (json['duration'] as num?)?.toInt() ?? base.durationMs,
        albumArtUrl: cover ?? base.albumArtUrl,
        fee: base.fee,
      ),
      coverUrl: cover,
      description: (json['description'] ?? '').toString(),
      createTime: createdMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(createdMs),
      listenerCount: (json['listenerCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// One song in the user's cloud drive.
class CloudSong {
  const CloudSong({
    required this.track,
    required this.fileName,
    required this.fileSize,
    this.addTime,
  });

  final Track track;
  final String fileName;
  final int fileSize;
  final DateTime? addTime;

  static CloudSong? tryParse(Map<String, dynamic> json) {
    final simple = json['simpleSong'];
    final id =
        (json['songId'] as num?)?.toInt() ??
        (simple is Map ? (simple['id'] as num?)?.toInt() : null);
    if (id == null) return null;
    final song = simple is Map
        ? Map<String, dynamic>.from(simple)
        : <String, dynamic>{'id': id};
    song['id'] = id;
    // Uploaded files often have an empty `ar`/`al`; fall back to the file's
    // own tags so rows still say something useful.
    final artistTag = (json['artist'] ?? '').toString();
    final albumTag = (json['album'] ?? '').toString();
    final ar = song['ar'] as List?;
    if ((ar == null || ar.every((a) => (a?['name'] ?? '') == '')) &&
        artistTag.isNotEmpty) {
      song['ar'] = [
        {'name': artistTag},
      ];
    }
    final al = song['al'] as Map?;
    if ((al == null || (al['name'] ?? '') == '') && albumTag.isNotEmpty) {
      song['al'] = {...?al?.cast<String, dynamic>(), 'name': albumTag};
    }
    song['name'] ??= json['songName'] ?? json['fileName'];
    final addMs = (json['addTime'] as num?)?.toInt();
    return CloudSong(
      track: Track.fromJson(song),
      fileName: (json['fileName'] ?? '').toString(),
      fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
      addTime: addMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(addMs),
    );
  }
}

/// Human-readable byte size, e.g. 1536 -> 1.5 KB.
String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return unit == 0
      ? '$bytes B'
      : '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unit]}';
}
