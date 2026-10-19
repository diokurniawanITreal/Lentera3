/// Seluruh kalimat yang diucapkan sistem, terpusat agar mudah diuji/diubah.
class Msg {
  const Msg._();

  static const welcome = 'Selamat datang di LENTERA.';
  static const nowAi = 'Anda sekarang berada di Mode AI.';
  static const nowBasic = 'Anda sekarang berada di Mode Dasar.';
  static const alreadyAi = 'Anda sudah berada di Mode AI.';
  static const alreadyBasic = 'Anda sudah berada di Mode Dasar.';

  static const unknownCommand = 'Maaf, perintah belum dikenali. Silakan ulangi.';
  static const timeout =
      'Tidak ada suara terdengar. Sentuh layar untuk mendengarkan lagi.';
  static const genericError = 'Maaf, terjadi kendala. Silakan coba lagi.';

  static const micPermission =
      'Izin mikrofon diperlukan agar LENTERA dapat mendengarkan Anda. '
      'Sentuh layar untuk memberikan izin.';
  static const micPermissionForever =
      'Izin mikrofon ditolak. Sentuh layar untuk membuka pengaturan aplikasi, '
      'lalu aktifkan izin mikrofon.';
  static const openingSettings =
      'Membuka pengaturan aplikasi. Aktifkan izin mikrofon, lalu kembali ke LENTERA.';
  static const sttUnavailable =
      'Pengenalan suara tidak tersedia di perangkat ini.';
  static const sttNetwork =
      'Layanan pengenalan suara tidak dapat dijangkau. Periksa koneksi internet, '
      'lalu sentuh layar untuk mencoba lagi.';

  static const offline =
      'Tidak dapat terhubung ke internet. Periksa koneksi Anda, lalu coba lagi.';

  static const aiNotConfigured =
      'Layanan AI belum dikonfigurasi pada aplikasi ini.';
  static const aiTimeout = 'Layanan AI terlalu lama merespons. Silakan coba lagi.';
  static const aiRateLimited =
      'Batas penggunaan layanan AI sedang tercapai. Silakan coba beberapa saat lagi.';
  static const aiServer = 'Layanan AI sedang bermasalah. Silakan coba lagi nanti.';
  static const aiEmpty =
      'Maaf, saya belum mendapatkan jawaban. Silakan ajukan pertanyaan lagi.';

  static const locPermission =
      'Izin lokasi belum diberikan, sehingga lokasi Anda tidak dapat diketahui.';
  static const locPermissionForever =
      'Izin lokasi ditolak. Aktifkan izin lokasi di pengaturan aplikasi untuk memakai fitur ini.';
  static const locServiceOff =
      'Layanan lokasi di perangkat sedang mati. Nyalakan lokasi, lalu coba lagi.';
  static const locFailed =
      'Lokasi Anda belum dapat ditentukan saat ini. Silakan coba lagi.';
  static const weatherFailed =
      'Maaf, informasi cuaca belum dapat diambil saat ini. Silakan coba lagi.';
}
