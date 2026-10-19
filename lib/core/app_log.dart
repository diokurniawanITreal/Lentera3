import 'package:flutter/foundation.dart';

/// Log diagnostik. Hanya aktif pada mode debug dan TIDAK PERNAH memuat isi
/// ucapan, jawaban, atau lokasi pengguna.
class AppLog {
  const AppLog._();
  static void d(String tag, String message) {
    if (kDebugMode) debugPrint('[LENTERA/$tag] $message');
  }
}
