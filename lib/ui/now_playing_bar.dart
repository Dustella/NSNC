import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:provider/provider.dart';

import '../services/player_service.dart';
import 'lazy_network_image.dart';
import 'player_screen.dart';

/// Compact bottom bar showing the currently playing track with quick
/// play/pause + next controls and a thin progress line. Tapping the body
/// (anywhere but the buttons) opens the full [PlayerScreen].
class NowPlayingBar extends StatelessWidget {
  const NowPlayingBar({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerService>();
    final track = p.current;
    if (track == null) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final duration = p.duration;

    return MiuixSurface(
      color: cs.surfaceContainerHigh,
      onPressed: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const PlayerScreen())),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: ValueListenableBuilder<Duration>(
              valueListenable: p.positionListenable,
              builder: (context, position, _) {
                final progress = duration.inMilliseconds > 0
                    ? position.inMilliseconds / duration.inMilliseconds
                    : 0.0;
                return MiuixLinearProgressIndicator(
                  progress: progress.clamp(0.0, 1.0),
                  height: 2,
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                _Cover(url: track.albumArtUrl, cs: cs),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        track.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        track.artistLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (p.isBuffering)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: MiuixCircularProgressIndicator(size: 18),
                  ),
                Tooltip(
                  message: p.isPlaying ? '暂停' : '播放',
                  child: MiuixIconButton(
                    onPressed: p.togglePlay,
                    child: Icon(p.isPlaying ? Icons.pause : Icons.play_arrow),
                  ),
                ),
                Tooltip(
                  message: '下一首',
                  child: MiuixIconButton(
                    onPressed: p.next,
                    child: const Icon(Icons.skip_next),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 44x44 rounded album thumbnail with a music-note placeholder for
/// null/empty URLs or load failures.
class _Cover extends StatelessWidget {
  const _Cover({required this.url, required this.cs});

  final String? url;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    const size = 44.0;
    final placeholder = Container(
      width: size,
      height: size,
      color: cs.surfaceContainerHighest,
      child: Icon(Icons.music_note, size: 22, color: cs.onSurfaceVariant),
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
