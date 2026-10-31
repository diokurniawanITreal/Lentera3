import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../command/command_router.dart';
import '../core/app_config.dart';
import '../core/app_log.dart';
import '../core/messages.dart';
import '../core/speech_text.dart';
import '../services/ai_service.dart';
import '../services/basic_info_service.dart';
import '../voice/speech_ports.dart';
import 'lentera_state.dart';

enum HapticKind { listening, timeout, error }

void _systemHaptics(HapticKind kind) {
  switch (kind) {
    case HapticKind.listening:
      // Getaran GANDA saat mikrofon mulai mendengarkan: dua ketukan pendek
      // berjarak dekat sehingga pengguna tunanetra merasakan bahwa mic
      // sudah aktif dan boleh berbicara. Pola ganda sengaja dibedakan dari
      // sinyal lain (timeout = satu ketuk sedang, error = satu ketuk berat)
      // agar tidak tertukar. Ketukan kedua tidak perlu dibatalkan walau
      // sesi berganti — hanya getaran perangkat, tanpa efek ke sesi suara.
      HapticFeedback.mediumImpact();
      unawaited(Future<void>.delayed(const Duration(milliseconds: 150), () {
        HapticFeedback.mediumImpact();
      }));
    case HapticKind.timeout:
      HapticFeedback.mediumImpact();
    case HapticKind.error:
      HapticFeedback.heavyImpact();
  }
}

/// Orkestrator sesi suara dan mode aplikasi (tanpa dependensi ke widget).
///
/// Prinsip kendali konkurensi:
///  * [_epoch] naik setiap alur tingkat-atas baru dimulai (sentuhan, pindah
///    mode, interupsi, latar belakang). Setiap pekerjaan async memeriksa
///    epoch-nya sebelum bertindak, sehingga respons lama TIDAK PERNAH
///    dibacakan pada mode/sesi yang baru.
///  * [_listenToken] naik setiap jendela mendengarkan berakhir, sehingga
///    callback STT yang terlambat diabaikan.
///  * Mikrofon tidak pernah aktif saat TTS berbicara (alur selalu serial).
class LenteraController extends ChangeNotifier {
  LenteraController({
    required SpeechOutput tts,
    required SpeechInput stt,
    required InfoAnswerer info,
    required AiService ai,
    CommandRouter router = const CommandRouter(),
    DateTime Function()? clock,
    Duration? listenWindow,
    void Function(HapticKind)? haptics,
    Future<void> Function()? openSettings,
  })  : _tts = tts,
        _stt = stt,
        _info = info,
        _ai = ai,
        _router = router,
        _clock = clock ?? DateTime.now,
        _listenWindow = listenWindow ?? AppConfig.listenWindow,
        _haptics = haptics ?? _systemHaptics,
        _openSettings = openSettings ?? (() async => openAppSettings());

  final SpeechOutput _tts;
  final SpeechInput _stt;
  final InfoAnswerer _info;
  final AiService _ai;
  final CommandRouter _router;
  final DateTime Function() _clock;
  final Duration _listenWindow;
  final void Function(HapticKind) _haptics;
  final Future<void> Function() _openSettings;

  AppMode _mode = AppMode.basic;
  VoiceStatus _status = VoiceStatus.idle;
  String _transcript = '';
  String _question = '';
  String _answer = '';

  int _epoch = 0;
  int _listenToken = 0;
  Timer? _deadline;
  Timer? _restartTimer;
  DateTime _deadlineAt = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastWords = '';
  int _restarts = 0;
  bool _started = false;
  bool _disposed = false;
  bool _wasBackgrounded = false;
  bool _micPermanentlyDenied = false;
  DateTime? _lastSwitchAt;

  AppMode get mode => _mode;
  VoiceStatus get status => _status;
  String get transcript => _transcript;
  String get question => _question;
  String get answer => _answer;

  // ---------------------------------------------------------------- publik

