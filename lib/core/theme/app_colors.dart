import 'dart:ui';

/// Warna diambil langsung dari file Figma "Lentera-PBL3 - Manual"
/// (dibaca via Figma API, bukan ditebak).
class AppColors {
  const AppColors._();

  static const background = Color(0xFF0B1220); // latar semua layar
  static const textPrimary = Color(0xFFF8FAFC); // judul, transkrip, label mode
  static const textSecondary = Color(0xFFCBD5E1); // tagline, prompt Gemini
  static const statusText = Color(0xFFFFFFFF);
  static const statusDot = Color(0xFF8B5CF6);

  // Tiga lapisan lingkaran (urutan luar -> dalam), satu elemen visual.
  static const ringOuter = Color(0xFF27214A);
  static const ringMiddle = Color(0xFF4C3D7A);
  static const ringInner = Color(0xFF6D5BA8);

  static const questionBubble = Color(0xFF262443);
  static const loadingShape = Color(0xFFFEF7FF);
}
