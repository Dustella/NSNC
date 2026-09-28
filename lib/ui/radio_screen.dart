import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:ncm_api/ncm_api.dart';
import 'package:provider/provider.dart';

import '../models/media_item.dart';
import '../services/app_state.dart';
import '../services/player_service.dart';
import '../services/ui_preferences.dart';
import 'navigation.dart';
import 'widgets/common.dart';
import 'widgets/detail_scaffold.dart';
import 'widgets/media_widgets.dart';
import 'widgets/track_widgets.dart';

enum _RadioTab {
  subscribed('我的订阅'),
  recommend('精选'),
  hot('热门');

  const _RadioTab(this.label);
  final String label;
}

/// Radio (podcast) hub: subscriptions, editor picks and popular radios.
class RadioHubScreen extends StatefulWidget {
  const RadioHubScreen({super.key});

  @override
  State<RadioHubScreen> createState() => _RadioHubScreenState();
}

class _RadioHubScreenState extends State<RadioHubScreen> {
  final Map<_RadioTab, Future<List<MediaItem>>> _futures = {};
  late _RadioTab _tab;

  @override
  void initState() {
    super.initState();
    final loggedIn = context.read<AppState>().status == AuthStatus.loggedIn;
    _tab = loggedIn ? _RadioTab.subscribed : _RadioTab.recommend;
  }

  List<_RadioTab> get _tabs {
    final loggedIn = context.read<AppState>().status == AuthStatus.loggedIn;
    return [
      if (loggedIn) _RadioTab.subscribed,
      _RadioTab.recommend,
      _RadioTab.hot,
    ];
  }

