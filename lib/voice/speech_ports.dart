/// Antarmuka lapisan suara. Controller hanya bergantung pada ini, sehingga
/// dapat diuji dengan fake tanpa mikrofon/speaker.
abstract class SpeechOutput {
  /// Membacakan [text]. Future selesai saat pembacaan tuntas, dihentikan
  /// lewat [stop], atau gagal. Tidak pernah dua pembacaan bersamaan.
  Future<void> speak(String text);
  Future<void> stop();
}

enum SttReadiness { ready, denied, permanentlyDenied, unavailable }

enum SttEnd { done, noMatch, speechTimeout, permission, unavailable, network, error }

abstract class SpeechInput {
  /// Memastikan izin mikrofon + layanan pengenalan siap (dapat memunculkan
  /// dialog izin sistem).
  Future<SttReadiness> ensureReady();

  /// Memulai satu sesi pengenalan. [onEnd] dipanggil paling banyak sekali.
  Future<void> start({
    required void Function(String words, bool isFinal) onResult,
    required void Function(SttEnd reason) onEnd,
    required Duration listenFor,
    required Duration pauseFor,
  });

  /// Menghentikan sesi dan MELEPAS mikrofon; tidak ada callback setelahnya.
  Future<void> cancel();
}
