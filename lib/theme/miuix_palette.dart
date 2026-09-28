import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

/// HyperOS-style palette: MIUIX's neutral grey/white surface ladder with only
/// the primary family re-tinted to [accent]. This keeps the MIUIX look (white
/// cards on a light grey page, true-black dark mode) instead of Monet's tinted
/// surfaces, while still honouring the user's accent colour.
MiuixColors miuixAccentColors(Color accent, {required bool dark}) {
  final b = dark ? darkColorScheme() : lightColorScheme();
  final hsl = HSLColor.fromColor(accent);
  Color tone(double lightness, {double? saturation, double alpha = 1}) => hsl
      .withLightness(lightness.clamp(0.0, 1.0))
      .withSaturation((saturation ?? hsl.saturation).clamp(0.0, 1.0))
      .toColor()
      .withValues(alpha: alpha);

  final primary = dark ? tone(hsl.lightness.clamp(0.5, 0.62)) : accent;
  return MiuixColors(
    primary: primary,
    onPrimary: Colors.white,
    primaryVariant: primary,
    onPrimaryVariant: tone(dark ? 0.78 : 0.82),
    error: b.error,
    onError: b.onError,
    errorContainer: b.errorContainer,
    onErrorContainer: b.onErrorContainer,
    disabledPrimary: dark ? tone(0.22, saturation: 0.35) : tone(0.86),
    disabledOnPrimary: dark ? tone(0.5, saturation: 0.2) : tone(0.97),
    disabledPrimaryButton: dark ? tone(0.22, saturation: 0.35) : tone(0.86),
    disabledOnPrimaryButton: dark ? tone(0.5, saturation: 0.2) : Colors.white,
    disabledPrimarySlider: dark ? tone(0.32, saturation: 0.3) : tone(0.8),
    primaryContainer: dark ? tone(0.45) : tone(0.62),
    onPrimaryContainer: Colors.white,
    secondary: b.secondary,
    onSecondary: b.onSecondary,
    secondaryVariant: b.secondaryVariant,
    onSecondaryVariant: b.onSecondaryVariant,
    disabledSecondary: b.disabledSecondary,
    disabledOnSecondary: b.disabledOnSecondary,
    disabledSecondaryVariant: b.disabledSecondaryVariant,
    disabledOnSecondaryVariant: b.disabledOnSecondaryVariant,
    secondaryContainer: b.secondaryContainer,
    onSecondaryContainer: b.onSecondaryContainer,
    secondaryContainerVariant: b.secondaryContainerVariant,
    onSecondaryContainerVariant: b.onSecondaryContainerVariant,
    tertiaryContainer: dark ? tone(0.2, saturation: 0.35) : tone(0.95),
    onTertiaryContainer: dark ? tone(0.66) : primary,
    tertiaryContainerVariant: dark ? b.tertiaryContainerVariant : tone(0.95),
    background: b.background,
    onBackground: b.onBackground,
    onBackgroundVariant: b.onBackgroundVariant,
    surface: b.surface,
    onSurface: b.onSurface,
    surfaceVariant: b.surfaceVariant,
    onSurfaceSecondary: b.onSurfaceSecondary,
    onSurfaceVariantSummary: b.onSurfaceVariantSummary,
    onSurfaceVariantActions: b.onSurfaceVariantActions,
    disabledOnSurface: b.disabledOnSurface,
    surfaceContainer: b.surfaceContainer,
    onSurfaceContainer: b.onSurfaceContainer,
    onSurfaceContainerVariant: b.onSurfaceContainerVariant,
    surfaceContainerHigh: b.surfaceContainerHigh,
    onSurfaceContainerHigh: b.onSurfaceContainerHigh,
    surfaceContainerHighest: b.surfaceContainerHighest,
    onSurfaceContainerHighest: b.onSurfaceContainerHighest,
    outline: b.outline,
    dividerLine: b.dividerLine,
    windowDimming: b.windowDimming,
    sliderKeyPoint: b.sliderKeyPoint,
    sliderKeyPointForeground: dark ? tone(0.66) : tone(0.7),
    sliderBackground: b.sliderBackground,
  );
}
