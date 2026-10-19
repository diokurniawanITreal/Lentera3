import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_config.dart';
import '../core/theme/app_colors.dart';
import 'widgets/brand_assets.dart';

/// Splash 3 detik tanpa pekerjaan jaringan/izin, lalu [onFinished].
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onFinished});
  final VoidCallback onFinished;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(AppConfig.splashDuration, () {
      if (mounted) widget.onFinished();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Semantics(
        container: true,
        label: 'LENTERA. Layanan Informasi Harian Ramah Akses bagi Tunanetra.',
        child: ExcludeSemantics(
          child: SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LenteraWordmark(),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 311),
                    child: Text(
                      'Layanan Informasi Harian Ramah Akses bagi Tunanetra',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
