import 'package:flutter/material.dart';

/// A minimal focus/reticle mark — concentric rings around a solid core.
/// Used both as the Focus-mode icon and as the mark inside the app logo,
/// so the whole app shares one visual identity instead of borrowing a
/// generic Material glyph.
class FocusMarkIcon extends StatelessWidget {
  final double size;
  final Color color;
  final double strokeWidth;

  const FocusMarkIcon({
    super.key,
    this.size = 18,
    required this.color,
    this.strokeWidth = 2.0,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _FocusMarkPainter(color: color, strokeWidth: strokeWidth),
    );
  }
}

class _FocusMarkPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  _FocusMarkPainter({required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = size.width / 2 - strokeWidth / 2;

    final outerPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, outerR, outerPaint);

    final innerPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 0.8
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, outerR * 0.52, innerPaint);

    final dotPaint = Paint()..color = color;
    canvas.drawCircle(center, outerR * 0.16, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _FocusMarkPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}

/// A small hand-drawn tomato mark for the Pomodoro preset — a real vector
/// icon (not an emoji glyph), with a gradient body and a three-leaf stem.
class TomatoIcon extends StatelessWidget {
  final double size;
  final double opacity;

  const TomatoIcon({super.key, this.size = 18, this.opacity = 1.0});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: CustomPaint(
        size: Size(size, size),
        painter: _TomatoPainter(),
      ),
    );
  }
}

class _TomatoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final bodyRect = Rect.fromLTWH(w * 0.06, h * 0.30, w * 0.88, h * 0.66);
    final bodyPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFFF7A66), Color(0xFFE0332F)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(bodyRect);
    canvas.drawOval(bodyRect, bodyPaint);

    final highlightPaint = Paint()..color = Colors.white.withOpacity(0.22);
    canvas.drawOval(
      Rect.fromLTWH(w * 0.20, h * 0.40, w * 0.20, h * 0.14),
      highlightPaint,
    );

    final leafPaint = Paint()..color = const Color(0xFF4CAF6D);
    final leafCenter = Offset(w * 0.5, h * 0.30);
    for (final angle in [-0.6, 0.0, 0.6]) {
      canvas.save();
      canvas.translate(leafCenter.dx, leafCenter.dy);
      canvas.rotate(angle);
      final leafPath = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(w * 0.16, -h * 0.14, 0, -h * 0.30)
        ..quadraticBezierTo(-w * 0.16, -h * 0.14, 0, 0)
        ..close();
      canvas.drawPath(leafPath, leafPaint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _TomatoPainter old) => false;
}

/// The app logo — a rounded gradient badge built around the same focus
/// mark used for the Focus mode tab, so the icon and the in-app identity
/// are visually the same shape.
class AppLogoMark extends StatelessWidget {
  final double size;

  const AppLogoMark({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8B5CF6), Color(0xFF6425D0)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C5CFC).withOpacity(0.45),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Center(
        child: FocusMarkIcon(
          size: size * 0.52,
          color: Colors.white,
          strokeWidth: size * 0.06,
        ),
      ),
    );
  }
}
