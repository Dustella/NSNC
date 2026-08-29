import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:ncm_api/ncm_api.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../services/app_state.dart';
import '../services/player_service.dart';
import 'login_screen.dart';

/// The user's music library: their playlists. Requires a logged-in session.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  Future<List<dynamic>>? _playlistsFuture;
  int? _loadedForUid;

  Future<List<dynamic>> _load(AppState appState) {
    return appState.client.userPlaylists(appState.uid!);
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

    return Scaffold(
      appBar: AppBar(title: const Text('我的音乐库')),
      body: RefreshIndicator(
        onRefresh: () async {
          final future = _load(appState);
          setState(() => _playlistsFuture = future);
          await future.catchError((_) => <dynamic>[]);
        },
        child: FutureBuilder<List<dynamic>>(
          future: _playlistsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
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
                final json = playlists[i] as Map<String, dynamic>;
                return _PlaylistTile(json: json);
              },
            );
          },
        ),
      ),
    );
  }
}

class _LoginPrompt extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的音乐库')),
      body: Center(
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
            FilledButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              },
              child: const Text('去登录'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({required this.json});

  final Map<String, dynamic> json;

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
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, _) => placeholder,
        errorWidget: (_, _, _) => placeholder,
      ),
    );
  }
}

/// Tracks of a single playlist, with play-all and per-track playback.
class PlaylistDetailScreen extends StatefulWidget {
  const PlaylistDetailScreen({
    super.key,
    required this.playlistId,
    required this.title,
  });

  final int playlistId;
  final String title;

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  bool _loading = true;
  String? _error;
  List<Track> _tracks = const [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await context.read<AppState>().client.playlistTracks(
            widget.playlistId,
          );
      final tracks = raw
          .map((e) => Track.fromJson(e as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() {
        _tracks = tracks;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败：${e.message}';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败：$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _ErrorState(message: _error!, onRetry: _fetch);
    }
    if (_tracks.isEmpty) {
      return const _EmptyState(message: '这个歌单还没有歌曲');
    }

    return Column(
      children: [
        _header(context),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: _tracks.length,
            itemBuilder: (context, i) {
              final track = _tracks[i];
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
                  context.read<PlayerService>().setQueue(_tracks, startAt: i);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '共 ${_tracks.length} 首',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          FilledButton.icon(
            onPressed: () {
              context.read<PlayerService>().setQueue(_tracks, startAt: 0);
            },
            icon: const Icon(Icons.play_arrow),
            label: const Text('播放全部'),
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
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, _) => placeholder,
        errorWidget: (_, _, _) => placeholder,
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
          OutlinedButton(onPressed: onRetry, child: const Text('重试')),
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
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