  /// Dipanggil sekali saat Mode Dasar siap: sambutan, lalu mendengarkan.
  Future<void> onHomeReady() async {
    if (_started || _disposed) return;
    _started = true;
    final e = await _begin();
    if (!await _say(e, Msg.welcome)) return;
    await _listen(e);
  }

  /// Sentuhan pada area layar (termasuk ikon mikrofon di tengah).
  Future<void> onTap() async {
    if (!_started || _disposed) return;
    if (_status != VoiceStatus.idle) return; // abaikan saat aktif/berbicara
    // Konfirmasi sentuhan SEGERA: getaran ganda memberi tahu bahwa mic
    // akan aktif. Ditembakkan dulu (sebelum pengecekan izin/persiapan yang
    // async) agar pengguna tunanetra merasakan getaran persis saat menekan,
    // bukan sesudah jeda.
    _haptics(HapticKind.listening);
    final e = await _begin();
    if (_micPermanentlyDenied) {
      await _say(e, Msg.openingSettings);
      if (e != _epoch) return;
      _setStatus(VoiceStatus.idle);
      await _openSettings();
      return;
    }
    await _listen(e);
  }

  /// Tekan-tahan: hentikan pembacaan/pemrosesan lalu dengarkan lagi.
  Future<void> onLongPress() => interrupt();

  Future<void> interrupt() async {
    if (!_started || _disposed) return;
    if (_status != VoiceStatus.speaking && _status != VoiceStatus.processing) {
      return;
    }
    final e = await _begin();
    await _listen(e);
  }

  Future<void> onSwipeLeft() async {
    if (_mode == AppMode.basic) await switchMode(AppMode.ai);
  }

  Future<void> onSwipeRight() async {
    if (_mode == AppMode.ai) await switchMode(AppMode.basic);
  }

  Future<void> switchMode(AppMode target) async {
    if (!_started || _disposed || target == _mode) return;
    final now = _clock();
    final last = _lastSwitchAt;
    if (last != null && now.difference(last) < const Duration(milliseconds: 500)) {
      return; // satu gestur = satu perpindahan
    }
    _lastSwitchAt = now;

    final e = await _begin();
    _mode = target;
    _transcript = '';
    _question = '';
    _answer = '';
    notifyListeners();
    if (!await _say(e, target == AppMode.ai ? Msg.nowAi : Msg.nowBasic)) return;
    await _listen(e);
  }

  Future<void> onBackground() async {
    if (!_started || _disposed) return;
    _wasBackgrounded = true;
    await _begin();
    _setStatus(VoiceStatus.idle);
  }

  Future<void> onResume() async {
    if (!_started || _disposed || !_wasBackgrounded) return;
    _wasBackgrounded = false;
    final e = await _begin();
    await _listen(e);
  }

  // ----------------------------------------------------------- alur dalam

  bool _isStale(int epoch, [int? token]) =>
      _disposed || epoch != _epoch || (token != null && token != _listenToken);

  /// Mulai alur baru: batalkan semua pekerjaan lama, lepas mikrofon & TTS.
  Future<int> _begin() async {
    final e = ++_epoch;
    _listenToken++;
    _deadline?.cancel();
    _restartTimer?.cancel();
    _ai.cancel();
    await _safe(_tts.stop());
    await _safe(_stt.cancel());
    return e;
  }

  Future<void> _safe(Future<void> f) async {
    try {
      await f;
    } catch (e) {
      AppLog.d('Controller', 'operasi gagal: ${e.runtimeType}');
    }
  }

  void _setStatus(VoiceStatus s) {
    if (_disposed) return;
    _status = s;
    notifyListeners();
  }

  /// Membacakan [text]. Mengembalikan true bila alur masih berlaku.
  Future<bool> _say(int epoch, String text) async {
    if (_isStale(epoch)) return false;
    _setStatus(VoiceStatus.speaking);
    try {
      await _tts.speak(text);
    } catch (e) {
      AppLog.d('Controller', 'TTS gagal: ${e.runtimeType}');
      _haptics(HapticKind.error);
    }
    return !_isStale(epoch);
  }

