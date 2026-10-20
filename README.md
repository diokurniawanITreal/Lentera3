# LENTERA — Layanan Informasi Harian Ramah Akses

Aplikasi informasi harian berbasis suara LENTERA12345 (_voice-first_, _accessibility-first_) untuk penyandang tunanetra.
Flutter/Dart. Desain: Figma "Lentera-PBL3 - Manual" (nilai warna/font/ukuran dibaca langsung dari Figma).

## Menjalankan

```bash
flutter pub get
flutter run \
  --dart-define=LENTERA_AI_URL=https://<worker-anda>.workers.dev \
  --dart-define=LENTERA_CLIENT_TOKEN=<token-klien>
flutter analyze && dart format . && flutter test
```

Tanpa `LENTERA_AI_URL`, Mode Dasar tetap berfungsi; Mode AI menjawab "Layanan AI belum dikonfigurasi".

### Backend Gemini (folder `backend/cloudflare-worker`)

```bash
cd backend/cloudflare-worker
npx wrangler secret put GEMINI_API_KEY   # kunci dari Google AI Studio
npx wrangler secret put CLIENT_TOKEN     # token bersama (pembatas dasar, bukan rahasia kuat)
npx wrangler deploy
```

Aktifkan _rate limiting_ Cloudflare per IP. Model default `gemini-2.5-flash` — **verifikasi** model yang masih tersedia (`GEMINI_MODEL`).
Grounding Google Search aktif secara default (`ENABLE_SEARCH=false` untuk mematikan).

### iOS (belum dikonfigurasi penuh)

Setelah `flutter pub get` & `pod install` membuat `ios/Podfile`, tambahkan pada `post_install` makro `permission_handler`:
`PERMISSION_MICROPHONE=1`, `PERMISSION_SPEECH_RECOGNIZER=1`, `PERMISSION_LOCATION_WHENINUSE=1`. Info.plist sudah berisi teks izin.

### Aset merek (perlu diekspor dari Figma)

Sandbox pengembangan tidak dapat mengunduh dari Figma, sehingga tiga aset berikut memakai **pengganti sementara**.
Ekspor dari Figma (PNG @3x) ke `assets/images/`; aplikasi otomatis memakainya:
| Berkas | Node Figma | Pengganti sementara |
|---|---|---|
| `lentera_wordmark.png` | `2:55` | teks Atkinson Hyperlegible 48 px |
| `gemini_icon.png` | `16:127` / `41:150` | bintang 4 sudut bergradien |
| `gemini_wordmark.png` | `16:128` | teks "Gemini" |

## Struktur

```
lib/
  main.dart, app.dart            # perakitan, tema, siklus hidup, splash -> home
  core/                          # config, pesan suara, format waktu/tanggal, pembersih teks TTS, tema
  state/lentera_controller.dart  # orkestrasi mode + sesi suara (sumber kebenaran tunggal)
  voice/                         # antarmuka + implementasi STT/TTS
  command/command_router.dart    # pengenalan maksud (murni, teruji)
  services/                      # waktu/lokasi/cuaca (Open-Meteo)/klien proxy Gemini
  ui/                            # splash, home (Mode Dasar & AI), widget
test/                            # unit, controller (dengan fake), widget
backend/cloudflare-worker/       # proxy Gemini
```

## Keputusan desain (dari audit Figma)

