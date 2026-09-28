import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../services/library_services.dart';
import '../../services/player_service.dart';
import '../navigation.dart';
import 'common.dart';
import 'miuix_extras.dart';

String formatClock(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// One song row: index or cover, title with badges, artist · album,
/// heart, duration and a "more" button for queue/navigation actions.
class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.onTap,
    this.index,
    this.showCover = true,
    this.showAlbum = true,
    this.subtitle,
    this.trailing,
    this.extraActions = const [],
  });

  final Track track;
  final VoidCallback onTap;

  /// 1-based position; shown instead of the cover when [showCover] is false.
  final int? index;
  final bool showCover;
  final bool showAlbum;

  /// Overrides the default "artist · album" line.
  final String? subtitle;
  final Widget? trailing;

  /// Screen-specific actions appended to the "more" sheet.
  final List<TrackAction> extraActions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final playing = context.select<PlayerService, bool>(
      (p) => p.current?.id == track.id,
    );
    final liked = _watchLiked(context);
    final line =
        subtitle ??
        (showAlbum && track.album.isNotEmpty
            ? '${track.artistLabel} · ${track.album}'
            : track.artistLabel);

    Widget leading;
    if (showCover) {
      leading = Stack(
        children: [
          CoverArt(
            url: track.albumArtUrl,
            size: 48,
            radius: coverRadiusOf(context, scale: 0.7),
            imageSize: 140,
          ),
          if (playing)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(
                    coverRadiusOf(context, scale: 0.7),
                  ),
                ),
                child: const Icon(
                  Icons.graphic_eq_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
        ],
      );
    } else {
      leading = SizedBox(
        width: 32,
        child: playing
            ? Icon(Icons.graphic_eq_rounded, color: cs.primary, size: 20)
            : Text(
                '${index ?? ''}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
      );
    }

    return InkWell(
      onTap: onTap,
      onLongPress: () =>
          showTrackActions(context, track, extraActions: extraActions),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
        child: Row(
          children: [
            leading,
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
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: playing ? cs.primary : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (track.isVip) ...[
                        const TagChip('VIP'),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          line,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (liked)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(
                  Icons.favorite_rounded,
                  size: 16,
                  color: cs.primary,
                ),
              ),
            ?trailing,
            if (trailing == null && track.durationMs > 0)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  formatClock(track.duration),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            Tooltip(
              message: '更多',
              child: MiuixIconButton(
                onPressed: () => showTrackActions(
                  context,
                  track,
                  extraActions: extraActions,
                ),
                child: Icon(
                  Icons.more_vert_rounded,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _watchLiked(BuildContext context) {
    try {
      return context.select<LikeService, bool>((l) => l.isLiked(track.id));
    } on ProviderNotFoundException {
      return false;
    }
  }
}

/// A screen-specific entry in the track "more" sheet.
class TrackAction {
  const TrackAction({
    required this.icon,
    required this.label,
    required this.onSelected,
  });

  final IconData icon;
  final String label;
  final VoidCallback onSelected;
}

/// Bottom sheet with the per-song actions shared by every track list.
Future<void> showTrackActions(
  BuildContext context,
  Track track, {
  List<TrackAction> extraActions = const [],
}) async {
  final player = context.read<PlayerService>();
  LikeService? likes;
  try {
    likes = context.read<LikeService>();
  } on ProviderNotFoundException {
    likes = null;
  }
  final navigator = Navigator.of(context);

  void toast(String text) {
    if (navigator.mounted) showToast(navigator.context, text);
  }

  await showMiuixSheet<void>(
    context,
    builder: (sheet) {
      final liked = likes?.isLiked(track.id) ?? false;
      final actions = <Widget>[
        _SheetAction(
          icon: Icons.playlist_play_rounded,
          label: '下一首播放',
          onTap: () {
            Navigator.pop(sheet);
            unawaited(player.playNext(track));
            toast('将在下一首播放「${track.name}」');
          },
        ),
        _SheetAction(
          icon: Icons.playlist_add_rounded,
          label: '添加到播放列表',
          onTap: () {
            Navigator.pop(sheet);
            if (player.tracks.isEmpty) {
              unawaited(player.setQueue([track]));
            } else {
              player.enqueue(track);
            }
            toast('已添加到播放列表');
          },
        ),
        if (likes != null && likes.ready)
          _SheetAction(
            icon: liked
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            label: liked ? '取消喜欢' : '喜欢',
            onTap: () {
              Navigator.pop(sheet);
              likes!.toggle(track).catchError((Object e) {
                toast('操作失败：${describeError(e)}');
              });
            },
          ),
        if (track.albumId != null)
          _SheetAction(
            icon: Icons.album_outlined,
            label: '专辑：${track.album}',
            onTap: () {
              Navigator.pop(sheet);
              openAlbum(navigator.context, track.albumId!, track.album);
            },
          ),
        for (var i = 0; i < track.artists.length; i++)
          if (i < track.artistIds.length && track.artistIds[i] != 0)
            _SheetAction(
              icon: Icons.person_outline_rounded,
              label: '歌手：${track.artists[i]}',
              onTap: () {
                Navigator.pop(sheet);
                openArtist(
                  navigator.context,
                  track.artistIds[i],
                  track.artists[i],
                );
              },
            ),
        for (final extra in extraActions)
          _SheetAction(
            icon: extra.icon,
            label: extra.label,
            onTap: () {
              Navigator.pop(sheet);
              extra.onSelected();
            },
          ),
      ];
      return SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  CoverArt(url: track.albumArtUrl, size: 52, imageSize: 140),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          track.artistLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: MiuixTheme.of(
                              sheet,
                            ).colors.onSurfaceVariantSummary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ...actions,
          ],
        ),
      );
    },
  );
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Play all" pill with the song count and a shuffle shortcut.
class PlayAllBar extends StatelessWidget {
  const PlayAllBar({
    super.key,
    required this.count,
    required this.onPlay,
    this.onShuffle,
    this.label,
    this.trailing = const [],
  });

  final int count;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;
  final String? label;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          ConstrainedBox(
            // Intrinsic width (no Flexible) so a trailing Spacer cannot steal
            // half of the row and truncate the label; capped for long text.
            constraints: const BoxConstraints(maxWidth: 240),
            child: MiuixButton(
              onPressed: onPlay ?? () {},
              enabled: onPlay != null,
              colors: MiuixButtonDefaults.buttonColorsPrimary(context),
              insideMargin: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 10,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.play_arrow_rounded,
                    color: colors.onPrimary,
                    size: 22,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label ?? '播放全部 · $count',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (onShuffle != null) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: '随机播放',
              child: MiuixIconButton(
                onPressed: onShuffle,
                backgroundColor: colors.secondaryVariant,
                cornerRadius: 16,
                minWidth: 44,
                minHeight: 44,
                child: Icon(
                  Icons.shuffle_rounded,
                  color: colors.onSecondaryVariant,
                  size: 22,
                ),
              ),
            ),
          ],
          const Spacer(),
          ...trailing,
        ],
      ),
    );
  }
}

/// Start [tracks] in a random order.
Future<void> shufflePlay(BuildContext context, List<Track> tracks) async {
  if (tracks.isEmpty) return;
  final player = context.read<PlayerService>();
  final start = DateTime.now().microsecond % tracks.length;
  if (!player.isShuffle) player.toggleShuffle();
  await player.setQueue(List<Track>.of(tracks), startAt: start);
}
