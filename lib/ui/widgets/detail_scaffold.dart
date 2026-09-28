import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../now_playing_bar.dart';
import 'common.dart';

/// Pushed-page chrome: small top bar with back button, body, and the
/// mini player pinned to the bottom (the shell's copy is covered by routes).
class DetailScaffold extends StatelessWidget {
  const DetailScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return MiuixScaffold(
      topBar: MiuixSmallTopAppBar(
        title: title,
        navigationIcon: Tooltip(
          message: '返回',
          child: MiuixIconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Icon(Icons.arrow_back_rounded),
          ),
        ),
        actions: actions,
      ),
      content: (padding) => Padding(
        padding: padding,
        child: Column(
          children: [
            Expanded(child: body),
            const NowPlayingBar(),
          ],
        ),
      ),
    );
  }
}

/// Large header for playlists, albums, artists, radios and the cloud drive:
/// blurred artwork backdrop, cover, title, subtitle and an expandable blurb.
class CollectionHeader extends StatefulWidget {
  const CollectionHeader({
    super.key,
    required this.title,
    this.coverUrl,
    this.subtitle,
    this.description,
    this.circle = false,
    this.icon = Icons.queue_music_rounded,
    this.meta = const [],
  });

  final String title;
  final String? coverUrl;
  final String? subtitle;
  final String? description;
  final bool circle;
  final IconData icon;

  /// Small facts below the subtitle (counts, dates, tags).
  final List<String> meta;

  @override
  State<CollectionHeader> createState() => _CollectionHeaderState();
}

class _CollectionHeaderState extends State<CollectionHeader> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final desc = widget.description?.trim() ?? '';
    return ClipRect(
      child: Stack(
        children: [
          Positioned.fill(child: BlurredCover(url: widget.coverUrl)),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final coverSize = constraints.maxWidth >= 560 ? 180.0 : 124.0;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            shape: widget.circle
                                ? BoxShape.circle
                                : BoxShape.rectangle,
                            borderRadius: widget.circle
                                ? null
                                : BorderRadius.circular(
                                    coverRadiusOf(context, scale: 1.2),
                                  ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.18),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: CoverArt(
                            url: widget.coverUrl,
                            size: coverSize,
                            circle: widget.circle,
                            radius: coverRadiusOf(context, scale: 1.2),
                            icon: widget.icon,
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.title,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  fontSize: coverSize > 150 ? 28 : 21,
                                  height: 1.2,
                                ),
                              ),
                              if (widget.subtitle != null &&
                                  widget.subtitle!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  widget.subtitle!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              if (widget.meta.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  widget.meta.join(' · '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (desc.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => setState(() => _expanded = !_expanded),
                        child: AnimatedSize(
                          duration: const Duration(milliseconds: 180),
                          alignment: Alignment.topCenter,
                          child: Text(
                            desc,
                            maxLines: _expanded ? null : 2,
                            overflow: _expanded
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
