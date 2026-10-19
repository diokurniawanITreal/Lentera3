import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../core/app_config.dart';
import '../core/app_log.dart';
import 'speech_ports.dart';

class SttService implements SpeechInput {
  final SpeechToText _stt = SpeechToText();
  bool _initialized = false;
  String? _localeId;

  void Function(String, bool)? _onResult;
  void Function(SttEnd)? _onEnd;

  @override
  Future<SttReadiness> ensureReady() async {
    if (!_initialized) {
      // initialize() meminta izin mikrofon (dan pengenalan suara di iOS).
      _initialized = await _stt.initialize(
        onStatus: _handleStatus,
        onError: _handleError,
      );
      if (_initialized) _localeId = await _pickIndonesianLocale();
    }
    if (_initialized) return SttReadiness.ready;

    if (!await _stt.hasPermission) {
      try {
        if (await Permission.microphone.isPermanentlyDenied) {
          return SttReadiness.permanentlyDenied;
        }
      } catch (_) {}
      return SttReadiness.denied;
    }
    return SttReadiness.unavailable;
  }

  Future<String?> _pickIndonesianLocale() async {
    try {
      final locales = await _stt.locales();
      for (final l in locales) {
        final id = l.localeId.toLowerCase().replaceAll('-', '_');
        if (id == 'id_id') return l.localeId;
      }
      for (final l in locales) {
        if (l.localeId.toLowerCase().startsWith(AppConfig.sttLocalePrefix)) {
          return l.localeId;
        }
      }
    } catch (_) {}
    AppLog.d('STT', 'locale Indonesia tidak ditemukan');
    return null;
  }

  @override
  Future<void> start({
    required void Function(String words, bool isFinal) onResult,
    required void Function(SttEnd reason) onEnd,
    required Duration listenFor,
    required Duration pauseFor,
  }) async {
    _onResult = onResult;
    _onEnd = onEnd;
    await _stt.listen(
      onResult: (r) => _onResult?.call(r.recognizedWords, r.finalResult),
      localeId: _localeId,
      listenFor: listenFor,
      pauseFor: pauseFor,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
      ),
    );
  }

  void _fire(SttEnd reason) {
    final cb = _onEnd;
    _onEnd = null; // paling banyak sekali per sesi
    cb?.call(reason);
  }

  void _handleStatus(String status) {
    // 'done' dikirim setelah hasil akhir/kesalahan.
    if (status == SpeechToText.doneStatus) _fire(SttEnd.done);
  }

  void _handleError(SpeechRecognitionError e) {
    switch (e.errorMsg) {
      case 'error_no_match':
        _fire(SttEnd.noMatch);
      case 'error_speech_timeout':
        _fire(SttEnd.speechTimeout);
      case 'error_permission':
        _fire(SttEnd.permission);
      case 'error_network':
      case 'error_network_timeout':
      case 'error_server':
      case 'error_server_disconnected':
        _fire(SttEnd.network);
      case 'error_language_not_supported':
      case 'error_language_unavailable':
        _fire(SttEnd.unavailable);
      default:
        _fire(SttEnd.error);
    }
  }

  @override
  Future<void> cancel() async {
    _onEnd = null;
    _onResult = null;
    try {
      await _stt.cancel();
    } catch (_) {}
  }
}
