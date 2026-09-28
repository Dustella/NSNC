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
      topBar: const MiuixTopAppBar(title: '发现'),
      content: (padding) => Padding(
        padding: padding,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              _Greeting(name: loggedIn ? app.nickname : null),
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

class _Greeting extends StatelessWidget {
  const _Greeting({required this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final hello = switch (hour) {
      < 5 => '夜深了',
      < 11 => '早上好',
      < 13 => '中午好',
      < 18 => '下午好',
      _ => '晚上好',
    };
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name == null ? hello : '$hello，$name',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            name == null ? '登录后解锁每日推荐、私人 FM 与音乐云盘' : '今天想听点什么？',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAccess extends StatelessWidget {
  const _QuickAccess({required this.loggedIn});

  final bool loggedIn;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tiles = <Widget>[
      if (loggedIn)
        QuickTile(
          label: '私人 FM',
          icon: Icons.radio_rounded,
          color: cs.primary,
          onTap: () => openPersonalFm(context),
        ),
      if (loggedIn)
        QuickTile(
          label: '每日推荐',
          icon: Icons.today_rounded,
          color: const Color(0xFFE0703A),
          onTap: () => openDailySongs(context),
        ),
      QuickTile(
        label: '排行榜',
        icon: Icons.leaderboard_rounded,
        color: const Color(0xFF3A7BD5),
        onTap: () => openCharts(context),
      ),
      QuickTile(
        label: '电台',
        icon: Icons.podcasts_rounded,
        color: const Color(0xFF8E5CC4),
        onTap: () => openRadioHub(context),
      ),
      if (loggedIn)
        QuickTile(
          label: '音乐云盘',
          icon: Icons.cloud_rounded,
          color: const Color(0xFF26A69A),
          onTap: () => openCloud(context),
        ),
      if (loggedIn)
        QuickTile(
          label: '最近播放',
          icon: Icons.history_rounded,
          color: const Color(0xFF607D8B),
          onTap: () => openRecentSongs(context),
        ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final columns = c.maxWidth >= 900
            ? 3
            : c.maxWidth >= 360
            ? 2
            : 1;
        final rows = <Widget>[];
        for (var i = 0; i < tiles.length; i += columns) {
          rows.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var j = i; j < i + columns; j++) ...[
                    if (j > i) const SizedBox(width: 8),
                    Expanded(
                      child: j < tiles.length
                          ? tiles[j]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: rows),
        );
      },
    );
  }
}

class _DailyHero extends StatelessWidget {
  const _DailyHero({required this.tracks});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final now = DateTime.now();
    final covers = tracks
        .map((t) => t.albumArtUrl)
        .whereType<String>()
        .take(3)
        .toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Material(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openDailySongs(context),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${now.day}'.padLeft(2, '0'),
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: cs.onPrimaryContainer,
                          height: 1,
                        ),
                      ),
                      Text(
                        '${now.month} 月 · 每日推荐',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${tracks.length} 首 · ${tracks.take(2).map((t) => t.name).join('、')}…',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onPrimaryContainer.withValues(alpha: 0.8),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => context.read<PlayerService>().setQueue(
                          List<Track>.of(tracks),
                        ),
                        style: FilledButton.styleFrom(
                          shape: const StadiumBorder(),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('立即播放'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 124,
                  height: 116,
                  child: Stack(
                    children: [
                      for (var i = covers.length - 1; i >= 0; i--)
                        Positioned(
                          right: i * 18.0,
                          top: i * 8.0,
                          child: Transform.rotate(
                            angle: (i - 1) * 0.07,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.2),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: CoverArt(
                                url: covers[i],
                                size: 92 - i * 10,
                                radius: 12,
                                imageSize: 240,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
          return Column(
            children: [for (var i = 0; i < shown.length; i++) tile(i)],
          );
        }
        final half = (shown.length / 2).ceil();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(children: [for (var i = 0; i < half; i++) tile(i)]),
            ),
            Expanded(
              child: Column(
                children: [for (var i = half; i < shown.length; i++) tile(i)],
              ),
            ),
          ],
        );
      },
    );
  }
}
