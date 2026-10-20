/// Format ucapan waktu & tanggal dalam bahasa Indonesia.
///
/// Keputusan format waktu: "pukul sebelas lewat dua puluh satu menit pagi".
/// Bentuk "12 kurang 39 menit" (Figma) sengaja tidak dipakai karena mudah
/// disalahpahami saat hanya didengar.
class IndonesianSpeech {
  const IndonesianSpeech._();

  static const _units = [
    'nol',
    'satu',
    'dua',
    'tiga',
    'empat',
    'lima',
    'enam',
    'tujuh',
    'delapan',
    'sembilan',
  ];
  static const _days = [
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
    'Minggu',
  ];
  static const _months = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];

  /// 0..99 menjadi kata. Di luar itu dikembalikan sebagai angka.
  static String numberToWords(int n) {
    if (n < 0 || n > 99) return n.toString();
    if (n < 10) return _units[n];
    if (n == 10) return 'sepuluh';
    if (n == 11) return 'sebelas';
    if (n < 20) return '${_units[n - 10]} belas';
    final tens = n ~/ 10;
    final unit = n % 10;
    final base = '${_units[tens]} puluh';
    return unit == 0 ? base : '$base ${_units[unit]}';
  }

  static String dayPart(int hour24) {
    if (hour24 < 4) return 'dini hari';
    if (hour24 < 11) return 'pagi';
    if (hour24 < 15) return 'siang';
    if (hour24 < 18) return 'sore';
    return 'malam';
  }

  static String? zoneName(Duration offset) {
    switch (offset.inMinutes) {
      case 420:
        return 'Waktu Indonesia Barat';
      case 480:
        return 'Waktu Indonesia Tengah';
      case 540:
        return 'Waktu Indonesia Timur';
    }
    return null;
  }

  static String time(DateTime t) {
    final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final hour = numberToWords(h12);
    final body = t.minute == 0
        ? 'pukul $hour tepat'
        : 'pukul $hour lewat ${numberToWords(t.minute)} menit';
    final zone = zoneName(t.timeZoneOffset);
    return 'Sekarang $body ${dayPart(t.hour)}${zone == null ? '' : ', $zone'}.';
  }

  static String date(DateTime t) {
    final day = _days[t.weekday - 1];
    final month = _months[t.month - 1];
    return 'Hari ini hari $day, tanggal ${t.day} $month ${t.year}.';
  }
}
