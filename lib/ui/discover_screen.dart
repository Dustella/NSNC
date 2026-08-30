import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../services/app_state.dart';
import '../services/player_service.dart';
import 'lazy_network_image.dart';
import 'library_screen.dart';

/// Landing page: recommended playlists (works for guests) plus daily
/// recommended songs when logged in.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  Future<_DiscoverData>? _future;
  AuthStatus? _loadedFor;

  Future<_DiscoverData> _load() async {
    final app = context.read<AppState>();
    final client = app.client;
    final loggedIn = app.status == AuthStatus.loggedIn;
    final playlists = await client.recommendPlaylists(limit: 12);
    List<dynamic> daily = const [];
    if (loggedIn) {
      try {
        daily = await client.recommendSongs();
      } catch (_) {/* daily needs login; ignore on failure */}
    }
    return _DiscoverData(playlists: playlists, dailySongs: daily);
  }

  @override
  Widget build(BuildContext context) {
    final status = context.watch<AppState>().status;
    // (Re)load when auth status settles or changes.
    if (_future == null || _loadedFor != status) {
      _loadedFor = status;
      _future = _load();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('发现音乐')),
      body: RefreshIndicator(
        onRefresh: () async => setState(() => _future = _load()),
        child: FutureBuilder<_DiscoverData>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _ErrorView(
                message: '加载失败: ${snap.error}',
                onRetry: () => setState(() => _future = _load()),
              );
            }
            final data = snap.data!;
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (data.dailySongs.isNotEmpty) ...[
                  const _SectionTitle('每日推荐'),
                  _DailySongs(songs: data.dailySongs),
                  const SizedBox(height: 24),
                ],
                const _SectionTitle('推荐歌单'),
                _PlaylistGrid(playlists: data.playlists),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DiscoverData {
  _DiscoverData({required this.playlists, required this.dailySongs});
  final List<dynamic> playlists;
  final List<dynamic> dailySongs;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleLarge),
      );
}

class _DailySongs extends StatelessWidget {
  const _DailySongs({required this.songs});
  final List<dynamic> songs;

  @override
  Widget build(BuildContext context) {
    final tracks =
        songs.map((e) => Track.fromJson(e as Map<String, dynamic>)).toList();
    return Column(
      children: [
        for (var i = 0; i < tracks.length && i < 10; i++)
          ListTile(
            leading: _Art(url: tracks[i].albumArtUrl, size: 44),
            title: Text(tracks[i].name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(tracks[i].artistLabel,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () =>
                context.read<PlayerService>().setQueue(tracks, startAt: i),
          ),
      ],
    );
  }
}

class _PlaylistGrid extends StatelessWidget {
  const _PlaylistGrid({required this.playlists});
  final List<dynamic> playlists;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: playlists.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        childAspectRatio: 0.78,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (context, i) {
        final p = playlists[i] as Map<String, dynamic>;
        final cover = (p['picUrl'] ?? p['coverImgUrl'])?.toString();
        final name = (p['name'] ?? '').toString();
        final id = (p['id'] as num?)?.toInt() ?? 0;
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PlaylistDetailScreen(playlistId: id, title: name),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: _Art(url: cover, size: double.infinity, radius: 8),
              ),
              const SizedBox(height: 6),
              Text(name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        );
      },
    );
  }
}

class _Art extends StatelessWidget {
  const _Art({required this.url, required this.size, this.radius = 6});
  final String? url;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size == double.infinity ? null : size,
      height: size == double.infinity ? null : size,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.music_note, color: Colors.white24),
    );
    if (url == null || url!.isEmpty) {
      return ClipRRect(
          borderRadius: BorderRadius.circular(radius), child: placeholder);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: LazyNetworkImage(
        url: url,
        width: size == double.infinity ? null : size,
        height: size == double.infinity ? null : size,
        placeholder: placeholder,
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Center(child: Text(message, textAlign: TextAlign.center)),
        const SizedBox(height: 12),
        Center(
          child: FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
        ),
      ],
    );
  }
}
