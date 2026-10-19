import 'package:flutter_test/flutter_test.dart';
import 'package:lentera3/core/indonesian_speech.dart';
import 'package:lentera3/core/speech_text.dart';

void main() {
  test('numberToWords', () {
    expect(IndonesianSpeech.numberToWords(0), 'nol');
    expect(IndonesianSpeech.numberToWords(10), 'sepuluh');
    expect(IndonesianSpeech.numberToWords(11), 'sebelas');
    expect(IndonesianSpeech.numberToWords(15), 'lima belas');
    expect(IndonesianSpeech.numberToWords(20), 'dua puluh');
    expect(IndonesianSpeech.numberToWords(21), 'dua puluh satu');
    expect(IndonesianSpeech.numberToWords(59), 'lima puluh sembilan');
  });

  test('format waktu', () {
    expect(IndonesianSpeech.time(DateTime.utc(2026, 10, 13, 11, 21)),
        'Sekarang pukul sebelas lewat dua puluh satu menit siang.');
    expect(IndonesianSpeech.time(DateTime.utc(2026, 10, 13, 0, 0)),
        'Sekarang pukul dua belas tepat dini hari.');
    expect(IndonesianSpeech.time(DateTime.utc(2026, 10, 13, 15, 5)),
        'Sekarang pukul tiga lewat lima menit sore.');
    expect(IndonesianSpeech.time(DateTime.utc(2026, 10, 13, 20, 30)),
        'Sekarang pukul delapan lewat tiga puluh menit malam.');
  });

  test('zona waktu Indonesia', () {
    expect(IndonesianSpeech.zoneName(const Duration(hours: 7)),
        'Waktu Indonesia Barat');
    expect(IndonesianSpeech.zoneName(const Duration(hours: 8)),
        'Waktu Indonesia Tengah');
    expect(IndonesianSpeech.zoneName(const Duration(hours: 9)),
        'Waktu Indonesia Timur');
    expect(IndonesianSpeech.zoneName(Duration.zero), isNull);
  });

  test('format tanggal', () {
    expect(IndonesianSpeech.date(DateTime.utc(2026, 10, 13)),
        'Hari ini hari Selasa, tanggal 13 Oktober 2026.');
  });

  group('SpeechText', () {
    test('membuang markdown, tautan, dan sitasi', () {
      expect(
        SpeechText.forDisplay(
            '**Presiden** adalah X [1, 2]. Lihat https://a.b/c untuk info.'),
        'Presiden adalah X. Lihat untuk info.',
      );
    });

    test('forSpeech memberi jeda antarbaris', () {
      expect(SpeechText.forSpeech('Satu.\n\nDua'), 'Satu. Dua.');
    });

    test('split menghormati batas panjang dan tidak menghilangkan kata', () {
      final text = List.generate(12, (i) => 'Ini kalimat nomor $i yang cukup.')
          .join(' ');
      final parts = SpeechText.split(text, maxLen: 80);
      expect(parts.length, greaterThan(1));
      expect(parts.every((p) => p.length <= 80), isTrue);
      expect(parts.join(' '), text);
    });

    test('split teks kosong', () {
      expect(SpeechText.split('  '), isEmpty);
    });
  });
}
