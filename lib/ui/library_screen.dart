import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:ncm_api/ncm_api.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../services/app_state.dart';
import '../services/player_service.dart';
import '../services/playlist_repository.dart';
import 'lazy_network_image.dart';
import 'login_screen.dart';
import 'now_playing_bar.dart';

/// The user's music library: their playlists. Requires a logged-in session.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  Future<List<Map<String, dynamic>>>? _playlistsFuture;
  int? _loadedForUid;

  Future<List<Map<String, dynamic>>> _load(
    AppState appState, {
    bool refresh = false,
  }) {
    return context.read<PlaylistRepository>().userPlaylists(
      appState.uid!,
      refresh: refresh,
    );
  }

  void _ensureLoaded(AppState appState) {
    final uid = appState.uid;
    if (uid == null) return;
    if (_playlistsFuture == null || _loadedForUid != uid) {
      _loadedForUid = uid;
      _playlistsFuture = _load(appState);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    if (appState.status != AuthStatus.loggedIn) {
      return _LoginPrompt();
    }

    _ensureLoaded(appState);

    return MiuixScaffold(
      topBar: const MiuixTopAppBar(title: '我的音乐库'),
      content: (padding) => Padding(
        padding: padding,
        child: RefreshIndicator(
          onRefresh: () async {
            final future = _load(appState, refresh: true);
            setState(() => _playlistsFuture = future);
            await future.catchError((_) => <Map<String, dynamic>>[]);
          },
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _playlistsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: MiuixCircularProgressIndicator());
              }
              if (snapshot.hasError) {
                final err = snapshot.error;
                final msg = err is ApiException
                    ? '加载失败：${err.message}'
                    : '加载失败：$err';
                return _ErrorState(
                  message: msg,
                  onRetry: () => setState(() {
                    _playlistsFuture = _load(appState);
                  }),
                );
              }
              final playlists = snapshot.data ?? const [];
              if (playlists.isEmpty) {
                return const _EmptyState(message: '你还没有任何歌单');
              }
              return ListView.builder(
                itemCount: playlists.length,
                itemBuilder: (context, i) {
                  final json = playlists[i];
                  return _PlaylistTile(json: json, uid: appState.uid!);
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LoginPrompt extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MiuixScaffold(
      topBar: const MiuixTopAppBar(title: '我的音乐库'),
      content: (padding) => Padding(
        padding: padding,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.library_music_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              const Text('登录后查看你的音乐库'),
              const SizedBox(height: 16),
              MiuixTextButton(
                '去登录',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({required this.json, required this.uid});

  final Map<String, dynamic> json;
  final int uid;
  @override
  Widget build(BuildContext context) {
    final coverUrl = json['coverImgUrl']?.toString();
    final name = json['name']?.toString() ?? '未命名歌单';
    final trackCount = (json['trackCount'] as num?)?.toInt() ?? 0;

    return ListTile(
      leading: _cover(context, coverUrl),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('$trackCount 首'),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PlaylistDetailScreen(
              playlistId: (json['id'] as num).toInt(),
              title: name,
              likedSongsUid: (json['specialType'] as num?)?.toInt() == 5
                  ? uid
                  : null,
            ),
          ),
        );
      },
    );
  }

  Widget _cover(BuildContext context, String? url) {
    const size = 52.0;
    final placeholder = Container(
      width: size,
      height: size,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.queue_music,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
    if (url == null || url.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: placeholder,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LazyNetworkImage(
        url: url,
        width: size,
        height: size,
        placeholder: placeholder,
      ),
    );
  }
}

/// Tracks of a single playlist, loaded in bounded pages.
class PlaylistDetailScreen extends StatefulWidget {
  const PlaylistDetailScreen({
    super.key,
    required this.playlistId,
    required this.title,
    this.likedSongsUid,
  });

  final int playlistId;
  final String title;
  final int? likedSongsUid;

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  final ScrollController _scrollController = ScrollController();
  final List<Track> _tracks = [];
  bool _loadingInitial = true;
  bool _loadingMore = false;
  bool _queueFollowsPlaylist = false;
  String? _error;
  String? _loadMoreError;
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
    try {
      final page = await context.read<PlaylistRepository>().page(
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
    } on ApiException catch (error) {
      _setInitialError('加载失败：${error.message}');
    } catch (error) {
      _setInitialError('加载失败：$error');
    }
  }

  void _setInitialError(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _loadingInitial = false;
    });
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
    } on ApiException catch (error) {
      _setLoadMoreError('加载失败：${error.message}');
    } catch (error) {
      _setLoadMoreError('加载失败：$error');
    }
  }

  void _setLoadMoreError(String message) {
    if (!mounted) return;
    setState(() {
      _loadMoreError = message;
      _loadingMore = false;
    });
  }

  bool _sameTrackIds(List<Track> left, List<Track> right) {
    for (var i = 0; i < left.length; i++) {
      if (left[i].id != right[i].id) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return MiuixScaffold(
      topBar: MiuixSmallTopAppBar(
        title: widget.title,
        navigationIcon: MiuixIconButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Icon(Icons.arrow_back),
        ),
        actions: [
          Tooltip(
            message: '刷新',
            child: MiuixIconButton(
              onPressed: _loadingInitial
                  ? null
                  : () => _loadInitial(refresh: true),
              child: const Icon(Icons.refresh),
            ),
          ),
        ],
      ),
      content: (padding) => Padding(
        padding: padding,
        child: Column(
          children: [
            Expanded(child: _buildBody(context)),
            const NowPlayingBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loadingInitial) {
      return const Center(child: MiuixCircularProgressIndicator());
    }
    if (_error != null) {
      return _ErrorState(message: _error!, onRetry: _loadInitial);
    }
    if (_tracks.isEmpty) {
      return const _EmptyState(message: '这个歌单还没有歌曲');
    }

    final hasMore = _nextPage * PlaylistRepository.pageSize < _total;
    return Column(
      children: [
        _header(context),
        const MiuixHorizontalDivider(),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            itemExtent: 64,
            itemCount: _tracks.length + (hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == _tracks.length) return _pageFooter();
              final track = _tracks[index];
              return ListTile(
                leading: _art(context, track.albumArtUrl),
                title: Text(
                  track.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  track.artistLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  _queueFollowsPlaylist = true;
                  context.read<PlayerService>().setQueue(
                    List<Track>.of(_tracks),
                    startAt: index,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _pageFooter() {
    if (_loadMoreError != null) {
      return Center(child: MiuixTextButton('加载失败，点击重试', onPressed: _loadMore));
    }
    return const Center(
      child: SizedBox(
        width: 20,
        height: 20,
        child: MiuixCircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '已加载 ${_tracks.length} / $_total 首',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          MiuixButton(
            colors: MiuixButtonDefaults.buttonColorsPrimary(context),
            onPressed: () {
              _queueFollowsPlaylist = true;
              context.read<PlayerService>().setQueue(
                List<Track>.of(_tracks),
                startAt: 0,
              );
            },
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_arrow),
                SizedBox(width: 6),
                Text('播放已加载'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _art(BuildContext context, String? url) {
    const size = 48.0;
    final placeholder = Container(
      width: size,
      height: size,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.music_note,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
    if (url == null || url.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: placeholder,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LazyNetworkImage(
        url: url,
        width: size,
        height: size,
        placeholder: placeholder,
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(message, textAlign: TextAlign.center),
          ),
          const SizedBox(height: 12),
          MiuixTextButton('重试', onPressed: onRetry),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}
