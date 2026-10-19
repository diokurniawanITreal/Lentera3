/// Konfigurasi aplikasi. Nilai rahasia/endpoint TIDAK ditulis di source code,
/// melainkan dikirim saat build:
///
///   flutter run --dart-define=LENTERA_AI_URL=https://lentera-ai.example.workers.dev \
///               --dart-define=LENTERA_CLIENT_TOKEN=token-klien
///
/// API key Gemini hanya ada di backend proxy (lihat folder backend/).
class AppConfig {
  const AppConfig._();

  static const String aiEndpoint = String.fromEnvironment('LENTERA_AI_URL');
  static const String clientToken =
      String.fromEnvironment('LENTERA_CLIENT_TOKEN');

  /// Durasi splash screen (spesifikasi: 3 detik).
  static const Duration splashDuration = Duration(seconds: 3);

  /// Batas menunggu ucapan yang valid (spesifikasi: 10 detik).
  static const Duration listenWindow = Duration(seconds: 10);

  /// Batas panjang satu sesi pengenalan (setelah pengguna mulai bicara).
  static const Duration recognizerListenFor = Duration(seconds: 20);
  static const Duration recognizerPauseFor = Duration(seconds: 3);

  static const Duration httpTimeout = Duration(seconds: 10);
  static const Duration aiTimeout = Duration(seconds: 25);

  static const String sttLocalePrefix = 'id';
  static const String ttsLanguage = 'id-ID';
}
