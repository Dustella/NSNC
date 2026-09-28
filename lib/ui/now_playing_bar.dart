import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:provider/provider.dart';

import '../services/library_services.dart';
import '../services/player_service.dart';
import 'player_screen.dart';
import 'widgets/common.dart';

/// Floating mini player: cover, title/artist, like, play/pause and next,
/// with a hairline progress track. Tapping the body opens [PlayerScreen].
class NowPlayingBar extends StatelessWidget {
  const NowPlayingBar({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerService>();
    final track = p.current;
    if (track == null) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final duration = p.duration;
    bool liked = false;
    LikeService? likes;
    try {
      likes = context.watch<LikeService>();
      liked = likes.isLiked(track.id);
    } on ProviderNotFoundException {
      likes = null;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      child: MiuixSurface(
        color: MiuixTheme.of(context).colors.surfaceContainer,
        cornerRadius: 18,
        shadowElevation: 6,
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const PlayerScreen())),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 7, 4, 5),
              child: Row(
                children: [
                  CoverArt(
                    url: track.albumArtUrl,
                    size: 44,
                    radius: coverRadiusOf(context, scale: 0.8),
                    imageSize: 140,
                  ),
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
                  if (likes != null && likes.ready)
                    Tooltip(
                      message: liked ? '取消喜欢' : '喜欢',
                      child: MiuixIconButton(
                        onPressed: () =>
                            likes!.toggle(track).catchError((Object e) {
                              if (context.mounted) {
                                showToast(context, '操作失败：${describeError(e)}');
                              }
                            }),
                        child: Icon(
                          liked
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: liked ? cs.primary : cs.onSurfaceVariant,
                          size: 22,
                        ),
                      ),
                    ),
                  if (p.isBuffering)
                    const SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: MiuixCircularProgressIndicator(size: 18),
                      ),
                    )
                  else
                    Tooltip(
                      message: p.isPlaying ? '暂停' : '播放',
                      child: MiuixIconButton(
                        onPressed: p.togglePlay,
                        child: Icon(
                          p.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 28,
                        ),
                      ),
                    ),
                  Tooltip(
                    message: '下一首',
                    child: MiuixIconButton(
                      onPressed: p.next,
                      child: const Icon(Icons.skip_next_rounded, size: 26),
                    ),
                  ),
                ],
              ),
            ),
            ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                child: ValueListenableBuilder<Duration>(
                  valueListenable: p.positionListenable,
                  builder: (context, position, _) {
                    final progress = duration.inMilliseconds > 0
                        ? position.inMilliseconds / duration.inMilliseconds
                        : 0.0;
                    return SizedBox(
                      width: double.infinity,
                      child: MiuixLinearProgressIndicator(
                        progress: progress.clamp(0.0, 1.0),
                        height: 3,
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