  Future<List<MediaItem>> _load(_RadioTab tab) async {
    final client = context.read<AppState>().client;
    final raw = switch (tab) {
      _RadioTab.subscribed => await client.djSubscribed(),
      _RadioTab.recommend => await client.djRecommend(),
      _RadioTab.hot => await client.djHot(limit: 50),
    };
    return raw
        .whereType<Map>()
        .map((e) => MediaItem.radio(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppState>();
    final tabs = _tabs;
    if (!tabs.contains(_tab)) _tab = tabs.first;
    final future = _futures.putIfAbsent(_tab, () => _load(_tab));
    final layout = context.watch<UiPreferences>().layoutFor(
      LayoutSurface.radios,
    );
    return DetailScaffold(
      title: '电台',
      actions: const [LayoutToggle(surface: LayoutSurface.radios)],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: MiuixTabRow(
              tabs: [for (final t in tabs) t.label],
              selectedTabIndex: tabs.indexOf(_tab),
              onTabSelected: (i) => setState(() => _tab = tabs[i]),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<MediaItem>>(
              key: ValueKey(_tab),
              future: future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const LoadingView();
                }
                if (snap.hasError) {
                  return MessageView.error(
                    snap.error!,
                    onRetry: () => setState(() => _futures.remove(_tab)),
                  );
                }
                final items = snap.data!;
                if (items.isEmpty) {
                  return MessageView(
                    icon: Icons.podcasts_rounded,
                    message: _tab == _RadioTab.subscribed
                        ? '还没有订阅电台，去「精选」看看吧'
                        : '暂时没有电台',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    final next = _load(_tab);
                    setState(() => _futures[_tab] = next);
                    await next.catchError((_) => items);
                  },
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 16),
                    children: [
                      MediaCollection(
                        items: items,
                        layout: layout,
                        onTap: (item) async {
                          await openMedia(context, item);
                          // Subscriptions may have changed on the detail page.
                          if (mounted) {
                            setState(
                              () => _futures.remove(_RadioTab.subscribed),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One radio: header, subscribe toggle, and its programs in pages.
class RadioDetailScreen extends StatefulWidget {
  const RadioDetailScreen({
    super.key,
    required this.radioId,
    required this.title,
  });

  final int radioId;
  final String title;

  @override
  State<RadioDetailScreen> createState() => _RadioDetailScreenState();
}

class _RadioDetailScreenState extends State<RadioDetailScreen> {
  static const _pageSize = 40;

  final _scroll = ScrollController();
  final List<RadioProgram> _programs = [];
  Map<String, dynamic>? _detail;
  Object? _error;
  bool _loading = true;
  bool _loadingMore = false;
  bool _more = false;
  bool _asc = false;
  bool? _subscribed;
  int _count = 0;

  NcmClient get _client => context.read<AppState>().client;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 500) unawaited(_loadMore());
    });
    unawaited(_reload());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object>([
        _client.djDetail(widget.radioId),
        _client.djPrograms(widget.radioId, limit: _pageSize, asc: _asc),
      ]);
      final detail = results[0] as Map<String, dynamic>;
      final page = results[1] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _subscribed = detail['subed'] as bool? ?? false;
        _programs
          ..clear()
          ..addAll(_parse(page));
        _more = page['more'] == true;
        _count = (page['count'] as num?)?.toInt() ?? _programs.length;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_more) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _client.djPrograms(
        widget.radioId,
        limit: _pageSize,
        offset: _programs.length,
        asc: _asc,
      );
      if (!mounted) return;
      setState(() {
        _programs.addAll(_parse(page));
        _more = page['more'] == true;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  List<RadioProgram> _parse(Map<String, dynamic> page) =>
      ((page['programs'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => RadioProgram.tryParse(Map<String, dynamic>.from(e)))
          .whereType<RadioProgram>()
          .toList();

  Future<void> _toggleSubscribe() async {
    final next = !(_subscribed ?? false);
    setState(() => _subscribed = next);
    try {
      await _client.djSubscribe(widget.radioId, subscribe: next);
      if (mounted) showToast(context, next ? '已订阅' : '已取消订阅');
    } catch (e) {
      if (!mounted) return;
      setState(() => _subscribed = !next);
      showToast(context, '操作失败：${describeError(e)}');
    }
  }

  void _play(int index) {
    unawaited(
      context.read<PlayerService>().setQueue([
        for (final p in _programs) p.track,
      ], startAt: index),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = context.watch<AppState>().status == AuthStatus.loggedIn;
    return DetailScaffold(title: widget.title, body: _body(loggedIn));
  }

  Widget _body(bool loggedIn) {
    if (_loading && _programs.isEmpty) return const LoadingView();
    if (_error != null) return MessageView.error(_error!, onRetry: _reload);
    final d = _detail ?? const {};
    final dj = d['dj'] as Map?;
    final subCount = (d['subCount'] as num?)?.toInt() ?? 0;
    final category = [
      d['category'],
      d['secondCategory'],
    ].where((e) => e != null && e.toString().isNotEmpty).join(' / ');
    return ListView.builder(
      controller: _scroll,
      itemCount: 2 + _programs.length + (_more ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == 0) {
          return CollectionHeader(
            title: (d['name'] ?? widget.title).toString(),
            coverUrl: d['picUrl']?.toString(),
            subtitle: dj?['nickname']?.toString(),
            description: d['desc']?.toString(),
            icon: Icons.podcasts_rounded,
            meta: [
              '$_count 期',
              if (subCount > 0) '${formatCount(subCount)} 人订阅',
              if (category.isNotEmpty) category,
            ],
          );
        }
        if (i == 1) {
          return PlayAllBar(
            count: _count,
            label: '播放${_asc ? '最早' : '最新'}节目',
            onPlay: _programs.isEmpty ? null : () => _play(0),
            trailing: [
              Tooltip(
                message: _asc ? '按最新排序' : '按最早排序',
                child: MiuixIconButton(
                  onPressed: () {
                    setState(() => _asc = !_asc);
                    unawaited(_reload());
                  },
                  child: Icon(
                    _asc
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                  ),
                ),
              ),
              if (loggedIn && _subscribed != null)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: _subscribed!
                      ? OutlinedButton.icon(
                          onPressed: _toggleSubscribe,
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: const Text('已订阅'),
                        )
                      : FilledButton.tonalIcon(
                          onPressed: _toggleSubscribe,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('订阅'),
                        ),
                ),
            ],
          );
        }
        final index = i - 2;
        if (index == _programs.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: MiuixCircularProgressIndicator(size: 20)),
          );
        }
        final program = _programs[index];
        return TrackTile(
          track: program.track,
          subtitle: [
            if (program.createTime != null) _date(program.createTime!),
            if (program.listenerCount > 0)
              '${formatCount(program.listenerCount)} 次收听',
          ].join(' · '),
          onTap: () => _play(index),
        );
      },
    );
  }
}

String _date(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
