import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import '../core/app_config.dart';

enum WeatherFailure { offline, server }

class WeatherException implements Exception {
  const WeatherException(this.failure);
  final WeatherFailure failure;
}

class WeatherReading {
  const WeatherReading({
    required this.code,
    required this.temperature,
    required this.apparentTemperature,
    required this.humidity,
    required this.precipitation,
  });
  final int code;
  final double temperature;
  final double? apparentTemperature;
  final int? humidity;
  final double precipitation;

  /// Deskripsi dari kode cuaca WMO (dipakai Open-Meteo).
  String get description => describeCode(code);

  bool get isRaining =>
      (code >= 51 && code <= 67) ||
      (code >= 80 && code <= 82) ||
      code >= 95 ||
      precipitation > 0;

  static String describeCode(int c) {
    if (c == 0) return 'cerah';
    if (c == 1) return 'sebagian besar cerah';
    if (c == 2) return 'berawan sebagian';
    if (c == 3) return 'mendung';
    if (c == 45 || c == 48) return 'berkabut';
    if (c >= 51 && c <= 55) return 'gerimis';
    if (c == 56 || c == 57) return 'gerimis dingin';
    if (c == 61) return 'hujan ringan';
    if (c == 63) return 'hujan sedang';
    if (c == 65) return 'hujan lebat';
    if (c == 66 || c == 67) return 'hujan dingin';
    if (c >= 71 && c <= 77) return 'bersalju';
    if (c == 80) return 'hujan lokal ringan';
    if (c == 81) return 'hujan lokal sedang';
    if (c == 82) return 'hujan lokal deras';
    if (c == 85 || c == 86) return 'hujan salju';
    if (c == 95) return 'badai petir';
    if (c == 96 || c == 99) return 'badai petir disertai hujan es';
    return 'tidak diketahui';
  }
}

abstract class WeatherProvider {
  Future<WeatherReading> fetch(double lat, double lon);
}

/// Open-Meteo: tanpa API key, HTTPS, cakupan global (termasuk Indonesia).
/// Lapisan ini ada di balik antarmuka sehingga dapat diganti BMKG kelak.
class OpenMeteoService implements WeatherProvider {
  OpenMeteoService({http.Client Function()? clientFactory})
      : _factory = clientFactory ?? http.Client.new;
  final http.Client Function() _factory;

  @override
  Future<WeatherReading> fetch(double lat, double lon) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': lat.toStringAsFixed(4),
      'longitude': lon.toStringAsFixed(4),
      'current':
          'temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,weather_code',
      'timezone': 'auto',
    });
    final client = _factory();
    try {
      final res = await client.get(uri).timeout(AppConfig.httpTimeout);
      if (res.statusCode != 200) {
        throw const WeatherException(WeatherFailure.server);
      }
      final json = jsonDecode(utf8.decode(res.bodyBytes));
      final cur = (json as Map<String, dynamic>)['current'] as Map<String, dynamic>;
      return WeatherReading(
        code: (cur['weather_code'] as num).toInt(),
        temperature: (cur['temperature_2m'] as num).toDouble(),
        apparentTemperature: (cur['apparent_temperature'] as num?)?.toDouble(),
        humidity: (cur['relative_humidity_2m'] as num?)?.toInt(),
        precipitation: (cur['precipitation'] as num?)?.toDouble() ?? 0,
      );
    } on WeatherException {
      rethrow;
    } on TimeoutException {
      throw const WeatherException(WeatherFailure.offline);
    } on SocketException {
      throw const WeatherException(WeatherFailure.offline);
    } on http.ClientException {
      throw const WeatherException(WeatherFailure.offline);
    } catch (_) {
      throw const WeatherException(WeatherFailure.server);
    } finally {
      client.close();
    }
  }
}
