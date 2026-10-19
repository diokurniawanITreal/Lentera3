import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Indikator pemrosesan Mode Dasar: bentuk bergerigi putih (mengikuti
/// "Loading indicator" Material 3 di Figma), berputar pelan. Statis bila
/// pengguna menonaktifkan animasi.
class LoadingShape extends StatefulWidget {
  const LoadingShape({super.key, this.size = 44});
  final double size;

  @override
  State<LoadingShape> createState() => _LoadingShapeState();
}

class _LoadingShapeState extends State<LoadingShape>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _c,
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _CookiePainter(),
      ),
    );
  }
}

class _CookiePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(r, r);
    final path = Path();
    const steps = 160;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps * 2 * math.pi;
      final rad = r * (0.88 + 0.12 * math.cos(8 * t));
      final p = center + Offset(math.cos(t), math.sin(t)) * rad;
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = AppColors.loadingShape);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