- **Cuaca:** Open-Meteo (tanpa kunci, HTTPS). Berada di balik `WeatherProvider`, dapat diganti BMKG.
- **Waktu:** "pukul sebelas lewat dua puluh satu menit siang, Waktu Indonesia Barat" (bukan "12 kurang 39 menit").
- **Logo Gemini:** warna merek dikecualikan dari larangan aksen sian; tidak dipakai sebagai warna UI.
- **Sitasi `[1, 2]` dan tautan (frame Figma hasil AI):** tidak ditampilkan/dibacakan karena tidak dapat dioperasikan pengguna tunanetra.
- **Status idle/timeout dan error:** tidak ada di Figma → memakai layout yang sama, status berupa teks "Sentuh layar untuk mendengarkan" dengan titik berongga.
- **Label "Mode Ai" di Figma** ditulis "Mode AI" agar konsisten dengan suara.
- **Mode AI:** perintah dasar bentuk pendek persis ("jam berapa sekarang") dijawab lokal karena Gemini tidak tahu jam/lokasi perangkat.
- **Menghentikan pembacaan:** karena mikrofon sengaja mati saat TTS (mencegah gema), interupsi lewat _suara_ tidak layak. Gantinya: tekan-tahan layar, atau aksi semantik "Hentikan dan dengarkan" di menu aksi TalkBack/VoiceOver. **Perlu persetujuan.**
- **Teks status** 16 px mengikuti Figma; kontras terhitung (lihat bawah). Ukuran mengikuti skala teks sistem.
- Titik status ungu `#8B5CF6` memiliki kontras 4,42:1 terhadap latar (elemen non-teks, ambang WCAG 3:1 terpenuhi; informasi status juga disampaikan teks dan suara).

Kontras (WCAG, dihitung): teks utama 17,9:1 · sekunder 12,6:1 · status 18,7:1 · teks di gelembung 14,2:1 · ikon di lingkaran dalam 5,4:1.

## Status pengerjaan (jujur)

**Belum ada yang dikompilasi atau dijalankan.** Lingkungan penulis tidak memiliki Flutter/Dart SDK dan pub.dev diblokir,
sehingga `flutter analyze`, `flutter test`, dan seluruh pengujian perangkat **belum pernah dijalankan**. Versi paket pada `pubspec.yaml`
ditulis dari pengetahuan penulis dan **belum diverifikasi** terhadap pub.dev; pada Flutter 3.47/Dart 3.13 mungkin perlu
penyesuaian API kecil. Langkah pertama Anda: `flutter pub get && flutter analyze && flutter test`, lalu kirim keluarannya agar diperbaiki.

| #   | Kriteria penerimaan                      | Status                                                                |
| --- | ---------------------------------------- | --------------------------------------------------------------------- |
| 1–2 | Splash 3 dtk → Mode Dasar                | Kode + widget test ditulis; belum dijalankan                          |
| 3–4 | Sambutan sekali, mendengarkan setelahnya | Kode + unit test (fake); belum dijalankan; belum di perangkat         |
| 5   | Timeout 10 dtk                           | Kode + unit test (jendela dipendekkan); belum di perangkat            |
| 6   | Sentuhan mendengarkan kembali            | Kode + unit test; belum di perangkat                                  |
| 7–9 | Swipe/suara pindah mode + konfirmasi     | Kode + unit test; **konflik swipe vs TalkBack perlu uji perangkat**   |
| 10  | Perintah suara pindah mode               | Router teruji (teks); akurasi STT Indonesia belum diuji               |
| 11  | Layanan dasar                            | Kode; API cuaca/lokasi belum diuji nyata                              |
| 12  | Gemini                                   | Kode + worker; butuh kredensial & deploy                              |
| 13  | TTS tanpa tumpang tindih                 | Dijamin alur serial di kode; belum di perangkat                       |
| 14  | Penanganan kegagalan                     | Kode; sebagian dengan fake; belum di perangkat                        |
| 15  | Tanpa database/penyimpanan               | Terpenuhi (tidak ada penyimpanan; log tanpa isi ucapan)               |
| 16  | Konsisten dengan Figma                   | Nilai dari Figma; **belum dibandingkan visual**; aset merek sementara |
| 17  | Operasional tanpa navigasi visual        | Desain mendukung; **wajib uji TalkBack/VoiceOver nyata**              |

## Risiko yang diketahui

- Swipe satu jari diambil TalkBack; jalur setara: perintah suara + aksi semantik (sudah ada).
- STT Android sering berhenti sendiri dan dapat berbunyi saat dimulai ulang; ada logika mulai-ulang dalam jendela 10 dtk.
- TTS aplikasi dan TalkBack dapat berbicara bersamaan saat pembaca layar aktif — perlu diuji di perangkat.
- Pengenalan bahasa Indonesia bergantung pada layanan perangkat.
