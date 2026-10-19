import '../state/lentera_state.dart';

enum BasicIntent { time, date, location, weather, rain }

sealed class Command {
  const Command();
}

class SwitchModeCommand extends Command {
  const SwitchModeCommand(this.target);
  final AppMode target;
}

class BasicCommand extends Command {
  const BasicCommand(this.intent);
  final BasicIntent intent;
}

class AiQuestionCommand extends Command {
  const AiQuestionCommand(this.question);
  final String question;
}

class UnknownCommand extends Command {
  const UnknownCommand();
}

/// Mengenali maksud ucapan. Murni (tanpa efek samping) sehingga mudah diuji.
///
/// Aturan:
///  * Perintah pindah mode berlaku di kedua mode.
///  * Mode Dasar: pola longgar untuk waktu/tanggal/lokasi/cuaca; selain itu
///    perintah tidak dikenali. Gemini TIDAK dipanggil dari Mode Dasar.
///  * Mode AI: hanya bentuk pendek persis (mis. "jam berapa sekarang") yang
///    dijawab lokal karena Gemini tidak tahu jam/lokasi perangkat; sisanya
///    dikirim ke Gemini.
class CommandRouter {
  const CommandRouter();

  static final _wakePrefix =
      RegExp(r'^(?:(?:hai|halo|hei|hey|ok|oke)\s+)?l[ae]nt[ae]ra\s+');
  static final _wakeSuffix = RegExp(r'\s+l[ae]nt[ae]ra$');

  static const _verbs = r'(?:(?:tolong|silakan|coba)\s+)?';
  static final _toAi = RegExp(
      '^$_verbs(?:(?:buka|masuk|pindah|ganti|beralih|aktifkan)\\s+)?(?:ke\\s+)?mode ai\$');
  static final _toBasic = RegExp(
      '^$_verbs(?:(?:buka|masuk|pindah|ganti|beralih|aktifkan|kembali)\\s+)?(?:ke\\s+)?mode (?:dasar|utama)\$');

  static final _basicLoose = <BasicIntent, List<RegExp>>{
    BasicIntent.rain: [
      RegExp(r'\b(?:apakah|apa)\s+(?:sekarang\s+|saat ini\s+|hari ini\s+)?(?:sedang\s+|lagi\s+|akan\s+)?(?:turun\s+)?hujan\b'),
      RegExp(r'\b(?:sedang|lagi)\s+hujan\b'),
    ],
    BasicIntent.weather: [
      RegExp(r'\bcuaca\b'),
      RegExp(r'\bsuhu\b'),
    ],
    BasicIntent.time: [
      RegExp(r'\b(?:jam|pukul)\s+berapa\b'),
      RegExp(r'\bberapa\s+waktu\b'),
      RegExp(r'\bwaktu\s+(?:saat ini|sekarang|setempat)\b'),
      RegExp(r'\bjam\s+(?:sekarang|saat ini)\b'),
    ],
    BasicIntent.date: [
      RegExp(r'\bhari\s+apa\b'),
      RegExp(r'\btanggal\s+berapa\b'),
      RegExp(r'\btanggal\s+(?:sekarang|hari ini|saat ini)\b'),
      RegExp(r'\bhari\s+dan\s+tanggal\b'),
      RegExp(r'\bhari ini tanggal\b'),
    ],
    BasicIntent.location: [
      RegExp(r'\b(?:di mana|dimana)\s+(?:lokasi|posisi|letak)?\s*(?:saya|aku)\b'),
      RegExp(r'\b(?:lokasi|posisi)\s+(?:saya|aku)\b'),
      RegExp(r'\bsaya\s+(?:sedang\s+)?(?:ada\s+)?di\s*mana\b'),
      RegExp(r'\blokasi\s+(?:saat ini|sekarang)\b'),
    ],
  };

  static final _basicStrict = <BasicIntent, List<RegExp>>{
    BasicIntent.rain: [
      RegExp(r'^apakah (?:sekarang |saat ini )?(?:sedang )?hujan$'),
    ],
    BasicIntent.weather: [
      RegExp(r'^(?:bagaimana |gimana )?cuaca(?: hari ini| sekarang| saat ini)?$'),
    ],
    BasicIntent.time: [
      RegExp(r'^(?:jam|pukul) berapa(?: sekarang| saat ini| ini)?$'),
      RegExp(r'^(?:berapa )?waktu(?: saat ini| sekarang)$'),
    ],
    BasicIntent.date: [
      RegExp(r'^(?:hari ini )?hari apa(?: ini| sekarang)?$'),
      RegExp(r'^(?:hari ini )?tanggal berapa(?: sekarang| ini)?$'),
    ],
    BasicIntent.location: [
      RegExp(r'^(?:di mana|dimana) (?:lokasi |posisi )?saya(?: sekarang| saat ini)?$'),
    ],
  };

  /// Huruf kecil, tanda baca dibuang, variasi pengejaan "AI" disatukan,
  /// kata panggil "LENTERA" dibuang.
  static String normalize(String raw) {
    var t = raw.toLowerCase();
    t = t.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    t = t.replaceAllMapped(
        RegExp(r'\bmode (?:a i|ei ai|e ai|ay ai|a ay|ei ay|ay|ei)\b'),
        (_) => 'mode ai');
    t = t.replaceFirst(_wakePrefix, '');
    t = t.replaceFirst(_wakeSuffix, '');
    return t.trim();
  }

  Command parse(String raw, {required AppMode mode}) {
    final t = normalize(raw);
    if (t.isEmpty) return const UnknownCommand();

    if (_toAi.hasMatch(t)) return const SwitchModeCommand(AppMode.ai);
    if (_toBasic.hasMatch(t)) return const SwitchModeCommand(AppMode.basic);

    final table = mode == AppMode.basic ? _basicLoose : _basicStrict;
    for (final entry in table.entries) {
      for (final re in entry.value) {
        if (re.hasMatch(t)) return BasicCommand(entry.key);
      }
    }

    if (mode == AppMode.ai) return AiQuestionCommand(raw.trim());
    return const UnknownCommand();
  }
}