  Future<void> _listen(int epoch) async {
    if (_isStale(epoch)) return;
    final readiness = await _stt.ensureReady();
    if (_isStale(epoch)) return;

    switch (readiness) {
      case SttReadiness.ready:
        break;
      case SttReadiness.denied:
        _micPermanentlyDenied = false;
        await _failAndIdle(epoch, Msg.micPermission);
        return;
      case SttReadiness.permanentlyDenied:
        _micPermanentlyDenied = true;
        await _failAndIdle(epoch, Msg.micPermissionForever);
        return;
      case SttReadiness.unavailable:
        await _failAndIdle(epoch, Msg.sttUnavailable);
        return;
    }
    _micPermanentlyDenied = false;

    _transcript = '';
    _lastWords = '';
    _restarts = 0;
    final token = ++_listenToken;
    _deadlineAt = _clock().add(_listenWindow);
    _setStatus(VoiceStatus.listening);
    _deadline?.cancel();
    _deadline = Timer(_listenWindow, () => _onTimeout(epoch, token));
    await _startRecognizer(epoch, token);
  }

  Future<void> _startRecognizer(int epoch, int token) async {
    if (_isStale(epoch, token)) return;
    try {
      await _stt.start(
        listenFor: AppConfig.recognizerListenFor,
        pauseFor: AppConfig.recognizerPauseFor,
        onResult: (words, isFinal) => _onResult(epoch, token, words, isFinal),
        onEnd: (reason) => _onEnd(epoch, token, reason),
      );
    } catch (e) {
      AppLog.d('Controller', 'STT start gagal: ${e.runtimeType}');
      _onEnd(epoch, token, SttEnd.error);
    }
  }

  void _onResult(int epoch, int token, String words, bool isFinal) {
    if (_isStale(epoch, token) || _status != VoiceStatus.listening) return;
    final w = words.trim();
    if (w.isEmpty) return;
    _lastWords = w;
    _transcript = w;
    _deadline?.cancel(); // pengguna sedang bicara: batas menunggu tidak berlaku
    notifyListeners();
    if (isFinal) _finalize(epoch, w);
  }

