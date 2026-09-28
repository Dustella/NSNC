// Regenerate platform icons: dart run tool/generate_icons.dart
// Renders the NSNC logo (an eighth note whose head is a vinyl record, on a
// warm-red squircle) to every platform icon size. Geometry lives in unit space
// [0,1]^2 and is evaluated analytically with 4x4 supersampling, so every size
// is crisp. Keep in sync with assets/branding/nsnc_logo.svg.
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const _c0 = [0xFF, 0x6B, 0x5B]; // top-left coral
const _c1 = [0xD9, 0x1E, 0x3C]; // bottom-right crimson

/// Glyph only, on transparency, for Android adaptive-icon foregrounds: the
/// 108dp canvas maps onto the icon square scaled by [scale] so the glyph stays
/// inside the 66dp safe zone. Grooves are translucent so the background
/// gradient shows through them, as on the full icon.
List<double> _sampleForeground(double u, double v, {double scale = 0.76}) {
  final x = 0.5 + (u - 0.5) / scale, y = 0.5 + (v - 0.5) / scale;
  final part = _noteGlyph(x, y);
  if (part == _Part.none) return const [0, 0, 0, 0];
  if (part == _Part.disc) {
    final dx = x - _discX, dy = y - _discY;
    final d = math.sqrt(dx * dx + dy * dy);
    if (d <= 0.052) return const [0, 0, 0, 0];
    for (final (radius, width) in [
      (0.188, 0.0065),
      (0.143, 0.0055),
      (0.098, 0.005),
    ]) {
      if ((d - radius).abs() < width) return const [255, 255, 255, 184];
    }
  }
  return const [255, 255, 255, 255];
}

/// RGBA for one sample. [bleed]: full square background (iOS), otherwise a
/// squircle with [pad] transparent margin.
List<double> _sample(
  double u,
  double v, {
  required bool bleed,
  double pad = 0,
}) {
  // Map into the icon's content box.
  final x = (u - pad) / (1 - 2 * pad), y = (v - pad) / (1 - 2 * pad);
  if (!bleed) {
    if (x < 0 || x > 1 || y < 0 || y > 1) return const [0, 0, 0, 0];
    final ax = (2 * x - 1).abs(), ay = (2 * y - 1).abs();
    if (math.pow(ax, 5) + math.pow(ay, 5) > 1) return const [0, 0, 0, 0];
  }
  final t = ((x + y) / 2).clamp(0.0, 1.0);
  var r = _c0[0] + (_c1[0] - _c0[0]) * t;
  var g = _c0[1] + (_c1[1] - _c0[1]) * t;
  var b = _c0[2] + (_c1[2] - _c0[2]) * t;
  // Soft top-left glow.
  final glow = math.max(
    0.0,
    1 - math.sqrt(math.pow(x - 0.2, 2) + math.pow(y - 0.15, 2)) / 0.7,
  );
  r += (255 - r) * glow * 0.18;
  g += (255 - g) * glow * 0.18;
  b += (255 - b) * glow * 0.18;
  final bg = [r, g, b];

  // Glyph: an eighth note whose head is a vinyl record.
  final white = _noteGlyph(x, y);
  if (white == _Part.none) return [bg[0], bg[1], bg[2], 255];
  if (white == _Part.disc) {
    final dx = x - _discX, dy = y - _discY;
    final d = math.sqrt(dx * dx + dy * dy);
    if (d <= 0.052) return [bg[0], bg[1], bg[2], 255]; // spindle hole
    for (final (radius, width) in [
      (0.188, 0.0065),
      (0.143, 0.0055),
      (0.098, 0.005),
    ]) {
      if ((d - radius).abs() < width) {
        return [
          255 + (bg[0] - 255) * 0.28,
          255 + (bg[1] - 255) * 0.28,
          255 + (bg[2] - 255) * 0.28,
          255,
        ];
      }
    }
  }
  return const [255, 255, 255, 255];
}

enum _Part { none, disc, stem }

const _discX = 0.415, _discY = 0.615, _discR = 0.235;

double _capsule(
  double x,
  double y,
  double ax,
  double ay,
  double bx,
  double by,
) {
  final pax = x - ax, pay = y - ay, bax = bx - ax, bay = by - ay;
  final h = ((pax * bax + pay * bay) / (bax * bax + bay * bay)).clamp(0.0, 1.0);
  final ex = pax - bax * h, ey = pay - bay * h;
  return math.sqrt(ex * ex + ey * ey);
}

