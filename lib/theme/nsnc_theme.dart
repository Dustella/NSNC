import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// NSNC's restrained Material 3 theme.
///
/// Netease red is reserved for selection and interaction states while neutral
/// surfaces carry most of the interface. Both brightness variants share the
/// same component geometry so switching the system theme does not shift the UI.
abstract final class NsncTheme {
  static const _seed = Color(0xFFC20C0C);
  static const _radius = 12.0;

  static ThemeData light({TargetPlatform? platform}) =>
      _build(Brightness.light, platform ?? defaultTargetPlatform);

  static ThemeData dark({TargetPlatform? platform}) =>
      _build(Brightness.dark, platform ?? defaultTargetPlatform);

  static ThemeData _build(Brightness brightness, TargetPlatform platform) {
    final scheme = _colorScheme(brightness);
    final fonts = _fontsFor(platform);

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      fontFamily: fonts.primary,
      fontFamilyFallback: fonts.fallback,
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return base.textTheme.labelMedium?.copyWith(
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        elevation: 0,
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
        ),
        selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: base.textTheme.labelMedium?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: base.textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: 8,
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        elevation: 8,
        modalElevation: 8,
        backgroundColor: scheme.surfaceContainerLow,
        modalBackgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 6,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: base.textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        actionTextColor: scheme.inversePrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: scheme.surfaceContainerHighest,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: base.textTheme.bodySmall?.copyWith(
          color: scheme.onInverseSurface,
        ),
      ),
      splashColor: scheme.primary.withValues(alpha: 0.08),
      highlightColor: scheme.primary.withValues(alpha: 0.05),
      visualDensity: VisualDensity.standard,
      extensions: const [],
    );
  }

  static _PlatformFonts _fontsFor(TargetPlatform platform) =>
      switch (platform) {
        TargetPlatform.windows => const _PlatformFonts('Microsoft YaHei UI', [
          'Microsoft YaHei',
          'Segoe UI',
          'sans-serif',
        ]),
        TargetPlatform.iOS || TargetPlatform.macOS => const _PlatformFonts(
          'PingFang SC',
          ['SF Pro Text', 'Helvetica Neue', 'sans-serif'],
        ),
        TargetPlatform.android => const _PlatformFonts('MiSans', [
          'Noto Sans CJK SC',
          'Roboto',
          'sans-serif',
        ]),
        TargetPlatform.linux => const _PlatformFonts('Noto Sans CJK SC', [
          'Noto Sans',
          'Ubuntu',
          'DejaVu Sans',
          'sans-serif',
        ]),
        TargetPlatform.fuchsia => const _PlatformFonts('Roboto', [
          'Noto Sans',
          'sans-serif',
        ]),
      };

  static ColorScheme _colorScheme(Brightness brightness) {
    final base = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);

    if (brightness == Brightness.light) {
      return base.copyWith(
        surface: const Color(0xFFFFF8F7),
        surfaceContainerLowest: const Color(0xFFFFFFFF),
        surfaceContainerLow: const Color(0xFFFFF0EE),
        surfaceContainer: const Color(0xFFF8EAE8),
        surfaceContainerHigh: const Color(0xFFF2E4E2),
        surfaceContainerHighest: const Color(0xFFEADCD9),
        outlineVariant: const Color(0xFFDDC2BE),
      );
    }

    return base.copyWith(
      surface: const Color(0xFF141211),
      surfaceContainerLowest: const Color(0xFF0F0D0D),
      surfaceContainerLow: const Color(0xFF1C1918),
      surfaceContainer: const Color(0xFF211D1C),
      surfaceContainerHigh: const Color(0xFF2B2625),
      surfaceContainerHighest: const Color(0xFF362F2E),
      outlineVariant: const Color(0xFF55413F),
    );
  }
}

class _PlatformFonts {
  const _PlatformFonts(this.primary, this.fallback);

  final String primary;
  final List<String> fallback;
}
