import 'package:flutter/material.dart';
import 'dart:math' as math;

/// A collection of stunning custom icons for Deep Focus.
/// All icons are vector-based CustomPainters - no emojis, no raster images.

/// ─── Focus Icon (Concentric rings with center dot) ───
class FocusIcon extends StatelessWidget {
  final double size;
  final Color color;
  final double strokeWidth;
  final double opacity;

  const FocusIcon({
    super.key,
    this.size = 24,
    required this.color,
    this.strokeWidth = 2.0,
    this.opacity = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: CustomPaint(
        size: Size(size, size),
        painter: _FocusIconPainter(color: color, strokeWidth: strokeWidth),
      ),
    );
  }
}

class _FocusIconPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  _FocusIconPainter({required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = size.width / 2 - strokeWidth / 2;

    // Outer ring
    final outerPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, outerR, outerPaint);

    // Middle ring
    final middlePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 0.75
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, outerR * 0.58, middlePaint);

    // Center dot with subtle glow
    final dotPaint = Paint()..color = color;
    canvas.drawCircle(center, outerR * 0.18, dotPaint);

    // Subtle glow on center dot
    final glowPaint = Paint()
      ..color = color.withOpacity(0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(center, outerR * 0.22, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _FocusIconPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}

/// ─── Break Icon (Coffee cup with steam - hand drawn) ───
class BreakIcon extends StatelessWidget {
  final double size;
  final Color color;
  final double opacity;

  const BreakIcon({
    super.key,
    this.size = 24,
    required this.color,
    this.opacity = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: CustomPaint(
        size: Size(size, size),
        painter: _BreakIconPainter(color: color),
      ),
    );
  }
}

class _BreakIconPainter extends CustomPainter {
  final Color color;

  _BreakIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final scale = w / 24.0;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Cup body
    final cupRect = Rect.fromLTWH(
      w * 0.22,
      h * 0.38,
      w * 0.56,
      h * 0.48,
    );
    final cupPath = Path()
      ..moveTo(cupRect.left, cupRect.top)
      ..lineTo(cupRect.left, cupRect.bottom)
      ..quadraticBezierTo(
        cupRect.left,
        cupRect.bottom + h * 0.06,
        cupRect.left + w * 0.08,
        cupRect.bottom + h * 0.06,
      )
      ..lineTo(cupRect.right - w * 0.08, cupRect.bottom + h * 0.06)
      ..quadraticBezierTo(
        cupRect.right,
        cupRect.bottom + h * 0.06,
        cupRect.right,
        cupRect.bottom,
      )
      ..lineTo(cupRect.right, cupRect.top)
      ..close();

    // Cup shadow/body
    canvas.drawPath(cupPath, fillPaint);

    // Cup inner highlight
    final highlightPaint = Paint()
      ..color = color.withOpacity(0.25)
      ..style = PaintingStyle.fill;
    final highlightPath = Path()
      ..moveTo(cupRect.left + w * 0.08, cupRect.top + h * 0.04)
      ..lineTo(cupRect.left + w * 0.08, cupRect.bottom - h * 0.06)
      ..quadraticBezierTo(
        cupRect.left + w * 0.08,
        cupRect.bottom - h * 0.02,
        cupRect.left + w * 0.14,
        cupRect.bottom - h * 0.02,
      )
      ..lineTo(cupRect.right - w * 0.14, cupRect.bottom - h * 0.02)
      ..quadraticBezierTo(
        cupRect.right - w * 0.08,
        cupRect.bottom - h * 0.02,
        cupRect.right - w * 0.08,
        cupRect.bottom - h * 0.06,
      )
      ..lineTo(cupRect.right - w * 0.08, cupRect.top + h * 0.04)
      ..close();
    canvas.drawPath(highlightPath, highlightPaint);

    // Handle
    final handleRect = Rect.fromLTWH(
      cupRect.right + w * 0.02,
      cupRect.top + h * 0.06,
      w * 0.18,
      h * 0.30,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(handleRect, Radius.circular(4 * scale)),
      paint,
    );

    // Steam - three curved lines
    final steamPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * scale
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 3; i++) {
      final steamPath = Path();
      final x = cupRect.left + w * 0.20 + i * w * 0.16;
      final startY = cupRect.top - h * 0.02;
      steamPath.moveTo(x, startY);
      steamPath.quadraticBezierTo(
        x + (i - 1) * w * 0.06,
        startY - h * 0.12,
        x + (i - 1) * w * 0.04,
        startY - h * 0.22,
      );
      canvas.drawPath(steamPath, steamPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _BreakIconPainter old) => old.color != color;
}

/// ─── Long Break Icon (Chair/Relax icon - hand drawn) ───
class LongBreakIcon extends StatelessWidget {
  final double size;
  final Color color;
  final double opacity;

  const LongBreakIcon({
    super.key,
    this.size = 24,
    required this.color,
    this.opacity = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: CustomPaint(
        size: Size(size, size),
        painter: _LongBreakIconPainter(color: color),
      ),
    );
  }
}

class _LongBreakIconPainter extends CustomPainter {
  final Color color;

  _LongBreakIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final scale = w / 24.0;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Chair back
    final backRect = Rect.fromLTWH(
      w * 0.15,
      h * 0.12,
      w * 0.70,
      h * 0.28,
    );
    final backPath = Path()
      ..addRRect(RRect.fromRectAndRadius(backRect, Radius.circular(3 * scale)));
    canvas.drawPath(backPath, fillPaint);

    // Chair seat
    final seatRect = Rect.fromLTWH(
      w * 0.10,
      h * 0.40,
      w * 0.80,
      h * 0.18,
    );
    final seatPath = Path()
      ..addRRect(RRect.fromRectAndRadius(seatRect, Radius.circular(3 * scale)));
    canvas.drawPath(seatPath, fillPaint);

    // Front legs
    final legWidth = w * 0.06;
    final legHeight = h * 0.28;
    final leftLegRect = Rect.fromLTWH(
      w * 0.18,
      h * 0.58,
      legWidth,
      legHeight,
    );
    final rightLegRect = Rect.fromLTWH(
      w * 0.76,
      h * 0.58,
      legWidth,
      legHeight,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(leftLegRect, Radius.circular(2 * scale)),
      fillPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rightLegRect, Radius.circular(2 * scale)),
      fillPaint,
    );

    // Back legs (partially visible)
    final backLegRect1 = Rect.fromLTWH(
      w * 0.22,
      h * 0.20,
      legWidth * 0.6,
      h * 0.22,
    );
    final backLegRect2 = Rect.fromLTWH(
      w * 0.72,
      h * 0.20,
      legWidth * 0.6,
      h * 0.22,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(backLegRect1, Radius.circular(2 * scale)),
      fillPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(backLegRect2, Radius.circular(2 * scale)),
      fillPaint,
    );

    // Zzz sleep indicator (optional - subtle)
    final zzzPaint = Paint()
      ..color = color.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 * scale
      ..strokeCap = StrokeCap.round;

    final zzzPath = Path()
      ..moveTo(w * 0.85, h * 0.20)
      ..lineTo(w * 0.92, h * 0.20)
      ..lineTo(w * 0.85, h * 0.28)
      ..lineTo(w * 0.92, h * 0.28)
      ..moveTo(w * 0.88, h * 0.28)
      ..lineTo(w * 0.95, h * 0.15);
    canvas.drawPath(zzzPath, zzzPaint);
  }

  @override
  bool shouldRepaint(covariant _LongBreakIconPainter old) => old.color != color;
}

