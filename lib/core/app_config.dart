/// Konfigurasi terpusat aplikasi LENTERA.
///
/// Nilai rahasia / endpoint dapat dikirim saat build menggunakan `--dart-define`:
///
/// 1. Menggunakan Backend Proxy Cloudflare Worker (Direkomendasikan untuk Production):
///    ```bash
///    flutter run \
///      --dart-define=LENTERA_AI_URL=https://lentera-ai.example.workers.dev \
///      --dart-define=LENTERA_CLIENT_TOKEN=token-klien
///    ```
///
/// 2. Menggunakan Direct Google Gemini API (Mudah untuk Development / Testing):
///    ```bash
///    flutter run \
///      --dart-define=GEMINI_API_KEY=AIzaSy... \
///      --dart-define=GEMINI_MODEL=gemini-2.5-flash
///    ```
class AppConfig {
  const AppConfig._();

  // ──────────────────────────────────────────────────────────────────────────
  //  KONFIGURASI AI (GEMINI PROXY & DIRECT API)
  // ──────────────────────────────────────────────────────────────────────────

  /// Endpoint backend proxy AI (mis. Cloudflare Worker).
  static const String aiEndpoint = String.fromEnvironment('LENTERA_AI_URL');

  /// Token klien untuk autentikasi ke backend proxy (opsional bila diproteksi).
  static const String clientToken =
      String.fromEnvironment('LENTERA_CLIENT_TOKEN');

  /// API Key Google Gemini untuk koneksi langsung (Google AI Studio).
  /// Berguna saat pengembangan lokal tanpa perlu deploy Cloudflare Worker.
  static const String geminiApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: String.fromEnvironment('LENTERA_GEMINI_API_KEY'),
  );

  /// Model Gemini yang digunakan saat koneksi langsung.
  /// Default: 'gemini-2.5-flash' (selaras dengan Cloudflare Worker).
  static const String geminiModel = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-2.5-flash',
  );

  /// URL dasar Google Generative Language API untuk direct request.
  static const String geminiBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  /// System prompt untuk asisten suara LENTERA (khusus pengguna tunanetra).
  /// Menjamin jawaban nyaman didengar lewat Text-to-Speech (TTS).
  static const String aiSystemPrompt =
      'Kamu adalah asisten suara untuk penyandang tunanetra di aplikasi LENTERA. '
      'Jawab dalam bahasa Indonesia yang jelas, ringkas (maksimal sekitar 120 kata), '
      'dan enak DIDENGAR. Jangan memakai markdown, tabel, daftar bernomor panjang, '
      'emoji, tautan, atau penanda sitasi seperti [1]. Untuk informasi terkini, '
      'sebutkan bila tidak yakin. Jangan mengaku selalu benar.';

  /// Memeriksa apakah proxy backend telah dikonfigurasi.
  static bool get isProxyConfigured {
    final uri = Uri.tryParse(aiEndpoint);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  /// Memeriksa apakah API Key direct Gemini telah dikonfigurasi.
  static bool get isDirectGeminiConfigured => geminiApiKey.trim().isNotEmpty;

  /// Memeriksa apakah fitur AI dapat digunakan (salah satu metode aktif).
  static bool get isAiConfigured => isProxyConfigured || isDirectGeminiConfigured;

  // ──────────────────────────────────────────────────────────────────────────
  //  DURASI & TIMEOUT
  // ──────────────────────────────────────────────────────────────────────────

  /// Durasi splash screen (spesifikasi: 3 detik).
  static const Duration splashDuration = Duration(seconds: 3);

  /// Batas menunggu ucapan yang valid (spesifikasi: 10 detik).
  static const Duration listenWindow = Duration(seconds: 10);

  /// Batas panjang satu sesi pengenalan (setelah pengguna mulai bicara).
  static const Duration recognizerListenFor = Duration(seconds: 20);
  static const Duration recognizerPauseFor = Duration(seconds: 3);

  /// Batas waktu request HTTP umum (misal cuaca / geocoding).
  static const Duration httpTimeout = Duration(seconds: 10);

  /// Batas waktu request ke AI (25 detik untuk respon AI).
  static const Duration aiTimeout = Duration(seconds: 25);

  // ──────────────────────────────────────────────────────────────────────────
  //  LOCALE & SUARA
  // ──────────────────────────────────────────────────────────────────────────

  static const String sttLocalePrefix = 'id';
  static const String ttsLanguage = 'id-ID';
}
