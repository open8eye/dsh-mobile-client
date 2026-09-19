import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Draws the built-in companion.
///
/// The same character is drawn by the Android overlay service in Kotlin, so the
/// preview here is a faithful preview of what will float on the home screen.
/// Replacing it with a Live2D or sprite character later only means swapping the
/// painter and the Android view — the plumbing around them does not change.
class CompanionPreview extends StatefulWidget {
  const CompanionPreview({this.size = 96, this.animated = true, super.key});

  final double size;
  final bool animated;

  @override
  State<CompanionPreview> createState() => _CompanionPreviewState();
}

class _CompanionPreviewState extends State<CompanionPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animated) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: CompanionPainter(
            phase: widget.animated ? _controller.value : 0,
            body: scheme.primary,
            accent: scheme.primaryContainer,
            eye: scheme.onPrimary,
            blush: scheme.tertiaryContainer,
          ),
        ),
      ),
    );
  }
}

/// Paints the companion: a soft blob that bobs, breathes and blinks.
class CompanionPainter extends CustomPainter {
  CompanionPainter({
    required this.phase,
    required this.body,
    required this.accent,
    required this.eye,
    required this.blush,
  });

  /// 0..1 animation phase.
  final double phase;
  final Color body;
  final Color accent;
  final Color eye;
  final Color blush;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    // Bob up and down on a sine so the motion reads as breathing.
    final bob = math.sin(phase * 2 * math.pi) * height * 0.035;
    // Blink twice per cycle, for a short slice each time.
    final blinkPhase = (phase * 2) % 1.0;
    final blink = blinkPhase > 0.86 ? 0.12 : 1.0;

    final bodyWidth = width * 0.62;
    final bodyHeight = height * 0.56;
    final center = Offset(width / 2, height * 0.52 + bob);
    final bodyRect = Rect.fromCenter(center: center, width: bodyWidth, height: bodyHeight);

    // Ground shadow shrinks as the character rises.
    final shadowWidth = bodyWidth * (0.92 - bob / height * 2);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(width / 2, height * 0.86),
        width: shadowWidth,
        height: height * 0.06,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.12),
    );

    // A pair of small ears behind the body gives it a character silhouette.
    final earPaint = Paint()..color = accent;
    for (final sign in <double>[-1, 1]) {
      final earCenter = Offset(center.dx + sign * bodyWidth * 0.30, center.dy - bodyHeight * 0.38);
      canvas.drawOval(
        Rect.fromCenter(center: earCenter, width: bodyWidth * 0.26, height: bodyHeight * 0.36),
        earPaint,
      );
    }

    // Body.
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, Radius.circular(bodyWidth * 0.45)),
      Paint()..color = body,
    );

    // A lighter belly patch.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + bodyHeight * 0.16),
        width: bodyWidth * 0.5,
        height: bodyHeight * 0.42,
      ),
      Paint()..color = accent.withValues(alpha: 0.55),
    );

    // Blush.
    for (final sign in <double>[-1, 1]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(center.dx + sign * bodyWidth * 0.28, center.dy + bodyHeight * 0.06),
          width: bodyWidth * 0.16,
          height: bodyHeight * 0.11,
        ),
        Paint()..color = blush.withValues(alpha: 0.75),
      );
    }

    // Eyes.
    final eyePaint = Paint()..color = eye;
    for (final sign in <double>[-1, 1]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(center.dx + sign * bodyWidth * 0.17, center.dy - bodyHeight * 0.05),
          width: bodyWidth * 0.10,
          height: bodyHeight * 0.18 * blink,
        ),
        eyePaint,
      );
    }

    // Mouth: a small smile that only appears when the eyes are open.
    if (blink > 0.5) {
      final mouth = Path()
        ..moveTo(center.dx - bodyWidth * 0.07, center.dy + bodyHeight * 0.20)
        ..quadraticBezierTo(
          center.dx,
          center.dy + bodyHeight * 0.30,
          center.dx + bodyWidth * 0.07,
          center.dy + bodyHeight * 0.20,
        );
      canvas.drawPath(
        mouth,
        Paint()
          ..color = eye
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.4, width * 0.018)
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(CompanionPainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.body != body ||
      oldDelegate.accent != accent ||
      oldDelegate.eye != eye ||
      oldDelegate.blush != blush;
}
