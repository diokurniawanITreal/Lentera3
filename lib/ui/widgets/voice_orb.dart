import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Tiga lingkaran konsentris (200/150/100) sebagai SATU elemen visual.
/// Ukuran dan warna diambil dari Figma.
class VoiceOrb extends StatelessWidget {
  const VoiceOrb({super.key, required this.icon, this.iconSize = 60});

  final IconData icon;
  final double iconSize;

  Widget _circle(double d, Color c) => Container(
        width: d,
        height: d,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _circle(200, AppColors.ringOuter),
          _circle(150, AppColors.ringMiddle),
          _circle(100, AppColors.ringInner),
          Icon(icon, size: iconSize, color: AppColors.textPrimary),
        ],
      ),
    );
  }
}
