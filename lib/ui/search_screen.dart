import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:ncm_api/ncm_api.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../services/app_state.dart';
import '../services/player_service.dart';
import 'lazy_network_image.dart';

/// Search screen: query songs by keyword and play a result from the list.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

enum _SearchStatus { idle, loading, ready, error }

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();

  _SearchStatus _status = _SearchStatus.idle;
  List<Track> _tracks = const [];
  String _errorMessage = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String raw) async {
    final keywords = raw.trim();
    if (keywords.isEmpty) return;

    setState(() {
      _status = _SearchStatus.loading;
      _errorMessage = '';
    });

    try {
      final body = await context.read<AppState>().client.search(
        keywords,
        limit: 30,
      );
      final songs = (body['result']?['songs'] as List?) ?? const [];
      final tracks = songs
          .map((e) => Track.fromJson(e as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() {
        _tracks = tracks;
        _status = _SearchStatus.ready;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _SearchStatus.error;
        _errorMessage = e.toString();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _SearchStatus.error;
        _errorMessage = e.toString();
      });
    }
  }

  void _playAt(int index) {
    context.read<PlayerService>().setQueue(_tracks, startAt: index);
  }

  @override
  Widget build(BuildContext context) {
    return MiuixScaffold(
      topBar: MiuixSmallTopAppBar(
        title: '搜索',
        bottomContent: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: MiuixTextField(
            controller: _controller,
            label: '搜索歌曲、歌手、专辑',
            useLabelAsPlaceholder: true,
            leadingIcon: const Icon(Icons.search),
            singleLine: true,
            textInputAction: TextInputAction.search,
            onSubmitted: _search,
          ),
        ),
      ),
      content: (padding) => Padding(padding: padding, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    switch (_status) {
      case _SearchStatus.idle:
        return const _CenteredHint(icon: Icons.search, message: '搜索歌曲、歌手、专辑');
      case _SearchStatus.loading:
        return const Center(child: MiuixCircularProgressIndicator());
      case _SearchStatus.error:
        return _CenteredHint(
          icon: Icons.error_outline,
          message: _errorMessage.isEmpty ? '搜索失败' : _errorMessage,
        );
      case _SearchStatus.ready:
        if (_tracks.isEmpty) {
          return const _CenteredHint(icon: Icons.music_off, message: '未找到结果');
        }
        return ListView.builder(
          itemCount: _tracks.length,
          itemBuilder: (context, index) {
            final track = _tracks[index];
            return _SearchResultTile(track: track, onTap: () => _playAt(index));
          },
        );
    }
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({required this.track, required this.onTap});

  final Track track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MiuixBasicComponent(
      onClick: onTap,
      startAction: _AlbumArt(url: track.albumArtUrl),
      content: [
        Row(
          children: [
            Expanded(
              child: Text(
                track.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (track.fee == 1) ...[
              const SizedBox(width: 6),
              _VipChip(color: theme.colorScheme.primary),
            ],
          ],
        ),
        Text(
          '${track.artistLabel} · ${track.album}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall,
        ),
      ],
      endActions: [
        Text(_clock(track.duration), style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _AlbumArt extends StatelessWidget {
  const _AlbumArt({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    const size = 48.0;
    final placeholder = Container(
      width: size,
      height: size,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.music_note, size: 24),
    );
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

class _VipChip extends StatelessWidget {
  const _VipChip({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color),
      ),
      child: Text(
        'VIP',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _CenteredHint extends StatelessWidget {
  const _CenteredHint({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

String _clock(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
