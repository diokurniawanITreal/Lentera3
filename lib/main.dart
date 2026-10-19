import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'services/ai_service.dart';
import 'services/basic_info_service.dart';
import 'services/location_service.dart';
import 'services/weather_service.dart';
import 'state/lentera_controller.dart';
import 'voice/stt_service.dart';
import 'voice/tts_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final controller = LenteraController(
    tts: TtsService(),
    stt: SttService(),
    info: BasicInfoService(
      location: DeviceLocationService(),
      weather: OpenMeteoService(),
    ),
    ai: GeminiProxyService(),
  );

  runApp(LenteraApp(controller: controller));
}
