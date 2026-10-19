import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Tipografi terpusat: Atkinson Hyperlegible (aset lokal).
/// Ukuran mengikuti Figma: 32 (judul), 24 (transkrip), 20 (jawaban/gelembung),
/// 16 (label mode & status).
class AppTheme {
  const AppTheme._();

  static const fontFamily = 'AtkinsonHyperlegible';

  static ThemeData dark() {
    TextStyle s(double size, Color color) => TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          color: color,
          height: 1.25,
        );

    final textTheme = TextTheme(
      displaySmall: s(32, AppColors.textPrimary), // judul
      headlineSmall: s(24, AppColors.textPrimary), // transkrip / hasil
      bodyLarge: s(20, AppColors.textPrimary), // jawaban AI, gelembung
      bodyMedium: s(16, AppColors.textPrimary), // label mode
      labelLarge: s(16, AppColors.statusText), // status
      titleMedium: s(32, AppColors.textSecondary), // prompt Gemini
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.ringInner,
        brightness: Brightness.dark,
        surface: AppColors.background,
      ),
      textTheme: textTheme,
    );
  }
}
