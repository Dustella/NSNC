import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:provider/provider.dart';

import '../models/media_item.dart';
import '../services/app_state.dart';
import '../services/playlist_repository.dart';
import '../services/ui_preferences.dart';
import 'login_screen.dart';
import 'navigation.dart';
import 'widgets/common.dart';
import 'widgets/media_widgets.dart';

export 'playlist_screen.dart' show PlaylistDetailScreen;

enum _Filter {
  all('全部'),
  created('创建的'),
  collected('收藏的');

  const _Filter(this.label);
  final String label;
}

/// The user's music library: profile, quick entries (liked songs, recently
/// played, cloud drive, radios) and their playlists as rows or cards.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  Future<List<MediaItem>>? _playlistsFuture;
  int? _loadedForUid;
  _Filter _filter = _Filter.all;

  Future<List<MediaItem>> _load(int uid, {bool refresh = false}) async {
    final raw = await context.read<PlaylistRepository>().userPlaylists(
      uid,
      refresh: refresh,
    );
    return raw.map(MediaItem.playlist).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (app.status != AuthStatus.loggedIn) return const _LoginPrompt();

    final uid = app.uid;
    if (uid != null && (_playlistsFuture == null || _loadedForUid != uid)) {
      _loadedForUid = uid;
      _playlistsFuture = _load(uid);
    }
    final layout = context.watch<UiPreferences>().layoutFor(
      LayoutSurface.libraryPlaylists,
    );

    return MiuixScaffold(
      topBar: const MiuixTopAppBar(title: '音乐库'),
      content: (padding) => Padding(
        padding: padding,
        child: RefreshIndicator(
          onRefresh: () async {
            if (uid == null) return;
            final future = _load(uid, refresh: true);
            setState(() => _playlistsFuture = future);
            await future.catchError((_) => <MediaItem>[]);
          },
          child: FutureBuilder<List<MediaItem>>(
            future: _playlistsFuture,
            builder: (context, snapshot) {
              final all = snapshot.data ?? const <MediaItem>[];
              final liked = all.where((p) => p.isLikedPlaylist).firstOrNull;
              final created = all
                  .where((p) => p.creatorId == uid && !p.isLikedPlaylist)
                  .toList();
              final collected = all.where((p) => p.creatorId != uid).toList();
              final shown = switch (_filter) {
                _Filter.all => all.where((p) => !p.isLikedPlaylist).toList(),
                _Filter.created => created,
                _Filter.collected => collected,
              };
              void open(MediaItem item) => openMedia(context, item, uid: uid);

              return ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  _ProfileCard(app: app),
                  _QuickEntries(liked: liked, onOpen: open),
                  SectionHeader(
                    title: '我的歌单',
                    subtitle: snapshot.hasData
                        ? '创建 ${created.length} · 收藏 ${collected.length}'
                        : null,
                    trailing: const [
                      LayoutToggle(surface: LayoutSurface.libraryPlaylists),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: MiuixTabRow(
                      tabs: [for (final f in _Filter.values) f.label],
                      selectedTabIndex: _filter.index,
                      onTabSelected: (i) =>
                          setState(() => _filter = _Filter.values[i]),
                    ),
                  ),
                  if (snapshot.connectionState != ConnectionState.done)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: LoadingView(),
                    )
                  else if (snapshot.hasError)
                    MessageView.error(
                      snapshot.error!,
                      onRetry: uid == null
                          ? null
                          : () => setState(() => _playlistsFuture = _load(uid)),
                    )
                  else if (shown.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: MessageView(
                        icon: Icons.queue_music_rounded,
                        message: '这里还没有歌单',
                      ),
                    )
                  else
                    MediaCollection(items: shown, layout: layout, onTap: open),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = app.profile ?? const {};
    final signature = (profile['signature'] ?? '').toString();
    final follows = (profile['follows'] as num?)?.toInt();
    final fans = (profile['followeds'] as num?)?.toInt();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: MiuixCard(
        cornerRadius: 20,
        insideMargin: const EdgeInsets.all(16),
        child: Row(
          children: [
            CoverArt(
              url: app.avatarUrl,
              size: 60,
              circle: true,
              icon: Icons.person_rounded,
              imageSize: 180,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    app.nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    [
                      if (follows != null) '关注 $follows',
                      if (fans != null) '粉丝 ${formatCount(fans)}',
                      if (signature.isNotEmpty) signature,
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickEntries extends StatelessWidget {
  const _QuickEntries({required this.liked, required this.onOpen});

  final MediaItem? liked;
  final ValueChanged<MediaItem> onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entries = <(String, String, IconData, Color, VoidCallback)>[
      (
        '我喜欢',
        liked?.subtitle.split(' · ').first ?? '红心歌曲',
        Icons.favorite_rounded,
        cs.primary,
        () {
          if (liked != null) onOpen(liked!);
        },
      ),
      (
        '最近播放',
        '播放记录',
        Icons.history_rounded,
        const Color(0xFF607D8B),
        () => openRecentSongs(context),
      ),
      (
        '音乐云盘',
        '上传的音乐',
        Icons.cloud_rounded,
        const Color(0xFF26A69A),
        () => openCloud(context),
      ),
      (
        '电台',
        '我的订阅',
        Icons.podcasts_rounded,
        const Color(0xFF8E5CC4),
        () => openRadioHub(context),
      ),
      (
        '私人 FM',
        '猜你喜欢',
        Icons.radio_rounded,
        const Color(0xFFE0703A),
        () => openPersonalFm(context),
      ),
    ];
    final scaler = MediaQuery.textScalerOf(context);
    return SizedBox(
      height: 96 + scaler.scale(14) * 1.4 + scaler.scale(11) * 1.4,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final (title, sub, icon, color, onTap) = entries[i];
          return SizedBox(
            width: 104,
            child: MiuixCard(
              cornerRadius: 18,
              insideMargin: const EdgeInsets.all(12),
              onPressed: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  const Spacer(),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LoginPrompt extends StatelessWidget {
  const _LoginPrompt();

  @override
  Widget build(BuildContext context) {
    return MiuixScaffold(
      topBar: const MiuixTopAppBar(title: '音乐库'),
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
