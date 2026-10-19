import 'package:flutter_test/flutter_test.dart';
import 'package:lentera3/command/command_router.dart';
import 'package:lentera3/state/lentera_state.dart';

void main() {
  const router = CommandRouter();

  BasicIntent? basic(String s, AppMode m) {
    final c = router.parse(s, mode: m);
    return c is BasicCommand ? c.intent : null;
  }

  AppMode? mode(String s, AppMode m) {
    final c = router.parse(s, mode: m);
    return c is SwitchModeCommand ? c.target : null;
  }

  group('Mode Dasar', () {
    test('waktu', () {
      expect(basic('Jam berapa sekarang?', AppMode.basic), BasicIntent.time);
      expect(basic('Berapa waktu saat ini?', AppMode.basic), BasicIntent.time);
      expect(basic('pukul berapa', AppMode.basic), BasicIntent.time);
    });
    test('hari dan tanggal', () {
      expect(basic('Hari ini hari apa?', AppMode.basic), BasicIntent.date);
      expect(basic('Tanggal berapa sekarang?', AppMode.basic), BasicIntent.date);
    });
    test('lokasi', () {
      expect(basic('Di mana lokasi saya sekarang?', AppMode.basic),
          BasicIntent.location);
      expect(basic('dimana posisi saya', AppMode.basic), BasicIntent.location);
    });
    test('cuaca dan hujan', () {
      expect(basic('Bagaimana cuaca hari ini?', AppMode.basic),
          BasicIntent.weather);
      expect(basic('Apakah sekarang sedang hujan?', AppMode.basic),
          BasicIntent.rain);
    });
    test('perintah tak dikenal / kosong', () {
      expect(router.parse('blablabla', mode: AppMode.basic),
          isA<UnknownCommand>());
      expect(router.parse('   ', mode: AppMode.basic), isA<UnknownCommand>());
      // pertanyaan umum tidak boleh dikira cuaca, dan tidak memanggil AI
      expect(router.parse('Mengapa hujan bisa terjadi?', mode: AppMode.basic),
          isA<UnknownCommand>());
    });
  });

  group('Pindah mode (kedua mode)', () {
    test('ke Mode AI', () {
      expect(mode('LENTERA, buka Mode AI', AppMode.basic), AppMode.ai);
      expect(mode('buka mode a i', AppMode.basic), AppMode.ai);
      expect(mode('Mode AI', AppMode.basic), AppMode.ai);
    });
    test('ke Mode Dasar dan alias mode utama', () {
      expect(mode('LENTERA, buka Mode Dasar.', AppMode.ai), AppMode.basic);
      expect(mode('mode utama', AppMode.ai), AppMode.basic);
      expect(mode('kembali ke mode dasar', AppMode.ai), AppMode.basic);
    });
  });

  group('Mode AI', () {
    test('pertanyaan bebas diteruskan ke Gemini', () {
      final c = router.parse('Mengapa hujan bisa terjadi?', mode: AppMode.ai);
      expect(c, isA<AiQuestionCommand>());
      expect((c as AiQuestionCommand).question, 'Mengapa hujan bisa terjadi?');
      expect(
          router.parse('Jelaskan apa itu kecerdasan buatan', mode: AppMode.ai),
          isA<AiQuestionCommand>());
    });
    test('hanya bentuk pendek persis yang dijawab lokal', () {
      expect(basic('Jam berapa sekarang?', AppMode.ai), BasicIntent.time);
      expect(basic('Bagaimana cuaca hari ini?', AppMode.ai),
          BasicIntent.weather);
      expect(router.parse('Jam berapa pesawat berangkat?', mode: AppMode.ai),
          isA<AiQuestionCommand>());
    });
  });
}
