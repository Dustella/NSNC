import 'package:flutter/material.dart';
import 'package:ncm_api/ncm_api.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../services/app_state.dart';
import '../services/player_service.dart';
import 'widgets/common.dart';
import 'widgets/detail_scaffold.dart';
import 'widgets/track_widgets.dart';

/// What a [TrackListScreen] loader resolves to.
class TrackListData {
  const TrackListData({
    required this.tracks,
    this.title,
    this.subtitle,
    this.description,
    this.coverUrl,
    this.meta = const [],
  });

  final List<Track> tracks;
  final String? title;
  final String? subtitle;
  final String? description;
  final String? coverUrl;
  final List<String> meta;
}

/// A header plus a full song list loaded in one request (albums, artists,
/// daily picks, recently played).
class TrackListScreen extends StatefulWidget {
  const TrackListScreen({
    super.key,
    required this.title,
    required this.loader,
    this.numbered = false,
    this.circleCover = false,
    this.headerIcon = Icons.queue_music_rounded,
    this.emptyMessage = '这里还没有歌曲',
  });

  final String title;
  final Future<TrackListData> Function(NcmClient client) loader;

  /// Show track numbers instead of covers (albums).
  final bool numbered;
  final bool circleCover;
  final IconData headerIcon;
  final String emptyMessage;

  @override
  State<TrackListScreen> createState() => _TrackListScreenState();
}

class _TrackListScreenState extends State<TrackListScreen> {
  late Future<TrackListData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<TrackListData> _load() =>
      widget.loader(context.read<AppState>().client);

  @override
  Widget build(BuildContext context) {
    return DetailScaffold(
      title: widget.title,
      body: FutureBuilder<TrackListData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const LoadingView();
          }
          if (snap.hasError) {
            return MessageView.error(
              snap.error!,
              onRetry: () => setState(() => _future = _load()),
            );
          }
          final data = snap.data!;
          final tracks = data.tracks;
          return RefreshIndicator(
            onRefresh: () async {
              final next = _load();
              setState(() => _future = next);
              await next.catchError((_) => data);
            },
            child: ListView.builder(
              itemCount: tracks.length + 2 + (tracks.isEmpty ? 1 : 0),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return CollectionHeader(
                    title: data.title ?? widget.title,
                    subtitle: data.subtitle,
                    description: data.description,
                    coverUrl:
                        data.coverUrl ??
                        (tracks.isEmpty ? null : tracks.first.albumArtUrl),
                    circle: widget.circleCover,
                    icon: widget.headerIcon,
                    meta: data.meta,
                  );
                }
                if (i == 1) {
                  return PlayAllBar(
                    count: tracks.length,
                    onPlay: tracks.isEmpty
                        ? null
                        : () => context.read<PlayerService>().setQueue(
                            List<Track>.of(tracks),
                          ),
                    onShuffle: tracks.isEmpty
                        ? null
                        : () => shufflePlay(context, tracks),
                  );
                }
                if (tracks.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 48),
                    child: MessageView(
                      icon: Icons.music_off_rounded,
                      message: widget.emptyMessage,
                    ),
                  );
                }
                final index = i - 2;
                return TrackTile(
                  track: tracks[index],
                  index: index + 1,
                  showCover: !widget.numbered,
                  showAlbum: !widget.numbered,
                  onTap: () => context.read<PlayerService>().setQueue(
                    List<Track>.of(tracks),
                    startAt: index,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

List<Track> parseTracks(Iterable<dynamic> raw) => raw
    .whereType<Map>()
    .where((e) => e['id'] != null)
    .map((e) => Track.fromJson(Map<String, dynamic>.from(e)))
    .toList(growable: false);
