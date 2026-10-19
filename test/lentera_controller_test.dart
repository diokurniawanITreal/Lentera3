import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lentera3/command/command_router.dart';
import 'package:lentera3/core/messages.dart';
import 'package:lentera3/services/ai_service.dart';
import 'package:lentera3/state/lentera_state.dart';
import 'package:lentera3/voice/speech_ports.dart';

import 'helpers/fakes.dart';

void main() {
  late Harness h;

  Future<void> start([Harness? custom]) async {
    h = custom ?? h;
    await h.controller.onHomeReady();
    await settle();
  }

  setUp(() => h = Harness());
  tearDown(() => h.controller.dispose());

  group('Awal aplikasi', () {
    test('sambutan terdengar lebih dulu, mikrofon baru aktif setelahnya',
        () async {
      await start();
      expect(h.tts.spoken, [Msg.welcome]);
      expect(h.log.indexOf('tts:${Msg.welcome}'),
          lessThan(h.log.indexOf('stt.start')));
      expect(h.controller.status, VoiceStatus.listening);
      expect(h.controller.mode, AppMode.basic);
    });

    test('sambutan hanya sekali', () async {
      await start();
      await h.controller.onHomeReady();
      await settle();
      expect(h.tts.spoken.where((s) => s == Msg.welcome).length, 1);
      expect(h.stt.startCount, 1);
    });

    test('izin mikrofon ditolak: dijelaskan lewat suara, tidak mendengarkan',
        () async {
      h.stt.readiness = SttReadiness.denied;
      await start();
      expect(h.tts.spoken, [Msg.welcome, Msg.micPermission]);
      expect(h.controller.status, VoiceStatus.idle);
      expect(h.stt.startCount, 0);
    });

    test('izin ditolak permanen: sentuhan membuka pengaturan', () async {
      h.stt.readiness = SttReadiness.permanentlyDenied;
      await start();
      expect(h.tts.spoken.last, Msg.micPermissionForever);
      await h.controller.onTap();
      await settle();
      expect(h.tts.spoken.last, Msg.openingSettings);
      expect(h.settingsOpened, 1);
    });
  });

  group('Timeout 10 detik (jendela diperpendek di tes)', () {
    test('tanpa ucapan: sesi berhenti, mikrofon dilepas, status idle',
        () async {
      await start();
      final cancelsBefore = h.stt.cancelCount;
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(h.controller.status, VoiceStatus.idle);
      expect(h.stt.cancelCount, greaterThan(cancelsBefore));
      expect(h.tts.spoken.last, Msg.timeout);
    });

    test('ucapan parsial membatalkan timeout', () async {
      await start();
      h.stt.say('jam', isFinal: false);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(h.controller.status, VoiceStatus.listening);
    });

    test('pengenal berhenti sendiri sebelum waktunya: dimulai ulang',
        () async {
      await start();
      h.stt.end(SttEnd.noMatch);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(h.stt.startCount, 1); // belum (jeda 300 ms)
      await Future<void>.delayed(const Duration(milliseconds: 300));
      // jendela 150 ms telah habis -> timeout, bukan restart tanpa akhir
      expect(h.controller.status, VoiceStatus.idle);
    });

    test('sentuhan saat idle mendengarkan lagi; saat mendengarkan diabaikan',
        () async {
      await start();
      await h.controller.onTap(); // sedang mendengarkan -> diabaikan
      await settle();
      expect(h.stt.startCount, 1);

      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(h.controller.status, VoiceStatus.idle);
      await h.controller.onTap();
      await settle();
      expect(h.controller.status, VoiceStatus.listening);
      expect(h.stt.startCount, 2);
    });
  });

  group('Perpindahan mode', () {
    test('swipe kiri: Mode Dasar -> Mode AI dengan konfirmasi lalu mendengarkan',
        () async {
      await start();
      await h.controller.onSwipeLeft();
      await settle();
      expect(h.controller.mode, AppMode.ai);
      expect(h.tts.spoken.last, Msg.nowAi);
      expect(h.controller.status, VoiceStatus.listening);
      expect(h.stt.startCount, 2);
    });

    test('gestur tidak valid tidak mengubah status', () async {
      await start();
      await h.controller.onSwipeRight(); // kanan dari Mode Dasar
      await settle();
      expect(h.controller.mode, AppMode.basic);
      expect(h.tts.spoken, [Msg.welcome]);

      await h.controller.onSwipeLeft();
      await settle();
      h.advance(const Duration(seconds: 2));
      final spokenBefore = h.tts.spoken.length;
      await h.controller.onSwipeLeft(); // kiri dari Mode AI
      await settle();
      expect(h.controller.mode, AppMode.ai);
      expect(h.tts.spoken.length, spokenBefore);
    });

    test('swipe kanan: Mode AI -> Mode Dasar', () async {
      await start();
      await h.controller.onSwipeLeft();
      await settle();
      h.advance(const Duration(seconds: 2));
      await h.controller.onSwipeRight();
      await settle();
      expect(h.controller.mode, AppMode.basic);
      expect(h.tts.spoken.last, Msg.nowBasic);
      expect(h.controller.status, VoiceStatus.listening);
    });

    test('satu gestur tidak memicu dua perpindahan (debounce)', () async {
      await start();
      await h.controller.onSwipeLeft();
      await settle();
      await h.controller.onSwipeRight(); // masih dalam 500 ms
      await settle();
      expect(h.controller.mode, AppMode.ai);
    });

    test('perintah suara "LENTERA, buka Mode AI" dan "buka Mode Dasar"',
        () async {
      await start();
      h.stt.say('LENTERA, buka Mode AI');
      await settle();
      expect(h.controller.mode, AppMode.ai);
      expect(h.tts.spoken.last, Msg.nowAi);

      h.stt.say('LENTERA, buka Mode Dasar');
      await settle();
      expect(h.controller.mode, AppMode.basic);
      expect(h.tts.spoken.last, Msg.nowBasic);
    });

    test('sudah di mode tujuan lewat suara: diberi tahu, tidak pindah',
        () async {
      await start();
      h.stt.say('buka mode dasar');
      await settle();
      expect(h.tts.spoken.last, Msg.alreadyBasic);
      expect(h.controller.status, VoiceStatus.listening);
    });
  });

  group('Mode Dasar', () {
    test('perintah informasi diteruskan ke layanan, bukan Gemini', () async {
      await start();
      h.stt.say('Jam berapa sekarang?');
      await settle();
      expect(h.info.calls, [BasicIntent.time]);
      expect(h.ai.asked, isEmpty);
      expect(h.tts.spoken.last, 'jawaban:time');
      expect(h.controller.status, VoiceStatus.listening); // kembali mendengarkan
      expect(h.stt.startCount, 2);
    });

    test('perintah tidak dikenali dijawab sopan', () async {
      await start();
      h.stt.say('blablabla');
      await settle();
      expect(h.tts.spoken.last, Msg.unknownCommand);
      expect(h.ai.asked, isEmpty);
    });

    test('mikrofon dilepas sebelum jawaban dibacakan', () async {
      await start();
      h.stt.say('Hari ini hari apa?');
      await settle();
      final iCancel = h.log.lastIndexOf('stt.cancel');
      final iSpeak = h.log.indexOf('tts:jawaban:date');
      expect(iCancel, lessThan(iSpeak));
    });
  });

  group('Mode AI', () {
    Future<void> toAi() async {
      await start();
      await h.controller.onSwipeLeft();
      await settle();
      h.advance(const Duration(seconds: 2));
    }

    test('pertanyaan diteruskan ke Gemini dan jawabannya dibacakan', () async {
      await toAi();
      h.ai.reply = '**Kecerdasan buatan** adalah ... [1]';
      h.stt.say('Jelaskan apa itu kecerdasan buatan');
      await settle();
      expect(h.ai.asked, ['Jelaskan apa itu kecerdasan buatan']);
      expect(h.tts.spoken.last, 'Kecerdasan buatan adalah ...');
      expect(h.controller.answer, 'Kecerdasan buatan adalah ...');
      expect(h.controller.status, VoiceStatus.listening);
    });

    test('respons lama tidak dibacakan setelah pindah mode', () async {
      await toAi();
      h.ai.pending = Completer<String>();
      h.stt.say('Siapa presiden Indonesia saat ini?');
      await settle();
      expect(h.controller.status, VoiceStatus.processing);

      await h.controller.onSwipeRight();
      await settle();
      expect(h.controller.mode, AppMode.basic);
      expect(h.ai.cancelCount, greaterThan(0));

      h.ai.pending!.complete('Jawaban LAMA yang tidak boleh terdengar.');
      await settle();
      expect(h.tts.spoken.any((s) => s.contains('LAMA')), isFalse);
      expect(h.tts.spoken.last, Msg.nowBasic);
    });

    test('kegagalan AI dijelaskan lewat suara lalu mendengarkan lagi',
        () async {
      await toAi();
      h.ai.failWith = AiFailure.rateLimited;
      h.stt.say('Mengapa hujan bisa terjadi?');
      await settle();
      expect(h.tts.spoken.last, Msg.aiRateLimited);
      expect(h.controller.status, VoiceStatus.listening);
    });

    test('tekan-tahan saat memproses membatalkan lalu mendengarkan',
        () async {
      await toAi();
      h.ai.pending = Completer<String>();
      h.stt.say('Pertanyaan panjang');
      await settle();
      await h.controller.onLongPress();
      await settle();
      expect(h.controller.status, VoiceStatus.listening);
      h.ai.pending!.complete('terlambat');
      await settle();
      expect(h.tts.spoken.any((s) => s.contains('terlambat')), isFalse);
    });
  });

  group('Siklus hidup', () {
    test('ke latar belakang: berhenti mendengarkan; kembali: mendengarkan lagi',
        () async {
      await start();
      await h.controller.onBackground();
      await settle();
      expect(h.controller.status, VoiceStatus.idle);
      expect(h.stt.cancelCount, greaterThan(0));

      await h.controller.onResume();
      await settle();
      expect(h.controller.status, VoiceStatus.listening);
      expect(h.tts.spoken.where((s) => s == Msg.welcome).length, 1);
    });
  });
}