  void _onEnd(int epoch, int token, SttEnd reason) {
    if (_isStale(epoch, token) || _status != VoiceStatus.listening) return;
    if (_lastWords.isNotEmpty) {
      _finalize(epoch, _lastWords);
      return;
    }
    switch (reason) {
      case SttEnd.permission:
        unawaited(_failAndIdle(epoch, Msg.micPermission));
        return;
      case SttEnd.unavailable:
        unawaited(_failAndIdle(epoch, Msg.sttUnavailable));
        return;
      case SttEnd.network:
        unawaited(_failAndIdle(epoch, Msg.sttNetwork));
        return;
      case SttEnd.done:
      case SttEnd.noMatch:
      case SttEnd.speechTimeout:
      case SttEnd.error:
        break;
    }
    // Pengenal bawaan sering berhenti sendiri dalam beberapa detik. Selama
    // jendela 10 detik belum habis, mulai lagi; jendela dihitung dari awal.
    if (!_clock().isBefore(_deadlineAt) || ++_restarts > 40) {
      _onTimeout(epoch, token);
      return;
    }
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(milliseconds: 300), () {
      unawaited(_startRecognizer(epoch, token));
    });
  }

  void _finalize(int epoch, String words) {
    _listenToken++; // callback STT berikutnya dianggap usang
    _deadline?.cancel();
    _restartTimer?.cancel();
    unawaited(_safe(_stt.cancel())); // lepas mikrofon sebelum memproses
    _transcript = words;
    unawaited(_handle(epoch, words));
  }

  void _onTimeout(int epoch, int token) {
    if (_isStale(epoch, token) || _status != VoiceStatus.listening) return;
    unawaited(_timeoutFlow(epoch));
  }

  Future<void> _timeoutFlow(int epoch) async {
    _listenToken++;
    _restartTimer?.cancel();
    await _safe(_stt.cancel()); // mikrofon dilepas SEBELUM status berubah
    if (_isStale(epoch)) return;
    _setStatus(VoiceStatus.idle);
    _haptics(HapticKind.timeout);
    try {
      await _tts.speak(Msg.timeout); // status tetap idle: sentuhan tetap aktif
    } catch (_) {}
  }

  Future<void> _failAndIdle(int epoch, String message) async {
    _listenToken++;
    _deadline?.cancel();
    _restartTimer?.cancel();
    await _safe(_stt.cancel());
    _haptics(HapticKind.error);
    if (_isStale(epoch)) return;
    await _say(epoch, message);
    if (!_isStale(epoch)) _setStatus(VoiceStatus.idle);
  }

  Future<void> _handle(int epoch, String words) async {
    if (_isStale(epoch)) return;
    _setStatus(VoiceStatus.processing);
    final cmd = _router.parse(words, mode: _mode);

    if (cmd is SwitchModeCommand) {
      if (cmd.target == _mode) {
        await _speakResult(
          epoch,
          cmd.target == AppMode.ai ? Msg.alreadyAi : Msg.alreadyBasic,
        );
      } else {
        _lastSwitchAt = null; // perintah suara tidak terkena debounce gestur
        await switchMode(cmd.target);
      }
      return;
    }

    if (cmd is BasicCommand) {
      String text;
      try {
        text = await _info.answer(cmd.intent);
      } catch (e) {
        AppLog.d('Controller', 'layanan dasar gagal: ${e.runtimeType}');
        text = Msg.genericError;
      }
      await _speakResult(epoch, text);
      return;
    }

    if (cmd is AiQuestionCommand) {
      _question = cmd.question;
      notifyListeners();
      String raw;
      try {
        raw = await _ai.ask(cmd.question);
      } on AiException catch (e) {
        if (e.failure == AiFailure.cancelled || _isStale(epoch)) return;
        await _speakResult(epoch, _aiMessage(e.failure));
        return;
      } catch (_) {
        if (_isStale(epoch)) return;
        await _speakResult(epoch, Msg.aiServer);
        return;
      }
      if (_isStale(epoch)) return; // respons lama tidak boleh dibacakan
      final speech = SpeechText.forSpeech(raw);
      if (speech.isEmpty) {
        await _speakResult(epoch, Msg.aiEmpty);
        return;
      }
      await _speakResult(epoch, SpeechText.forDisplay(raw), speech: speech);
      return;
    }

    await _speakResult(epoch, Msg.unknownCommand);
  }

  String _aiMessage(AiFailure f) {
    switch (f) {
      case AiFailure.notConfigured:
        return Msg.aiNotConfigured;
      case AiFailure.offline:
        return Msg.offline;
      case AiFailure.timeout:
        return Msg.aiTimeout;
      case AiFailure.rateLimited:
        return Msg.aiRateLimited;
      case AiFailure.empty:
        return Msg.aiEmpty;
      case AiFailure.server:
      case AiFailure.cancelled:
        return Msg.aiServer;
    }
  }

  /// Tampilkan + bacakan hasil, lalu kembali mendengarkan.
  Future<void> _speakResult(int epoch, String display, {String? speech}) async {
    if (_isStale(epoch)) return;
    _answer = display;
    if (!await _say(epoch, speech ?? display)) return;
    await _listen(epoch);
  }

  @override
  void dispose() {
    _disposed = true;
    _deadline?.cancel();
    _restartTimer?.cancel();
    _ai.cancel();
    unawaited(_safe(_tts.stop()));
    unawaited(_safe(_stt.cancel()));
    super.dispose();
  }
}
