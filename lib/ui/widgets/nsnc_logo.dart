import 'package:flutter/material.dart';

/// The NSNC mark drawn with the same geometry as the launcher icon
/// (see assets/branding/nsnc_logo.svg): an eighth note whose head is a
/// vinyl record, on a warm-red squircle.
class NsncLogo extends StatelessWidget {
  const NsncLogo({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'NSNC',
    image: true,
    child: CustomPaint(size: Size.square(size), painter: const _LogoPainter()),
  );
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter();

  static const _c0 = Color(0xFFFF6B5B);
  static const _c1 = Color(0xFFD91E3C);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    Offset p(double x, double y) => Offset(x * s, y * s);
    final rect = Offset.zero & size;
    final gradient = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [_c0, _c1],
    ).createShader(rect);

    canvas.drawRSuperellipse(
      RSuperellipse.fromRectAndRadius(rect, Radius.circular(s * 0.26)),
      Paint()..shader = gradient,
    );

    final white = Paint()..color = Colors.white;
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      p(0.61, 0.615),
      p(0.61, 0.19),
      stroke..strokeWidth = s * 0.082,
    );
    canvas.drawPath(
      Path()
        ..moveTo(0.61 * s, 0.19 * s)
        ..cubicTo(
          0.735 * s,
          0.215 * s,
          0.805 * s,
          0.3 * s,
          0.788 * s,
          0.43 * s,
        ),
      stroke..strokeWidth = s * 0.076,
    );

    final center = p(0.415, 0.615);
    canvas.drawCircle(center, s * 0.235, white);
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..color = _c1.withValues(alpha: 0.28);
    for (final (r, w) in [(0.188, 0.013), (0.143, 0.011), (0.098, 0.01)]) {
      canvas.drawCircle(center, s * r, groove..strokeWidth = s * w);
    }
    // Keep the stem solid where it crosses the record's grooves.
    canvas.drawRect(
      Rect.fromLTRB(0.569 * s, 0.4 * s, 0.651 * s, 0.615 * s),
      white,
    );
    canvas.drawCircle(center, s * 0.052, Paint()..shader = gradient);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
