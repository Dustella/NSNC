import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:provider/provider.dart';

import '../../services/ui_preferences.dart';
import '../lazy_network_image.dart';

/// The user's cover corner radius, or the medium default when preferences
/// are not provided (isolated widget tests).
double coverRadiusOf(BuildContext context, {double scale = 1}) {
  try {
    // `watch`, not `select`: this helper is also called from builder
    // callbacks (LayoutBuilder, MIUIX scaffold content) where `select`
    // asserts on the outer widget's context.
    return context.watch<UiPreferences>().coverRadius * scale;
  } on ProviderNotFoundException {
    return CoverCorner.medium.radius * scale;
  }
}

/// Rounded (or circular) artwork with a tonal placeholder.
class CoverArt extends StatelessWidget {
  const CoverArt({
    super.key,
    required this.url,
    this.size,
    this.radius,
    this.circle = false,
    this.icon = Icons.music_note_rounded,
    this.imageSize = 400,
  });

  final String? url;

  /// Square side; null fills the parent's constraints.
  final double? size;
  final double? radius;
  final bool circle;
  final IconData icon;

  /// Requested server-side resize (Netease `?param=NxN`), in physical pixels.
  final int imageSize;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.surfaceContainerHighest, cs.surfaceContainerHigh],
        ),
      ),
      child: SizedBox(
        width: size,
        height: size,
        child: LayoutBuilder(
          builder: (context, c) => Center(
            child: Icon(
              icon,
              size:
                  (c.biggest.shortestSide.isFinite
                      ? c.biggest.shortestSide
                      : 48) *
                  0.4,
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );
    final image = LazyNetworkImage(
      url: sizedCoverUrl(url, imageSize),
      width: size,
      height: size,
      placeholder: placeholder,
    );
    final r = circle ? 9999.0 : (radius ?? coverRadiusOf(context));
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(borderRadius: BorderRadius.circular(r), child: image),
    );
  }
}

/// Append Netease's resize parameter so thumbnails do not download originals.
String? sizedCoverUrl(String? url, int px) {
  if (url == null || url.isEmpty || url.contains('param=')) return url;
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.host.endsWith('music.126.net')) return url;
  return uri
      .replace(queryParameters: {...uri.queryParameters, 'param': '${px}y$px'})
      .toString();
}

/// Section title row: bold title, optional subtitle, trailing actions.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onMore,
    this.trailing = const [],
    this.padding = const EdgeInsets.fromLTRB(24, 16, 12, 8),
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onMore;
  final List<Widget> trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.onSurfaceVariantSummary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ...trailing,
          if (onMore != null)
            InkWell(
              onTap: onMore,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '更多',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: colors.onSurfaceVariantSummary,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: colors.onSurfaceVariantActions,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// List ⇄ card switch that remembers its choice per [surface].
class LayoutToggle extends StatelessWidget {
  const LayoutToggle({super.key, required this.surface});

  final String surface;

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<UiPreferences>();
    final layout = prefs.layoutFor(surface);
    final grid = layout == CollectionLayout.grid;
    return Tooltip(
      message: grid ? '切换为列表' : '切换为卡片',
      child: MiuixIconButton(
        onPressed: () => prefs.setLayout(
          surface,
          grid ? CollectionLayout.list : CollectionLayout.grid,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Icon(
            grid ? Icons.view_list_rounded : Icons.grid_view_rounded,
            key: ValueKey(grid),
            size: 22,
          ),
        ),
      ),
    );
  }
}

/// Soft blurred artwork behind detail headers and the player.
class BlurredCover extends StatelessWidget {
  const BlurredCover({
    super.key,
    required this.url,
    this.sigma = 48,
    this.strength = 0.5,
  });

  final String? url;
  final double sigma;

  /// 0..1: how much of the artwork colour shows through the surface wash.
  final double strength;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (url == null || url!.isEmpty) return ColoredBox(color: cs.surface);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: cs.surface),
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: TileMode.decal,
          ),
          child: Opacity(
            opacity: (dark ? 0.6 : 0.5) + 0.4 * (strength - 0.5).clamp(0, 1),
            child: LazyNetworkImage(
              url: sizedCoverUrl(url, 200),
              placeholder: const SizedBox.shrink(),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                cs.surface.withValues(alpha: 0.3 * (1 - strength)),
                cs.surface.withValues(alpha: 0.9 - 0.5 * strength),
                cs.surface.withValues(alpha: 1 - 0.4 * strength),
              ],
              stops: const [0, 0.65, 1],
            ),
          ),
        ),
      ],
    );
  }
}

/// Small pill label (VIP, 云盘, 订阅 …).
class TagChip extends StatelessWidget {
  const TagChip(this.label, {super.key, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.withValues(alpha: 0.7), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: c,
          fontSize: 9.5,
          height: 1.25,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: Center(child: MiuixCircularProgressIndicator()),
  );
}

class MessageView extends StatelessWidget {
  const MessageView({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  factory MessageView.error(Object error, {VoidCallback? onRetry}) =>
      MessageView(
        icon: Icons.cloud_off_rounded,
        message: describeError(error),
        actionLabel: onRetry == null ? null : '重试',
        onAction: onRetry,
      );

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: color.withValues(alpha: 0.7)),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: color),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 12),
              MiuixTextButton(actionLabel!, onPressed: onAction),
            ],
          ],
        ),
      ),
    );
  }
}

/// Short, user-facing text for an API/transport error.
String describeError(Object error) {
  final text = error.toString();
  if (text.contains('transport error')) return '网络连接失败，请检查网络';
  final match = RegExp(r'ApiException\((\d+)\): (.*)').firstMatch(text);
  if (match != null) {
    final code = match.group(1);
    if (code == '301') return '登录已过期，请重新登录';
    return '加载失败：${match.group(2)}';
  }
  return '加载失败：$text';
}

/// Transient message pill above the bottom edge. Works on any page because
/// it uses the root overlay rather than a Material Scaffold.
void showToast(BuildContext context, String message) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  if (_activeToast?.mounted ?? false) _activeToast!.remove();
  final cs = Theme.of(context).colorScheme;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => Positioned(
      left: 24,
      right: 24,
      bottom: MediaQuery.paddingOf(context).bottom + 96,
      child: IgnorePointer(
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 180),
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, (1 - t) * 12),
                child: child,
              ),
            ),
            child: Material(
              color: cs.inverseSurface,
              elevation: 4,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onInverseSurface),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  _activeToast = entry;
  overlay.insert(entry);
  Future<void>.delayed(const Duration(milliseconds: 2200), () {
    if (_activeToast == entry) _activeToast = null;
    if (entry.mounted) entry.remove();
  });
}

OverlayEntry? _activeToast;
