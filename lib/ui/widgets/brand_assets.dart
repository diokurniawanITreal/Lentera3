import 'dart:math' as math;

import 'package:flutter/material.dart';


/// Wordmark "LENTERA" (di Figma berupa text-path vektor).
///
/// Letakkan hasil ekspor Figma (node 2:55) di
/// assets/images/lentera_wordmark.png. Selama berkas belum ada, dipakai
/// teks Atkinson Hyperlegible sebagai pengganti sementara.
class LenteraWordmark extends StatelessWidget {
  const LenteraWordmark({super.key});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/lentera_wordmark.png',
      width: 260,
      excludeFromSemantics: true,
      errorBuilder: (context, error, stack) => Text(
        'LENTERA',
        style: Theme.of(context).textTheme.displaySmall?.copyWith(
              fontSize: 48,
              letterSpacing: 6,
            ),
      ),
    );
  }
}

/// Ikon Gemini berwarna. Aset resmi: assets/images/gemini_icon.png
/// (ekspor dari Figma). Pengganti sementara: bintang 4 sudut bergradien.
class GeminiIcon extends StatelessWidget {
  const GeminiIcon({super.key, this.size = 52});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/gemini_icon.png',
      width: size,
      height: size,
      excludeFromSemantics: true,
      errorBuilder: (context, error, stack) => CustomPaint(
        size: Size.square(size),
        painter: _SparklePainter(),
      ),
    );
  }
}

/// Wordmark "Gemini" putih. Aset resmi: assets/images/gemini_wordmark.png.
class GeminiWordmark extends StatelessWidget {
  const GeminiWordmark({super.key});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/gemini_wordmark.png',
      height: 38,
      excludeFromSemantics: true,
      errorBuilder: (context, error, stack) => Text(
        'Gemini',
        style: Theme.of(context).textTheme.displaySmall?.copyWith(fontSize: 36),
      ),
    );
  }
}

class _SparklePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final path = Path();
    const pts = 4;
    for (var i = 0; i < pts * 2; i++) {
      final a = -math.pi / 2 + i * math.pi / pts;
      final rad = i.isEven ? r : r * 0.18;
      final p = c + Offset(math.cos(a), math.sin(a)) * rad;
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    final rect = Offset.zero & size;
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF4285F4), Color(0xFF9B72CB), Color(0xFFD96570)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