/// ─── Celebration Icon (for completion notification - replaces 🎉) ───
class CelebrationIcon extends StatelessWidget {
  final double size;
  final Color color;
  final double opacity;
  final double animationValue; // 0.0 to 1.0 for animation

  const CelebrationIcon({
    super.key,
    this.size = 24,
    required this.color,
    this.opacity = 1.0,
    this.animationValue = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: CustomPaint(
        size: Size(size, size),
        painter: _CelebrationIconPainter(
          color: color,
          animationValue: animationValue,
        ),
      ),
    );
  }
}

class _CelebrationIconPainter extends CustomPainter {
  final Color color;
  final double animationValue;

  _CelebrationIconPainter({required this.color, required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    final scale = w / 24.0;

    // Burst lines
    final burstPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * scale
      ..strokeCap = StrokeCap.round;

    final burstCount = 8;
    for (int i = 0; i < burstCount; i++) {
      final angle = (i / burstCount) * 2 * math.pi;
      final startR = w * 0.25 * animationValue;
      final endR = w * 0.45 * animationValue;

      final start = Offset(
        center.dx + startR * math.cos(angle),
        center.dy + startR * math.sin(angle),
      );
      final end = Offset(
        center.dx + endR * math.cos(angle),
        center.dy + endR * math.sin(angle),
      );

      final linePaint = Paint()
        ..color = color.withOpacity((1.0 - animationValue) * 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 * scale * (1.0 - animationValue * 0.5)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(start, end, linePaint);
    }

    // Central star/sparkle
    final sparklePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final sparkleR = w * 0.18 * animationValue;
    final sparklePath = Path();
    for (int i = 0; i < 5; i++) {
      final angle = (i / 5.0) * 2 * math.pi - math.pi / 2;
      final outerR = sparkleR;
      final innerR = sparkleR * 0.4;
      final outer = Offset(
        center.dx + outerR * math.cos(angle),
        center.dy + outerR * math.sin(angle),
      );
      final innerAngle = angle + math.pi / 5;
      final inner = Offset(
        center.dx + innerR * math.cos(innerAngle),
        center.dy + innerR * math.sin(innerAngle),
      );
      if (i == 0) {
        sparklePath.moveTo(outer.dx, outer.dy);
      } else {
        sparklePath.lineTo(outer.dx, outer.dy);
      }
      sparklePath.lineTo(inner.dx, inner.dy);
    }
    sparklePath.close();
    canvas.drawPath(sparklePath, sparklePaint);

    // Inner glow
    final glowPaint = Paint()
      ..color = color.withOpacity(0.3 * animationValue)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(center, sparkleR * 1.5, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _CelebrationIconPainter old) =>
      old.color != color || old.animationValue != animationValue;
}

/// ─── App Logo Mark (Stunning gradient badge with focus mark) ───
class AppLogoMark extends StatelessWidget {
  final double size;
  final double glowIntensity;

  const AppLogoMark({
    super.key,
    this.size = 48,
    this.glowIntensity = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _AppLogoPainter(size: size, glowIntensity: glowIntensity),
    );
  }
}

class _AppLogoPainter extends CustomPainter {
  final double size;
  final double glowIntensity;

  _AppLogoPainter({required this.size, required this.glowIntensity});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    final radius = w * 0.5;

    // Outer glow
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF8B5CF6).withOpacity(0.5 * glowIntensity),
          const Color(0xFF6425D0).withOpacity(0.3 * glowIntensity),
          Colors.transparent,
        ],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 1.4));
    canvas.drawCircle(center, radius * 1.4, glowPaint);

    // Base badge with gradient
    final badgeRect = Rect.fromLTWH(0, 0, w, h);
    final badgePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF9B6BFF),
          Color(0xFF7C5CFC),
          Color(0xFF6D4BE0),
          Color(0xFF5B3CCC),
        ],
        stops: [0.0, 0.3, 0.7, 1.0],
      ).createShader(badgeRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(badgeRect, Radius.circular(w * 0.28)),
      badgePaint,
    );

    // Inner subtle highlight
    final highlightPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withOpacity(0.15),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(w * 0.1, h * 0.1, w * 0.8, h * 0.5));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.1, h * 0.1, w * 0.8, h * 0.5),
        Radius.circular(w * 0.2),
      ),
      highlightPaint,
    );

    // Focus mark (concentric rings)
    final markCenter = center;
    final outerR = w * 0.22;

    // Outer ring
    final outerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.035
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(markCenter, outerR, outerPaint);

    // Middle ring
    final middlePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.028
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(markCenter, outerR * 0.58, middlePaint);

    // Center dot
    final dotPaint = Paint()..color = Colors.white;
    canvas.drawCircle(markCenter, outerR * 0.16, dotPaint);

    // Subtle dot glow
    final dotGlow = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(markCenter, outerR * 0.22, dotGlow);
  }

  @override
  bool shouldRepaint(covariant _AppLogoPainter old) =>
      old.size != size || old.glowIntensity != glowIntensity;
}

