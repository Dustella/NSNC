import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsnc/theme/nsnc_theme.dart';

void main() {
  test('provides matching Material 3 light and dark themes', () {
    final light = NsncTheme.light();
    final dark = NsncTheme.dark();

    expect(light.useMaterial3, isTrue);
    expect(dark.useMaterial3, isTrue);
    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.colorScheme.surface, const Color(0xFFFFF8F7));
    expect(dark.colorScheme.surface, const Color(0xFF141211));
  });

  test('uses tonal surfaces and zero-elevation navigation', () {
    for (final theme in [NsncTheme.light(), NsncTheme.dark()]) {
      final scheme = theme.colorScheme;

      expect(theme.appBarTheme.elevation, 0);
      expect(theme.appBarTheme.scrolledUnderElevation, 0);
      expect(theme.navigationBarTheme.elevation, 0);
      expect(
        theme.navigationBarTheme.backgroundColor,
        scheme.surfaceContainerLow,
      );
      expect(theme.navigationBarTheme.indicatorColor, scheme.primaryContainer);
      expect(theme.cardTheme.elevation, 0);
      expect(theme.cardTheme.color, scheme.surfaceContainerLow);
    }
  });
}
