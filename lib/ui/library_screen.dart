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
import 'widgets/miuix_extras.dart';

export 'playlist_screen.dart' show PlaylistDetailScreen;

enum _Filter {
  all('全部'),
  created('创建的'),
  collected('收藏的');

  const _Filter(this.label);
  final String label;
}

/// The user's music library: profile, shortcut grid (liked songs, recently
/// played, cloud drive, radios, FM) and their playlists as rows or cards.
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
                padding: const EdgeInsets.only(top: 4, bottom: 24),
                children: [
                  _ProfileCard(app: app, liked: liked, onOpen: open),
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
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
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

/// Account row plus the liked-songs count, in one MIUIX card.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.app,
    required this.liked,
    required this.onOpen,
  });

  final AppState app;
  final MediaItem? liked;
  final ValueChanged<MediaItem> onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final profile = app.profile ?? const {};
    final signature = (profile['signature'] ?? '').toString().trim();
    final follows = (profile['follows'] as num?)?.toInt();
    final fans = (profile['followeds'] as num?)?.toInt();
    final level = (profile['level'] as num?)?.toInt();
    final stats = [
      if (follows != null) '关注 $follows',
      if (fans != null) '粉丝 ${formatCount(fans)}',
      if (level != null && level > 0) 'Lv.$level',
    ].join('  ·  ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: MiuixCard(
        cornerRadius: 16,
        insideMargin: const EdgeInsets.all(16),
        child: Row(
          children: [
            CoverArt(
              url: app.avatarUrl,
              size: 56,
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
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                  if (stats.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        stats,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.onSurfaceVariantSummary,
                        ),
                      ),
                    ),
                  if (signature.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        signature,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.onSurfaceVariantActions,
                        ),
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
    return ShortcutGrid(
      items: [
        Shortcut('我喜欢', Icons.favorite_rounded, const Color(0xFFE5484D), () {
          if (liked != null) onOpen(liked!);
        }),
        Shortcut(
          '最近播放',
          Icons.history_rounded,
          const Color(0xFF64748B),
          () => openRecentSongs(context),
        ),
        Shortcut(
          '音乐云盘',
          Icons.cloud_rounded,
          const Color(0xFF14B8A6),
          () => openCloud(context),
        ),
        Shortcut(
          '我的电台',
          Icons.podcasts_rounded,
          const Color(0xFF8B5CF6),
          () => openRadioHub(context),
        ),
        Shortcut(
          '私人 FM',
          Icons.radio_rounded,
          const Color(0xFFF08C2E),
          () => openPersonalFm(context),
        ),
      ],
    );
  }
}

class _LoginPrompt extends StatelessWidget {
  const _LoginPrompt();

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
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
                color: colors.onSurfaceVariantActions,
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