/// ─── Progress Ring Painter (reusable for timer ring) ───
class ProgressRingPainter extends CustomPainter {
  final double progress; // 0.0 to 1.0
  final Color accentColor;
  final double strokeWidth;
  final Color backgroundColor;
  final bool showGlow;

  const ProgressRingPainter({
    required this.progress,
    required this.accentColor,
    this.strokeWidth = 7,
    this.backgroundColor = const Color(0xFF262638),
    this.showGlow = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - strokeWidth / 2;

    // Background track
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);

    // Progress arc
    if (progress > 0) {
      final progressPaint = Paint()
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: math.pi * 1.5,
          colors: [
            accentColor,
            accentColor.withOpacity(0.6),
            accentColor,
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      final sweepAngle = 2 * math.pi * progress;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        sweepAngle,
        false,
        progressPaint,
      );

      // Glow on progress end
      if (showGlow && progress < 1.0) {
        final endAngle = -math.pi / 2 + sweepAngle;
        final endPoint = Offset(
          center.dx + radius * math.cos(endAngle),
          center.dy + radius * math.sin(endAngle),
        );
        final glowPaint = Paint()
          ..color = accentColor
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
        canvas.drawCircle(endPoint, strokeWidth * 0.6, glowPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant ProgressRingPainter old) =>
      old.progress != progress ||
      old.accentColor != accentColor ||
      old.strokeWidth != strokeWidth ||
      old.backgroundColor != backgroundColor ||
      old.showGlow != showGlow;
}

/// ─── Mode Enum Extension for Icons ───
enum TimerMode { focus, break_, long }

extension TimerModeIcon on TimerMode {
  Widget icon({
    double size = 24,
    required Color color,
    double opacity = 1.0,
    double strokeWidth = 2.0,
  }) {
    switch (this) {
      case TimerMode.focus:
        return FocusIcon(size: size, color: color, strokeWidth: strokeWidth, opacity: opacity);
      case TimerMode.break_:
        return BreakIcon(size: size, color: color, opacity: opacity);
      case TimerMode.long:
        return LongBreakIcon(size: size, color: color, opacity: opacity);
    }
  }

  Color get color {
    switch (this) {
      case TimerMode.focus:
        return const Color(0xFF7C5CFC);
      case TimerMode.break_:
        return const Color(0xFF34D399);
      case TimerMode.long:
        return const Color(0xFF2DD4BF);
    }
  }

  String get label {
    switch (this) {
      case TimerMode.focus:
        return 'FOCUS';
      case TimerMode.break_:
        return 'BREAK';
      case TimerMode.long:
        return 'LONG BREAK';
    }
  }

  String get shortLabel {
    switch (this) {
      case TimerMode.focus:
        return 'Focus';
      case TimerMode.break_:
        return 'Break';
      case TimerMode.long:
        return 'Long';
    }
  }
}