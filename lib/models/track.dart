/// A playable song, normalized from Netease's `song` JSON shapes.
///
/// Netease returns songs in several layouts (`ar`/`artists`, `al`/`album`,
/// `dt`/`duration`). [Track.fromJson] absorbs both the modern (v3/cloudsearch)
/// and legacy shapes so the UI/player see one consistent type.
class Track {
  const Track({
    required this.id,
    required this.name,
    required this.artists,
    required this.album,
    required this.durationMs,
    this.albumArtUrl,
    this.fee = 0,
    this.playableUrl,
    this.albumId,
    this.artistIds = const [],
  });

  final int id;
  final String name;
  final List<String> artists;
  final String album;
  final int durationMs;
  final String? albumArtUrl;

  /// Netease fee flag: 0 free, 1 vip/paid, 4 album-only, 8 low-quality-free.
  final int fee;

  /// Resolved playback URL (populated on demand via the song/url endpoint).
  final String? playableUrl;

  /// Album id, when known and non-zero (cloud uploads and programs lack one).
  final int? albumId;

  /// Artist ids, parallel to [artists]; 0 where the server gave none.
  final List<int> artistIds;

  String get artistLabel => artists.join(' / ');
  Duration get duration => Duration(milliseconds: durationMs);
  bool get isVip => fee == 1;

  Track copyWith({String? playableUrl, String? albumArtUrl}) => Track(
    id: id,
    name: name,
    artists: artists,
    album: album,
    durationMs: durationMs,
    albumArtUrl: albumArtUrl ?? this.albumArtUrl,
    fee: fee,
    playableUrl: playableUrl ?? this.playableUrl,
    albumId: albumId,
    artistIds: artistIds,
  );

  factory Track.fromJson(Map<String, dynamic> j) {
    // Artists: modern `ar`, legacy `artists`.
    final rawArtists = (j['ar'] ?? j['artists']) as List? ?? const [];
    final named = rawArtists
        .whereType<Map>()
        .where((a) => (a['name'] ?? '').toString().isNotEmpty)
        .toList();

    // Album: modern `al`, legacy `album`.
    final al = (j['al'] ?? j['album']) as Map? ?? const {};
    final albumId = (al['id'] as num?)?.toInt();

    return Track(
      id: (j['id'] as num).toInt(),
      name: (j['name'] ?? '').toString(),
      artists: named.isEmpty
          ? const ['未知艺术家']
          : [for (final a in named) a['name'].toString()],
      artistIds: [for (final a in named) (a['id'] as num?)?.toInt() ?? 0],
      album: (al['name'] ?? '').toString(),
      albumId: albumId == null || albumId == 0 ? null : albumId,
      durationMs: ((j['dt'] ?? j['duration'] ?? 0) as num).toInt(),
      albumArtUrl: (al['picUrl'] ?? j['picUrl'])?.toString(),
      fee: ((j['fee'] ?? 0) as num).toInt(),
    );
  }

  @override
  bool operator ==(Object other) => other is Track && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
