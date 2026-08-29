import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/player_service.dart';
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
    final progress = p.duration.inMilliseconds > 0
        ? p.position.inMilliseconds / p.duration.inMilliseconds
        : 0.0;

    return Material(
      color: cs.surfaceContainerHigh,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const PlayerScreen()),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 2,
              backgroundColor: cs.surfaceContainerHighest,
              color: cs.primary,
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
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  IconButton(
                    icon: Icon(p.isPlaying ? Icons.pause : Icons.play_arrow),
                    tooltip: p.isPlaying ? '暂停' : '播放',
                    onPressed: () => p.togglePlay(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next),
                    tooltip: '下一首',
                    onPressed: () => p.next(),
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
      child: (url == null || url!.isEmpty)
          ? placeholder
          : CachedNetworkImage(
              imageUrl: url!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (_, _) => placeholder,
              errorWidget: (_, _, _) => placeholder,
            ),
    );
  }
}
