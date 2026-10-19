import 'dart:async';

import 'package:lentera3/command/command_router.dart';
import 'package:lentera3/services/ai_service.dart';
import 'package:lentera3/services/basic_info_service.dart';
import 'package:lentera3/state/lentera_controller.dart';
import 'package:lentera3/voice/speech_ports.dart';

class FakeTts implements SpeechOutput {
  FakeTts(this.log);
  final List<String> log;
  final spoken = <String>[];

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
    log.add('tts:$text');
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Future<void> stop() async => log.add('tts.stop');
}

class FakeStt implements SpeechInput {
  FakeStt(this.log);
  final List<String> log;
  SttReadiness readiness = SttReadiness.ready;
  int startCount = 0;
  int cancelCount = 0;
  void Function(String, bool)? _onResult;
  void Function(SttEnd)? _onEnd;

  @override
  Future<SttReadiness> ensureReady() async => readiness;

  @override
  Future<void> start({
    required void Function(String words, bool isFinal) onResult,
    required void Function(SttEnd reason) onEnd,
    required Duration listenFor,
    required Duration pauseFor,
  }) async {
    startCount++;
    log.add('stt.start');
    _onResult = onResult;
    _onEnd = onEnd;
  }

  @override
  Future<void> cancel() async {
    cancelCount++;
    log.add('stt.cancel');
    _onResult = null;
    _onEnd = null;
  }

  void say(String words, {bool isFinal = true}) =>
      _onResult?.call(words, isFinal);
  void end(SttEnd reason) => _onEnd?.call(reason);
}

class FakeInfo implements InfoAnswerer {
  final calls = <BasicIntent>[];
  @override
  Future<String> answer(BasicIntent intent) async {
    calls.add(intent);
    return 'jawaban:${intent.name}';
  }
}

class FakeAi implements AiService {
  final asked = <String>[];
  Completer<String>? pending;
  String reply = 'Jawaban dari AI.';
  AiFailure? failWith;
  int cancelCount = 0;

  @override
  Future<String> ask(String question) {
    asked.add(question);
    if (failWith != null) return Future.error(AiException(failWith!));
    final p = pending;
    return p != null ? p.future : Future.value(reply);
  }

  @override
  void cancel() => cancelCount++;
}

class Harness {
  Harness({Duration window = const Duration(milliseconds: 150)}) {
    tts = FakeTts(log);
    stt = FakeStt(log);
    controller = LenteraController(
      tts: tts,
      stt: stt,
      info: info,
      ai: ai,
      clock: () => now,
      listenWindow: window,
      haptics: (_) {},
      openSettings: () async => settingsOpened++,
    );
  }

  final log = <String>[];
  late final FakeTts tts;
  late final FakeStt stt;
  final info = FakeInfo();
  final ai = FakeAi();
  late final LenteraController controller;
  DateTime now = DateTime.utc(2026, 10, 14, 10);
  int settingsOpened = 0;

  void advance(Duration d) => now = now.add(d);
}

/// Memberi kesempatan semua rantai async (microtask/event) selesai.
Future<void> settle() async {
  for (var i = 0; i < 25; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