_Part _noteGlyph(double x, double y) {
  // Stem rising from the record's right edge, then a flag drawn as a short
  // polyline of capsules so it reads as one smooth, tapering curve.
  const stemX = 0.61, hw = 0.041;
  const top = 0.19;
  final stem = _capsule(x, y, stemX, _discY, stemX, top) <= hw;
  const flag = [(stemX, top), (0.735, 0.215), (0.805, 0.3), (0.788, 0.43)];
  const steps = 32;
  var inFlag = false;
  (double, double) at(double t) {
    final u = 1 - t;
    final a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t;
    return (
      a * flag[0].$1 + b * flag[1].$1 + c * flag[2].$1 + d * flag[3].$1,
      a * flag[0].$2 + b * flag[1].$2 + c * flag[2].$2 + d * flag[3].$2,
    );
  }

  for (var i = 0; i < steps && !inFlag; i++) {
    final t0 = i / steps, t1 = (i + 1) / steps;
    final (ax, ay) = at(t0);
    final (bx, by) = at(t1);
    final width = hw - 0.008 * t0; // gentle taper towards the tip
    inFlag = _capsule(x, y, ax, ay, bx, by) <= width;
  }
  if (stem || inFlag) return _Part.stem;
  final dx = x - _discX, dy = y - _discY;
  if (dx * dx + dy * dy <= _discR * _discR) return _Part.disc;
  return _Part.none;
}

img.Image render(
  int size, {
  required bool bleed,
  double pad = 0,
  bool foreground = false,
}) {
  final out = img.Image(width: size, height: size, numChannels: 4);
  const ss = 4;
  for (var py = 0; py < size; py++) {
    for (var px = 0; px < size; px++) {
      var r = 0.0, g = 0.0, b = 0.0, a = 0.0;
      for (var sy = 0; sy < ss; sy++) {
        for (var sx = 0; sx < ss; sx++) {
          final u = (px + (sx + 0.5) / ss) / size;
          final v = (py + (sy + 0.5) / ss) / size;
          final s = foreground
              ? _sampleForeground(u, v)
              : _sample(u, v, bleed: bleed, pad: pad);
          final alpha = s[3] / 255;
          r += s[0] * alpha;
          g += s[1] * alpha;
          b += s[2] * alpha;
          a += alpha;
        }
      }
      final n = (ss * ss).toDouble();
      final alpha = a / n;
      out.setPixelRgba(
        px,
        py,
        alpha > 0 ? (r / a).round() : 0,
        alpha > 0 ? (g / a).round() : 0,
        alpha > 0 ? (b / a).round() : 0,
        (alpha * 255).round(),
      );
    }
  }
  return out;
}

void writePng(String path, img.Image image) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(image));
  stdout.writeln('wrote $path (${image.width}px)');
}

void main(List<String> args) {
  final root = args.isEmpty ? '.' : args.first;
  final master = render(1024, bleed: false);
  writePng('$root/assets/branding/nsnc_logo_1024.png', master);

  // Android legacy launcher icons (squircle, transparent corners).
  const android = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  };
  for (final e in android.entries) {
    writePng(
      '$root/android/app/src/main/res/mipmap-${e.key}/ic_launcher.png',
      render(e.value, bleed: false),
    );
    // Adaptive icon (Android 8+): 108dp foreground layer = 2.25x the 48dp
    // legacy size; the gradient background is a vector drawable.
    writePng(
      '$root/android/app/src/main/res/mipmap-${e.key}/ic_launcher_foreground.png',
      render((e.value * 2.25).round(), bleed: false, foreground: true),
    );
  }

  // iOS: opaque full-bleed squares; the system applies its own mask.
  final iosDir = '$root/ios/Runner/Assets.xcassets/AppIcon.appiconset';
  final iosSizes = <String, int>{};
  for (final f in Directory(iosDir).listSync().whereType<File>()) {
    final m = RegExp(
      r'Icon-App-([\d.]+)x[\d.]+@(\d)x\.png$',
    ).firstMatch(f.path);
    if (m != null) {
      iosSizes[f.path] = (double.parse(m.group(1)!) * int.parse(m.group(2)!))
          .round();
    }
  }
  for (final e in iosSizes.entries) {
    final image = render(e.value, bleed: true);
    writePng(e.key, image.convert(numChannels: 3));
  }

  // macOS: squircle inside the standard ~10% margin.
  const mac = [16, 32, 64, 128, 256, 512, 1024];
  for (final s in mac) {
    writePng(
      '$root/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$s.png',
      render(s, bleed: false, pad: 0.1),
    );
  }

  // Windows .ico with the usual shell sizes.
  final ico = img.IcoEncoder().encodeImages([
    for (final s in [16, 24, 32, 48, 64, 128, 256]) render(s, bleed: false),
  ]);
  File('$root/windows/runner/resources/app_icon.ico').writeAsBytesSync(ico);
  stdout.writeln('wrote windows/runner/resources/app_icon.ico');
}
