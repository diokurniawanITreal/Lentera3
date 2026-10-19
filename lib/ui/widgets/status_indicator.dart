import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../state/lentera_state.dart';

/// Titik ungu + teks status. Status selalu juga berupa TEKS (dan suara),
/// tidak hanya warna.
class StatusIndicator extends StatelessWidget {
  const StatusIndicator({super.key, required this.status});
  final VoiceStatus status;

  static String label(VoiceStatus s) {
    switch (s) {
      case VoiceStatus.listening:
        return 'Sedang mendengarkan...';
      case VoiceStatus.processing:
        return 'Sedang memproses...';
      case VoiceStatus.speaking:
        return 'Sedang berbicara...';
      case VoiceStatus.idle:
        return 'Sentuh layar untuk mendengarkan';
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = status != VoiceStatus.idle;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? AppColors.statusDot : null,
            // Idle: titik berongga (bentuk berbeda, bukan hanya warna).
            border: active
                ? null
                : Border.all(color: AppColors.textSecondary, width: 2),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label(status),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
      ],
    );
  }
}
