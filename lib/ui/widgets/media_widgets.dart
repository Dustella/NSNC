import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../models/media_item.dart';
import '../../services/ui_preferences.dart';
import 'common.dart';
import 'miuix_extras.dart';

IconData mediaIcon(MediaKind kind) => switch (kind) {
  MediaKind.playlist => Icons.queue_music_rounded,
  MediaKind.album => Icons.album_rounded,
  MediaKind.artist => Icons.person_rounded,
  MediaKind.radio => Icons.podcasts_rounded,
  MediaKind.chart => Icons.leaderboard_rounded,
};

/// Artwork-first card: square cover with an optional badge, then title and
/// subtitle. Height is intrinsic, so it never overflows at large text sizes.
class MediaCard extends StatelessWidget {
  const MediaCard({
    super.key,
    required this.item,
    required this.onTap,
    this.titleLines = 2,
  });

  final MediaItem item;
  final VoidCallback onTap;
  final int titleLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final circle = item.kind == MediaKind.artist;
    return Semantics(
      button: true,
      label: item.title,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(coverRadiusOf(context) + 4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: circle
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CoverArt(
                      url: item.coverUrl,
                      circle: circle,
                      icon: mediaIcon(item.kind),
                    ),
                    if (item.badge != null && item.badge!.isNotEmpty)
                      Positioned(right: 6, top: 6, child: _Badge(item: item)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                item.title,
                maxLines: titleLines,
                overflow: TextOverflow.ellipsis,
                textAlign: circle ? TextAlign.center : TextAlign.start,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
              if (item.subtitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final playCount = item.kind == MediaKind.playlist;
    return Container(
      constraints: const BoxConstraints(maxWidth: 96),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (playCount) ...[
            const Icon(Icons.play_arrow_rounded, size: 12, color: Colors.white),
            const SizedBox(width: 1),
          ],
          Flexible(
            child: Text(
              item.badge!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontally scrolling row of [MediaCard]s (a Spotify-style "shelf").
class MediaShelf extends StatelessWidget {
  const MediaShelf({
    super.key,
    required this.items,
    required this.onTap,
    this.cardWidth = 136,
  });

  final List<MediaItem> items;
  final ValueChanged<MediaItem> onTap;
  final double cardWidth;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    // Cover + gap + two title lines + one subtitle line + padding, scaled
    // with the user's text size so labels never clip.
    final height =
        cardWidth +
        8 +
        8 +
        scaler.scale(14) * 1.3 * 2 +
        scaler.scale(12) * 1.45 +
        6;
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (context, i) => SizedBox(
          width: cardWidth,
          child: Align(
            alignment: Alignment.topCenter,
            child: MediaCard(item: items[i], onTap: () => onTap(items[i])),
          ),
        ),
      ),
    );
  }
}

/// A collection rendered as a card grid or as rows, per [layout].
/// Non-scrolling: embed it in the page's own scroll view.
class MediaCollection extends StatelessWidget {
  const MediaCollection({
    super.key,
    required this.items,
    required this.layout,
    required this.onTap,
    this.maxCardWidth = 180,
    this.onLongPress,
  });

  final List<MediaItem> items;
  final CollectionLayout layout;
  final ValueChanged<MediaItem> onTap;
  final ValueChanged<MediaItem>? onLongPress;
  final double maxCardWidth;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      child: layout == CollectionLayout.grid
          ? _grid(context)
          : GroupCard(
              key: const ValueKey('list'),
              children: [
                for (final item in items)
                  MediaRow(
                    item: item,
                    onTap: () => onTap(item),
                    onLongPress: onLongPress == null
                        ? null
                        : () => onLongPress!(item),
                  ),
              ],
            ),
    );
  }

  Widget _grid(BuildContext context) {
    return LayoutBuilder(
      key: const ValueKey('grid'),
      builder: (context, constraints) {
        const padding = 12.0;
        final width = constraints.maxWidth - padding * 2;
        final columns = (width / maxCardWidth).ceil().clamp(2, 8);
        final rows = <Widget>[];
        for (var start = 0; start < items.length; start += columns) {
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = start; i < start + columns; i++)
                  Expanded(
                    child: i < items.length
                        ? MediaCard(
                            item: items[i],
                            onTap: () => onTap(items[i]),
                          )
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          );
          rows.add(const SizedBox(height: 8));
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: padding),
          child: Column(children: rows),
        );
      },
    );
  }
}

/// One collection as a list row: cover, title, subtitle, chevron.
class MediaRow extends StatelessWidget {
  const MediaRow({
    super.key,
    required this.item,
    required this.onTap,
    this.onLongPress,
    this.trailing,
  });

  final MediaItem item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            CoverArt(
              url: item.coverUrl,
              size: 52,
              circle: item.kind == MediaKind.artist,
              icon: mediaIcon(item.kind),
              imageSize: 160,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: colors.onSurface,
                    ),
                  ),
                  if (item.subtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        item.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.onSurfaceVariantSummary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            trailing ??
                Icon(
                  Icons.chevron_right_rounded,
                  color: colors.onSurfaceVariantActions,
                ),
          ],
        ),
      ),
    );
  }
}

/// Compact tile for quick-access entries (icon or cover, bold label).
class QuickTile extends StatelessWidget {
  const QuickTile({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.coverUrl,
    this.color,
  });

  final String label;
  final IconData? icon;
  final String? coverUrl;
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = color ?? cs.primary;
    return MiuixCard(
      cornerRadius: 14,
      insideMargin: EdgeInsets.zero,
      onPressed: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 60,
              child: coverUrl != null
                  ? CoverArt(url: coverUrl, radius: 0, imageSize: 160)
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            accent,
                            Color.lerp(accent, Colors.black, 0.35)!,
                          ],
                        ),
                      ),
                      child: Icon(icon, color: Colors.white, size: 26),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
