/// Pembersihan dan pemecahan teks agar nyaman didengar lewat TTS.
class SpeechText {
  const SpeechText._();

  static final _citation = RegExp(r'\[\s*\d+(?:\s*[,\-–]\s*\d+)*\s*\]');
  static final _url = RegExp(r'https?://\S+|www\.\S+');
  static final _mdMarks = RegExp(r'[*_`#>~]+');
  static final _bullet = RegExp(r'^\s*[-•]\s+', multiLine: true);
  static final _spaces = RegExp(r'[ \t]+');
  static final _blankLines = RegExp(r'\n{3,}');

  /// Untuk ditampilkan di layar: tanpa markdown, tautan, dan penanda sitasi
  /// (sitasi tidak dapat dioperasikan/didengar pengguna tunanetra).
  static String forDisplay(String raw) {
    var t = raw.replaceAll(_citation, '');
    t = t.replaceAll(_url, '');
    t = t.replaceAll(_bullet, '');
    t = t.replaceAll(_mdMarks, '');
    t = t.replaceAll(_spaces, ' ');
    t = t.replaceAll(RegExp(r' *\n *'), '\n');
    t = t.replaceAll(_blankLines, '\n\n');
    t = t.replaceAll(RegExp(r'\s+([.,;:!?])'), r'$1');
    return t.trim();
  }

  /// Untuk dibacakan: sama seperti tampilan; tiap baris menjadi kalimat
  /// sendiri sehingga ada jeda alami.
  static String forSpeech(String raw) {
    final lines = forDisplay(raw)
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .map((l) => RegExp(r'[.!?:;]$').hasMatch(l) ? l : '$l.');
    return lines.join(' ').replaceAll(_spaces, ' ').trim();
  }

  /// Memecah teks menjadi potongan <= [maxLen] karakter pada batas kalimat,
  /// agar batas panjang TTS Android tidak terlampaui dan pembacaan mudah
  /// dihentikan.
  static List<String> split(String text, {int maxLen = 400}) {
    final clean = text.trim();
    if (clean.isEmpty) return const [];
    final sentences = clean.split(RegExp(r'(?<=[.!?])\s+'));
    final out = <String>[];
    var buf = StringBuffer();
    var len = 0;
    void flush() {
      if (len > 0) out.add(buf.toString().trim());
      buf = StringBuffer();
      len = 0;
    }

    for (final s in sentences) {
      if (s.length > maxLen) {
        flush();
        // Kalimat sangat panjang: potong pada spasi terdekat.
        var rest = s;
        while (rest.length > maxLen) {
          var cut = rest.lastIndexOf(' ', maxLen);
          if (cut <= 0) cut = maxLen;
          out.add(rest.substring(0, cut).trim());
          rest = rest.substring(cut).trim();
        }
        if (rest.isNotEmpty) out.add(rest);
        continue;
      }
      if (len + s.length + 1 > maxLen) flush();
      if (len > 0) buf.write(' ');
      buf.write(s);
      len += s.length + 1;
    }
    flush();
    return out;
  }
}
