import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_tts/flutter_tts.dart';

import '../core/app_config.dart';
import '../core/app_log.dart';
import '../core/speech_text.dart';
import 'speech_ports.dart';

class TtsService implements SpeechOutput {
  final FlutterTts _tts = FlutterTts();
  Completer<void>? _chunkDone;
  bool _ready = false;
  int _generation = 0;

  Future<void> _init() async {
    if (_ready) return;
    _tts.setCompletionHandler(_finishChunk);
    _tts.setCancelHandler(_finishChunk);
    _tts.setErrorHandler((message) {
      AppLog.d('TTS', 'error');
      _finishChunk();
    });

    try {
      final available = await _tts.isLanguageAvailable(AppConfig.ttsLanguage);
      if (available == false) {
        AppLog.d('TTS', 'bahasa Indonesia tidak tersedia, memakai bawaan');
      } else {
        await _tts.setLanguage(AppConfig.ttsLanguage);
      }
      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      if (Platform.isIOS) {
        await _tts.setSharedInstance(true);
        // TTS dan STT bergantian pada sesi audio yang sama.
        await _tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playAndRecord,
          [
            IosTextToSpeechAudioCategoryOptions.allowBluetooth,
            IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
            IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          ],
          IosTextToSpeechAudioMode.defaultMode,
        );
      }
    } catch (e) {
      AppLog.d('TTS', 'init sebagian gagal: ${e.runtimeType}');
    }
    _ready = true;
  }

  void _finishChunk() {
    final c = _chunkDone;
    if (c != null && !c.isCompleted) c.complete();
  }

  @override
  Future<void> speak(String text) async {
    await _init();
    final generation = ++_generation;
    // Hentikan pembacaan sebelumnya agar tidak ada dua suara bersamaan.
    _finishChunk();
    await _tts.stop();

    for (final chunk in SpeechText.split(text)) {
      if (generation != _generation) return;
      final done = Completer<void>();
      _chunkDone = done;
      final result = await _tts.speak(chunk);
      if (result != 1) {
        AppLog.d('TTS', 'speak ditolak engine');
        throw StateError('TTS gagal memulai');
      }
      await done.future.timeout(
        Duration(seconds: 20 + chunk.length ~/ 6),
        onTimeout: () {},
      );
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    _finishChunk();
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
