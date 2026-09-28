import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

/// MIUIX building blocks that the package does not ship ready-made:
/// grouped list cards, a shortcut icon grid, pill chips and a confirm dialog.
/// They read colours from [MiuixTheme] so they sit naturally next to stock
/// MIUIX components (white cards on a light-grey page, black in dark mode).

const _groupRadius = 16.0;
const _groupMargin = EdgeInsets.symmetric(horizontal: 12);

/// Rows grouped in one rounded card, like MIUIX settings lists.
class GroupCard extends StatelessWidget {
  const GroupCard({
    super.key,
    required this.children,
    this.margin = const EdgeInsets.fromLTRB(12, 0, 12, 8),
    this.padding = const EdgeInsets.symmetric(vertical: 4),
  });

  final List<Widget> children;
  final EdgeInsets margin;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: MiuixCard(
        cornerRadius: _groupRadius,
        insideMargin: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// One item of a lazily built grouped list: item [index] of [count] gets the
/// card background with rounded corners only at the group's ends.
class GroupedItem extends StatelessWidget {
  const GroupedItem({
    super.key,
    required this.index,
    required this.count,
    required this.child,
  });

  final int index;
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final first = index == 0;
    final last = index == count - 1;
    const r = Radius.circular(_groupRadius);
    return Padding(
      padding: _groupMargin.copyWith(bottom: last ? 8 : 0),
      child: Material(
        color: colors.surfaceContainer,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.vertical(
          top: first ? r : Radius.zero,
          bottom: last ? r : Radius.zero,
        ),
        child: Padding(
          padding: EdgeInsets.only(top: first ? 4 : 0, bottom: last ? 4 : 0),
          child: child,
        ),
      ),
    );
  }
}

class Shortcut {
  const Shortcut(this.label, this.icon, this.color, this.onTap);
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

/// HyperOS-style shortcut grid: coloured squircle icons with labels, all in
/// one card. Columns adapt to width so it reads as a row on wide screens.
class ShortcutGrid extends StatelessWidget {
  const ShortcutGrid({super.key, required this.items});

  final List<Shortcut> items;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: MiuixCard(
        cornerRadius: _groupRadius,
        insideMargin: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: LayoutBuilder(
          builder: (context, c) {
            // One row when everything fits; otherwise the most even split
            // (6 → 3+3, 5 → 3+2, 8 → 4+4) instead of a lopsided 4+2.
            final n = items.length;
            final fitAll = c.maxWidth >= n * 76;
            final perRow = fitAll
                ? n
                : (n % 4 == 0 && c.maxWidth >= 4 * 76)
                ? 4
                : 3.clamp(1, n);
            final rows = <Widget>[];
            for (var i = 0; i < items.length; i += perRow) {
              rows.add(
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var j = i; j < i + perRow; j++)
                      Expanded(
                        child: j < items.length
                            ? _ShortcutButton(item: items[j], colors: colors)
                            : const SizedBox.shrink(),
                      ),
                  ],
                ),
              );
            }
            return Column(children: rows);
          },
        ),
      ),
    );
  }
}

class _ShortcutButton extends StatelessWidget {
  const _ShortcutButton({required this.item, required this.colors});

  final Shortcut item;
  final MiuixColors colors;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: item.label,
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          child: Column(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: ShapeDecoration(
                  shape: RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(item.color, Colors.white, 0.18)!,
                      item.color,
                    ],
                  ),
                ),
                child: Icon(item.icon, color: Colors.white, size: 24),
              ),
              const SizedBox(height: 7),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: colors.onSurface),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pill chip in MIUIX secondary colours (search history, tags).
class PillChip extends StatelessWidget {
  const PillChip({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return Material(
      color: colors.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(fontSize: 13.5, color: colors.onSurfaceSecondary),
          ),
        ),
      ),
    );
  }
}

/// MIUIX-style confirmation dialog: large rounded card, centred title and
/// message, side-by-side cancel / confirm buttons. Resolves to true when
/// confirmed.
Future<bool> showMiuixConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '确定',
  String cancelLabel = '取消',
  bool destructive = false,
}) async {
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: cancelLabel,
    barrierColor: MiuixTheme.of(context).colors.windowDimming,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, _, _) {
      final colors = MiuixTheme.of(dialogContext).colors;
      final wide = MediaQuery.sizeOf(dialogContext).width >= 600;
      return SafeArea(
        child: Align(
          alignment: wide ? Alignment.center : Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Material(
                color: colors.surfaceVariant,
                shape: RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.circular(32),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.45,
                          color: colors.onSurfaceSecondary,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: MiuixButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, false),
                              child: Text(cancelLabel),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: MiuixButton(
                              colors: destructive
                                  ? MiuixButtonColors(
                                      color: colors.error,
                                      disabledColor: colors.error,
                                      contentColor: colors.onError,
                                      disabledContentColor: colors.onError,
                                    )
                                  : MiuixButtonDefaults.buttonColorsPrimary(
                                      dialogContext,
                                    ),
                              onPressed: () =>
                                  Navigator.pop(dialogContext, true),
                              child: Text(confirmLabel),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
  return result ?? false;
}

/// HyperOS-style bottom sheet: a floating rounded card inset from the screen
/// edges with a short grab bar, instead of Material's edge-to-edge sheet.
/// [title] renders as the sheet's centred heading.
Future<T?> showMiuixSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
  double maxHeightFactor = 0.8,
}) {
  final colors = MiuixTheme.of(context).colors;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: colors.windowDimming,
    builder: (sheetContext) {
      final media = MediaQuery.of(sheetContext);
      final wide = media.size.width >= 600;
      return SafeArea(
        // heightFactor 1: size to the card instead of filling the route, so
        // taps above the card reach the modal barrier and dismiss it.
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: wide ? 520 : double.infinity,
              maxHeight: media.size.height * maxHeightFactor,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Material(
                color: colors.surfaceVariant,
                clipBehavior: Clip.antiAlias,
                shape: RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.circular(32),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 10, bottom: 6),
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colors.onSurfaceVariantActions,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    if (title != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 6, 24, 10),
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                    Flexible(child: builder(sheetContext)),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
