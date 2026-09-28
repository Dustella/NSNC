import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:provider/provider.dart';

import '../models/media_item.dart';
import '../models/track.dart';
import '../services/app_state.dart';
import '../services/player_service.dart';
import '../services/ui_preferences.dart';
import 'navigation.dart';
import 'track_list_screen.dart';
import 'widgets/common.dart';
import 'widgets/media_widgets.dart';
import 'widgets/miuix_extras.dart';
import 'widgets/track_widgets.dart';

/// Landing page: greeting, quick entries, daily picks and discovery
/// shelves. Every section loads independently, so one failing endpoint
/// never blanks the page, and each can be hidden in Settings.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  AuthStatus? _loadedFor;
  Future<List<MediaItem>>? _playlists;
  Future<List<Track>>? _daily;
  Future<List<Track>>? _newSongs;
  Future<List<MediaItem>>? _charts;
  Future<List<MediaItem>>? _radios;

  void _loadAll() {
    final app = context.read<AppState>();
    final client = app.client;
    final loggedIn = app.status == AuthStatus.loggedIn;
    _playlists = client
        .recommendPlaylists(limit: 18)
        .then(
          (raw) => raw
              .whereType<Map>()
              .map((e) => MediaItem.playlist(Map<String, dynamic>.from(e)))
              .toList(growable: false),
        );
    _daily = loggedIn
        ? client.recommendSongs().then(parseTracks)
        : Future.value(const []);
    _newSongs = client
        .personalizedNewSongs(limit: 12)
        .then(
          (raw) => parseTracks(
            raw.whereType<Map>().map((e) => e['song']).whereType<Map>(),
          ),
        );
    _charts = client.toplists().then(
      (raw) => raw
          .whereType<Map>()
          .map((e) => MediaItem.chart(Map<String, dynamic>.from(e)))
          .take(10)
          .toList(growable: false),
    );
    _radios = client.djRecommend().then(
      (raw) => raw
          .whereType<Map>()
          .map((e) => MediaItem.radio(Map<String, dynamic>.from(e)))
          .toList(growable: false),
    );
  }

  Future<void> _refresh() async {
    setState(_loadAll);
    await Future.wait<Object?>([
      for (final f in [_playlists, _daily, _newSongs, _charts, _radios])
        f!.then<Object?>((v) => v).catchError((_) => null),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final prefs = context.watch<UiPreferences>();
    if (_loadedFor != app.status) {
      _loadedFor = app.status;
      _loadAll();
    }
    final loggedIn = app.status == AuthStatus.loggedIn;
    void open(MediaItem item) => openMedia(context, item, uid: app.uid);

    return MiuixScaffold(
      topBar: MiuixTopAppBar(
        title: '发现',
        largeTitle: _greeting(loggedIn ? app.nickname : null),
      ),
      content: (padding) => Padding(
        padding: padding,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.only(top: 4, bottom: 24),
            children: [
              if (!loggedIn) const _GuestHint(),
              if (prefs.showsSection(HomeSection.quickAccess))
                _QuickAccess(loggedIn: loggedIn),
              if (loggedIn && prefs.showsSection(HomeSection.daily))
                _Async<List<Track>>(
                  future: _daily,
                  placeholderHeight: 150,
                  builder: (tracks) => tracks.isEmpty
                      ? const SizedBox.shrink()
                      : _DailyHero(tracks: tracks),
                ),
              if (prefs.showsSection(HomeSection.playlists)) ...[
                const SectionHeader(
                  title: '推荐歌单',
                  subtitle: '为你挑选的精选合集',
                  trailing: [
                    LayoutToggle(surface: LayoutSurface.homePlaylists),
                  ],
                ),
                _Async<List<MediaItem>>(
                  future: _playlists,
                  placeholderHeight: 200,
                  builder: (items) =>
                      prefs.layoutFor(LayoutSurface.homePlaylists) ==
                          CollectionLayout.grid
                      ? MediaShelf(items: items, onTap: open)
                      : MediaCollection(
                          items: items.take(8).toList(),
                          layout: CollectionLayout.list,
                          onTap: open,
                        ),
                ),
              ],
              if (prefs.showsSection(HomeSection.newSongs)) ...[
                const SectionHeader(title: '新歌速递', subtitle: '刚刚上架的好歌'),
                _Async<List<Track>>(
                  future: _newSongs,
                  placeholderHeight: 240,
                  builder: (tracks) => _NewSongs(tracks: tracks),
                ),
              ],
              if (prefs.showsSection(HomeSection.charts)) ...[
                SectionHeader(
                  title: '排行榜',
                  subtitle: '大家都在听什么',
                  onMore: () => openCharts(context),
                ),
                _Async<List<MediaItem>>(
                  future: _charts,
                  placeholderHeight: 200,
                  builder: (items) => MediaShelf(items: items, onTap: open),
                ),
              ],
              if (prefs.showsSection(HomeSection.radios)) ...[
                SectionHeader(
                  title: '精选电台',
                  subtitle: '播客、有声书与音乐故事',
                  onMore: () => openRadioHub(context),
                ),
                _Async<List<MediaItem>>(
                  future: _radios,
                  placeholderHeight: 200,
                  builder: (items) => MediaShelf(items: items, onTap: open),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Section body driven by its own future: skeleton while loading, a small
/// retry-less notice on error, the content otherwise.
class _Async<T> extends StatelessWidget {
  const _Async({
    required this.future,
    required this.builder,
    required this.placeholderHeight,
  });

  final Future<T>? future;
  final Widget Function(T value) builder;
  final double placeholderHeight;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _Skeleton(height: placeholderHeight);
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text(
              describeError(snap.error!),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          );
        }
        return builder(snap.data as T);
      },
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

String _greeting(String? name) {
  final hour = DateTime.now().hour;
  final hello = switch (hour) {
    < 5 => '夜深了',
    < 11 => '早上好',
    < 13 => '中午好',
    < 18 => '下午好',
    _ => '晚上好',
  };
  return name == null ? hello : '$hello，$name';
}

class _GuestHint extends StatelessWidget {
  const _GuestHint();

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Text(
        '登录后解锁每日推荐、私人 FM 与音乐云盘',
        style: TextStyle(fontSize: 14, color: colors.onSurfaceVariantSummary),
      ),
    );
  }
}

class _QuickAccess extends StatelessWidget {
  const _QuickAccess({required this.loggedIn});

  final bool loggedIn;

  @override
  Widget build(BuildContext context) {
    return ShortcutGrid(
      items: [
        if (loggedIn)
          Shortcut(
            '私人 FM',
            Icons.radio_rounded,
            const Color(0xFFE5484D),
            () => openPersonalFm(context),
          ),
        if (loggedIn)
          Shortcut(
            '每日推荐',
            Icons.calendar_today_rounded,
            const Color(0xFFF08C2E),
            () => openDailySongs(context),
          ),
        Shortcut(
          '排行榜',
          Icons.bar_chart_rounded,
          const Color(0xFF3482FF),
          () => openCharts(context),
        ),
        Shortcut(
          '电台',
          Icons.podcasts_rounded,
          const Color(0xFF8B5CF6),
          () => openRadioHub(context),
        ),
        if (loggedIn)
          Shortcut(
            '音乐云盘',
            Icons.cloud_rounded,
            const Color(0xFF14B8A6),
            () => openCloud(context),
          ),
        if (loggedIn)
          Shortcut(
            '最近播放',
            Icons.history_rounded,
            const Color(0xFF64748B),
            () => openRecentSongs(context),
          ),
      ],
    );
  }
}

class _DailyHero extends StatelessWidget {
  const _DailyHero({required this.tracks});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final now = DateTime.now();
    final cover = tracks
        .map((t) => t.albumArtUrl)
        .whereType<String>()
        .firstOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: MiuixCard(
        cornerRadius: 16,
        insideMargin: const EdgeInsets.all(14),
        onPressed: () => openDailySongs(context),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CoverArt(url: cover, size: 76, radius: 12, imageSize: 240),
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${now.day}'.padLeft(2, '0'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '每日推荐',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${now.month} 月 ${now.day} 日 · ${tracks.length} 首为你生成',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.onSurfaceVariantSummary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tracks.take(3).map((t) => t.name).join(' / '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.onSurfaceVariantActions,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: '播放每日推荐',
              child: MiuixIconButton(
                backgroundColor: colors.primary,
                cornerRadius: 22,
                minWidth: 44,
                minHeight: 44,
                onPressed: () => context.read<PlayerService>().setQueue(
                  List<Track>.of(tracks),
                ),
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: colors.onPrimary,
                  size: 28,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewSongs extends StatelessWidget {
  const _NewSongs({required this.tracks});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final shown = tracks.take(6).toList();
    return LayoutBuilder(
      builder: (context, c) {
        final twoColumns = c.maxWidth >= 720;
        Widget tile(int i) => TrackTile(
          track: shown[i],
          showAlbum: false,
          onTap: () => unawaited(
            context.read<PlayerService>().setQueue(
              List<Track>.of(tracks),
              startAt: i,
            ),
          ),
        );
        if (!twoColumns) {
          return GroupCard(
            children: [for (var i = 0; i < shown.length; i++) tile(i)],
          );
        }
        final half = (shown.length / 2).ceil();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: GroupCard(
                  margin: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                  children: [for (var i = 0; i < half; i++) tile(i)],
                ),
              ),
              Expanded(
                child: GroupCard(
                  margin: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                  children: [for (var i = half; i < shown.length; i++) tile(i)],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
