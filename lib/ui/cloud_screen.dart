import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:provider/provider.dart';

import '../models/media_item.dart';
import '../models/track.dart';
import '../services/app_state.dart';
import '../services/player_service.dart';
import 'widgets/common.dart';
import 'widgets/detail_scaffold.dart';
import 'widgets/miuix_extras.dart';
import 'widgets/track_widgets.dart';

/// The user's cloud drive: storage usage, every uploaded/matched song,
/// playback, and deletion (with confirmation).
class CloudScreen extends StatefulWidget {
  const CloudScreen({super.key});

  @override
  State<CloudScreen> createState() => _CloudScreenState();
}

class _CloudScreenState extends State<CloudScreen> {
  static const _pageSize = 100;

  final _scroll = ScrollController();
  final List<CloudSong> _songs = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  Object? _error;
  int _count = 0;
  int _used = 0;
  int _max = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 600) unawaited(_loadMore());
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
      final body = await context.read<AppState>().client.userCloud(
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _songs
          ..clear()
          ..addAll(_parse(body));
        _apply(body);
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
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final body = await context.read<AppState>().client.userCloud(
        limit: _pageSize,
        offset: _songs.length,
      );
      if (!mounted) return;
      setState(() {
        _songs.addAll(_parse(body));
        _apply(body);
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _apply(Map<String, dynamic> body) {
    _count = (body['count'] as num?)?.toInt() ?? _songs.length;
    _used = int.tryParse('${body['size'] ?? 0}') ?? 0;
    _max = int.tryParse('${body['maxSize'] ?? 0}') ?? 0;
    _hasMore = body['hasMore'] == true && _songs.length < _count;
  }

  List<CloudSong> _parse(Map<String, dynamic> body) =>
      ((body['data'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => CloudSong.tryParse(Map<String, dynamic>.from(e)))
          .whereType<CloudSong>()
          .toList();

  List<Track> get _tracks => [for (final s in _songs) s.track];

  Future<void> _confirmDelete(CloudSong song) async {
    final confirmed = await showMiuixConfirm(
      context,
      title: '从云盘删除',
      message:
          '将永久删除云盘中的「${song.track.name}」（${formatBytes(song.fileSize)}）。\n'
          '此操作无法撤销，本地已下载的文件不受影响。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await context.read<AppState>().client.userCloudDelete([song.track.id]);
      if (!mounted) return;
      setState(() {
        _songs.remove(song);
        _count = (_count - 1).clamp(0, 1 << 31);
        _used = (_used - song.fileSize).clamp(0, 1 << 62);
      });
      showToast(context, '已从云盘删除');
    } catch (e) {
      if (mounted) showToast(context, '删除失败：${describeError(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DetailScaffold(
      title: '音乐云盘',
      actions: [
        Tooltip(
          message: '刷新',
          child: MiuixIconButton(
            onPressed: _loading ? null : _reload,
            child: const Icon(Icons.refresh_rounded),
          ),
        ),
      ],
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading && _songs.isEmpty) return const LoadingView();
    if (_error != null) return MessageView.error(_error!, onRetry: _reload);
    return ListView.builder(
      controller: _scroll,
      itemCount: 2 + (_songs.isEmpty ? 1 : _songs.length) + (_hasMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == 0) return _UsageCard(count: _count, used: _used, max: _max);
        if (i == 1) {
          return PlayAllBar(
            count: _count,
            label: _songs.length < _count
                ? '播放已加载 · ${_songs.length}/$_count'
                : null,
            onPlay: _songs.isEmpty
                ? null
                : () => context.read<PlayerService>().setQueue(_tracks),
            onShuffle: _songs.isEmpty
                ? null
                : () => shufflePlay(context, _tracks),
          );
        }
        if (_songs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.only(top: 48),
            child: MessageView(
              icon: Icons.cloud_queue_rounded,
              message: '云盘里还没有歌曲\n可以在网易云音乐客户端上传本地音乐',
            ),
          );
        }
        final index = i - 2;
        if (index == _songs.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: MiuixCircularProgressIndicator(size: 20)),
          );
        }
        final song = _songs[index];
        return GroupedItem(
          index: index,
          count: _songs.length,
          child: TrackTile(
            track: song.track,
            subtitle:
                '${song.track.artistLabel} · ${formatBytes(song.fileSize)}',
            onTap: () =>
                context.read<PlayerService>().setQueue(_tracks, startAt: index),
            extraActions: [
              TrackAction(
                icon: Icons.delete_outline_rounded,
                label: '从云盘删除',
                onSelected: () => unawaited(_confirmDelete(song)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _UsageCard extends StatelessWidget {
  const _UsageCard({
    required this.count,
    required this.used,
    required this.max,
  });

  final int count;
  final int used;
  final int max;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final ratio = max > 0 ? (used / max).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: MiuixCard(
        cornerRadius: 16,
        insideMargin: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: ShapeDecoration(
                    color: const Color(0xFF14B8A6),
                    shape: RoundedSuperellipseBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Icon(
                    Icons.cloud_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$count 首歌曲',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                        ),
                      ),
                      Text(
                        max > 0
                            ? '已用 ${formatBytes(used)} / ${formatBytes(max)}'
                            : '已用 ${formatBytes(used)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.onSurfaceVariantSummary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (max > 0)
                  Text(
                    '${(ratio * 100).toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.primary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: MiuixLinearProgressIndicator(progress: ratio, height: 6),
            ),
          ],
        ),
      ),
    );
  }
}
