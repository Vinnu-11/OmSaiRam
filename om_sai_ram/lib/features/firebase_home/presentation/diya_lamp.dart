import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// A clay diya whose flame flickers briefly when lit, then rests. It never
/// animates forever, and stays still when the device asks for reduced motion.
class DiyaLamp extends StatefulWidget {
  final double size;
  const DiyaLamp({super.key, this.size = 96});
  @override
  State<DiyaLamp> createState() => DiyaLampState();
}

class DiyaLampState extends State<DiyaLamp> with SingleTickerProviderStateMixin {
  late final _flicker = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2400));

  /// Replays the short flicker, for example after the reader taps the card.
  void light() {
    if (!mounted || MediaQuery.of(context).disableAnimations) return;
    _flicker.forward(from: 0);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => light());
  }

  @override
  void dispose() {
    _flicker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
      child: AnimatedBuilder(
          animation: _flicker,
          builder: (context, _) => CustomPaint(
              size: Size.square(widget.size),
              painter: _DiyaPainter(_flicker.value))));
}

class _DiyaPainter extends CustomPainter {
  final double t;
  _DiyaPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // Two overlapping waves fade out, so the flame settles instead of looping.
    final sway = math.sin(t * math.pi * 6) * (1 - t) * 0.06;
    final lift = 1 + math.sin(t * math.pi * 9) * (1 - t) * 0.08;
    final base = Offset(w / 2, h * 0.60);
    final tip = Offset(w / 2 + w * sway, h * 0.60 - h * 0.46 * lift);

    canvas.drawCircle(
        Offset(w / 2, h * 0.40),
        w * 0.42,
        Paint()
          ..shader = RadialGradient(colors: [
            AppColors.marigold.withValues(alpha: 0.45),
            AppColors.marigold.withValues(alpha: 0),
          ]).createShader(Rect.fromCircle(
              center: Offset(w / 2, h * 0.40), radius: w * 0.42)));

    Path flame(double width) => Path()
      ..moveTo(base.dx, base.dy)
      ..quadraticBezierTo(base.dx - w * width, base.dy - h * 0.16, tip.dx, tip.dy)
      ..quadraticBezierTo(base.dx + w * width, base.dy - h * 0.16, base.dx, base.dy)
      ..close();
    canvas.drawPath(flame(0.20), Paint()..color = AppColors.kesari);
    canvas.drawPath(flame(0.11), Paint()..color = AppColors.marigold);
    canvas.drawCircle(Offset(base.dx, base.dy - h * 0.07), w * 0.035,
        Paint()..color = const Color(0xFFFFF4C2));

    final bowl = Path()
      ..moveTo(w * 0.12, h * 0.62)
      ..quadraticBezierTo(w * 0.50, h * 1.04, w * 0.88, h * 0.62)
      ..quadraticBezierTo(w * 0.50, h * 0.72, w * 0.12, h * 0.62)
      ..close();
    canvas.drawPath(bowl, Paint()..color = const Color(0xFFC96A2B));
    canvas.drawPath(
        Path()
          ..moveTo(w * 0.12, h * 0.62)
          ..quadraticBezierTo(w * 0.50, h * 0.72, w * 0.88, h * 0.62),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.03
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFFF0A860));
  }

  @override
  bool shouldRepaint(_DiyaPainter old) => old.t != t;
}
