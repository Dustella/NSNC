import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:provider/provider.dart';

import '../models/media_item.dart';
import '../models/track.dart';
import '../services/player_service.dart';
import '../services/playlist_repository.dart';
import 'widgets/common.dart';
import 'widgets/detail_scaffold.dart';
import 'widgets/track_widgets.dart';

/// Tracks of a single playlist (or chart), loaded in bounded pages.
class PlaylistDetailScreen extends StatefulWidget {
  const PlaylistDetailScreen({
    super.key,
    required this.playlistId,
    required this.title,
    this.coverUrl,
    this.likedSongsUid,
  });

  final int playlistId;
  final String title;
  final String? coverUrl;
  final int? likedSongsUid;

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  final ScrollController _scrollController = ScrollController();
  final List<Track> _tracks = [];
  Map<String, dynamic>? _meta;
  bool _loadingInitial = true;
  bool _loadingMore = false;
  bool _queueFollowsPlaylist = false;
  Object? _error;
  Object? _loadMoreError;
  int _nextPage = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadMoreNearEnd);
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _loadMoreNearEnd() {
    if (_scrollController.position.extentAfter < 600) _loadMore();
  }

  Future<void> _loadInitial({bool refresh = false}) async {
    setState(() {
      _loadingInitial = true;
      _error = null;
      _loadMoreError = null;
    });
    final repo = context.read<PlaylistRepository>();
    try {
      final page = await repo.page(
        playlistId: widget.playlistId,
        page: 0,
        likedSongsUid: widget.likedSongsUid,
        refresh: refresh,
      );
      final tracks = page.songs.map(Track.fromJson).toList(growable: false);
      if (!mounted) return;
      setState(() {
        _tracks
          ..clear()
          ..addAll(tracks);
        _total = page.total;
        _nextPage = 1;
        _loadingInitial = false;
        _queueFollowsPlaylist = false;
      });
      final meta = await repo.meta(widget.playlistId);
      if (mounted) setState(() => _meta = meta);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loadingInitial = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingInitial ||
        _loadingMore ||
        _nextPage * PlaylistRepository.pageSize >= _total) {
      return;
    }
    final previousTracks = List<Track>.of(_tracks);
    final player = context.read<PlayerService>();
    final extendQueue =
        _queueFollowsPlaylist &&
        player.tracks.length == previousTracks.length &&
        _sameTrackIds(player.tracks, previousTracks);
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    try {
      final page = await context.read<PlaylistRepository>().page(
        playlistId: widget.playlistId,
        page: _nextPage,
        likedSongsUid: widget.likedSongsUid,
      );
      final additions = page.songs.map(Track.fromJson).toList(growable: false);
      if (!mounted) return;
      setState(() {
        _tracks.addAll(additions);
        _total = page.total;
        _nextPage++;
        _loadingMore = false;
      });
      if (extendQueue &&
          player.tracks.length == previousTracks.length &&
          _sameTrackIds(player.tracks, previousTracks)) {
        player.enqueueAll(additions);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadMoreError = error;
        _loadingMore = false;
      });
    }
  }

  bool _sameTrackIds(List<Track> left, List<Track> right) {
    for (var i = 0; i < left.length; i++) {
      if (left[i].id != right[i].id) return false;
    }
    return true;
  }

  void _play(int index) {
    _queueFollowsPlaylist = true;
    unawaited(
      context.read<PlayerService>().setQueue(
        List<Track>.of(_tracks),
        startAt: index,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DetailScaffold(
      title: widget.title,
      actions: [
        Tooltip(
          message: '刷新',
          child: MiuixIconButton(
            onPressed: _loadingInitial
                ? null
                : () => _loadInitial(refresh: true),
            child: const Icon(Icons.refresh_rounded),
          ),
        ),
      ],
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loadingInitial && _tracks.isEmpty) return const LoadingView();
    if (_error != null) {
      return MessageView.error(_error!, onRetry: _loadInitial);
    }

    final hasMore = _nextPage * PlaylistRepository.pageSize < _total;
    final meta = _meta;
    final playCount = (meta?['playCount'] as num?)?.toInt() ?? 0;
    final subscribed = (meta?['subscribedCount'] as num?)?.toInt() ?? 0;
    final tags = ((meta?['tags'] as List?) ?? const []).join(' / ');
    return ListView.builder(
      controller: _scrollController,
      itemCount: 2 + (_tracks.isEmpty ? 1 : _tracks.length) + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == 0) {
          return CollectionHeader(
            title: (meta?['name'] ?? widget.title).toString(),
            coverUrl: (meta?['coverImgUrl'] ?? widget.coverUrl)?.toString(),
            subtitle: meta?['creator']?.toString(),
            description: meta?['description']?.toString(),
            meta: [
              '$_total 首',
              if (playCount > 0) '${formatCount(playCount)} 次播放',
              if (subscribed > 0) '${formatCount(subscribed)} 收藏',
              if (tags.isNotEmpty) tags,
            ],
          );
        }
        if (index == 1) {
          return PlayAllBar(
            count: _total,
            label: _tracks.length < _total
                ? '播放已加载 · ${_tracks.length}/$_total'
                : null,
            onPlay: _tracks.isEmpty ? null : () => _play(0),
            onShuffle: _tracks.isEmpty
                ? null
                : () {
                    _queueFollowsPlaylist = false;
                    shufflePlay(context, _tracks);
                  },
          );
        }
        if (_tracks.isEmpty) {
          return const Padding(
            padding: EdgeInsets.only(top: 48),
            child: MessageView(
              icon: Icons.music_off_rounded,
              message: '这个歌单还没有歌曲',
            ),
          );
        }
        final i = index - 2;
        if (i == _tracks.length) return _pageFooter();
        return TrackTile(
          track: _tracks[i],
          index: i + 1,
          onTap: () => _play(i),
        );
      },
    );
  }

  Widget _pageFooter() {
    if (_loadMoreError != null) {
      return Center(child: MiuixTextButton('加载失败，点击重试', onPressed: _loadMore));
    }
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: MiuixCircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
