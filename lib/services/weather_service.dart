import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import '../core/app_log.dart';

// ──────────────────────────────────────────────────────────────────────────────
//  ENUM & EXCEPTION
// ──────────────────────────────────────────────────────────────────────────────

enum WeatherFailure {
  offline,
  server,
  timeout,
  invalidData,
}

class WeatherException implements Exception {
  const WeatherException(this.failure, [this.message]);
  final WeatherFailure failure;
  final String? message;

  @override
  String toString() =>
      'WeatherException(${failure.name}${message != null ? ': $message' : ''})';
}

// ──────────────────────────────────────────────────────────────────────────────
//  DATA MODEL
// ──────────────────────────────────────────────────────────────────────────────

class WeatherReading {
  const WeatherReading({
    required this.code,
    required this.temperature,
    this.apparentTemperature,
    this.humidity,
    this.windSpeed,
    required this.precipitation,
    required this.timestamp,
    this.isFromCache = false,
  });

  /// Kode cuaca WMO (dipakai Open-Meteo).
  final int code;

  /// Suhu saat ini dalam °C.
  final double temperature;

  /// Suhu terasa (feels like) dalam °C.
  final double? apparentTemperature;

  /// Kelembapan relatif dalam persen.
  final int? humidity;

  /// Kecepatan angin dalam km/h.
  final double? windSpeed;

  /// Presipitasi (curah hujan) dalam mm.
  final double precipitation;

  /// Kapan data ini diperoleh.
  final DateTime timestamp;

  /// Apakah data ini dari cache.
  final bool isFromCache;

  /// Deskripsi cuaca dalam Bahasa Indonesia.
  String get description => describeCode(code);

  /// Nama ikon cuaca (bisa dipakai untuk ikon Material atau mapping custom).
  String get iconName => _iconForCode(code);

  /// Prakiraan singkat satu kalimat.
  String get shortForecast {
    final temp = temperature.round();
    final desc = description;
    final feelsLike = apparentTemperature?.round();

    final buf = StringBuffer('$desc, suhu $temp°C');
    if (feelsLike != null && (feelsLike - temp).abs() >= 2) {
      buf.write(' (terasa $feelsLike°C)');
    }
    return buf.toString();
  }

  bool get isRaining =>
      (code >= 51 && code <= 67) ||
      (code >= 80 && code <= 82) ||
      code >= 95 ||
      precipitation > 0;

  // ── Serialization (untuk cache) ──

  Map<String, dynamic> toJson() => {
        'code': code,
        'temperature': temperature,
        'apparentTemperature': apparentTemperature,
        'humidity': humidity,
        'windSpeed': windSpeed,
        'precipitation': precipitation,
        'ts': timestamp.millisecondsSinceEpoch,
      };

  factory WeatherReading.fromJson(Map<String, dynamic> json,
          {bool cached = false}) =>
      WeatherReading(
        code: (json['code'] as num).toInt(),
        temperature: (json['temperature'] as num).toDouble(),
        apparentTemperature:
            (json['apparentTemperature'] as num?)?.toDouble(),
        humidity: (json['humidity'] as num?)?.toInt(),
        windSpeed: (json['windSpeed'] as num?)?.toDouble(),
        precipitation: (json['precipitation'] as num?)?.toDouble() ?? 0,
        timestamp:
            DateTime.fromMillisecondsSinceEpoch((json['ts'] as num).toInt()),
        isFromCache: cached,
      );

  // ── Deskripsi kode WMO ──

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

  /// Mapping kode WMO ke nama ikon.
  static String _iconForCode(int c) {
    if (c == 0) return 'sunny';
    if (c == 1) return 'mostly_sunny';
    if (c == 2) return 'partly_cloudy';
    if (c == 3) return 'cloudy';
    if (c == 45 || c == 48) return 'foggy';
    if (c >= 51 && c <= 57) return 'drizzle';
    if (c >= 61 && c <= 67) return 'rainy';
    if (c >= 71 && c <= 77) return 'snowy';
    if (c >= 80 && c <= 82) return 'showers';
    if (c == 85 || c == 86) return 'snow_showers';
    if (c >= 95) return 'thunderstorm';
    return 'unknown';
  }
}

// ──────────────────────────────────────────────────────────────────────────────
//  ABSTRACT INTERFACE
// ──────────────────────────────────────────────────────────────────────────────

abstract class WeatherProvider {
  /// Ambil data cuaca berdasarkan koordinat (lat, lon).
  /// TIDAK pernah menggunakan nama kota.
  Future<WeatherReading> fetch(double lat, double lon);
}

// ──────────────────────────────────────────────────────────────────────────────
//  IMPLEMENTATION: Open-Meteo (gratis, tanpa API key, cakupan global)
// ──────────────────────────────────────────────────────────────────────────────

class OpenMeteoService implements WeatherProvider {
  OpenMeteoService({
    http.Client Function()? clientFactory,
    int maxRetries = 2,
    Duration retryDelay = const Duration(seconds: 2),
    Duration requestTimeout = const Duration(seconds: 10),
  })  : _factory = clientFactory ?? http.Client.new,
        _maxRetries = maxRetries,
        _retryDelay = retryDelay,
        _requestTimeout = requestTimeout;

  final http.Client Function() _factory;
  final int _maxRetries;
  final Duration _retryDelay;
  final Duration _requestTimeout;

  // ── Cache in-memory ──
  WeatherReading? _cache;
  double? _cacheLat;
  double? _cacheLon;

  /// Akses cache cuaca terakhir.
  WeatherReading? get lastReading => _cache;

  @override
  Future<WeatherReading> fetch(double lat, double lon) async {
    // Jika cache masih segar (< 5 menit) dan koordinat mirip → gunakan cache
    if (_cache != null &&
        !_cache!.isFromCache &&
        DateTime.now().difference(_cache!.timestamp) <
            const Duration(minutes: 5) &&
        _isSameArea(lat, lon)) {
      AppLog.d('Weather', 'Mengembalikan cache (masih segar)');
      return _cache!;
    }

    // Coba fetch online dengan retry
    WeatherException? lastError;
    for (var attempt = 0; attempt <= _maxRetries; attempt++) {
      if (attempt > 0) {
        AppLog.d('Weather', 'Retry ke-$attempt...');
        await Future<void>.delayed(_retryDelay);
      }

      try {
        final reading = await _fetchOnline(lat, lon);
        _cache = reading;
        _cacheLat = lat;
        _cacheLon = lon;
        return reading;
      } on WeatherException catch (e) {
        lastError = e;
        // Jika offline, tidak perlu retry lagi
        if (e.failure == WeatherFailure.offline) break;
        // Jika server error, retry
        AppLog.d('Weather', 'Attempt $attempt gagal: ${e.failure.name}');
      }
    }

    // Semua retry gagal → kembalikan cache jika tersedia
    if (_cache != null) {
      AppLog.d('Weather', 'Semua retry gagal, mengembalikan cache');
      return WeatherReading(
        code: _cache!.code,
        temperature: _cache!.temperature,
        apparentTemperature: _cache!.apparentTemperature,
        humidity: _cache!.humidity,
        windSpeed: _cache!.windSpeed,
        precipitation: _cache!.precipitation,
        timestamp: _cache!.timestamp,
        isFromCache: true,
      );
    }

    throw lastError ??
        const WeatherException(
          WeatherFailure.offline,
          'Tidak dapat mengambil data cuaca.',
        );
  }

  /// Fetch data cuaca dari Open-Meteo API.
  Future<WeatherReading> _fetchOnline(double lat, double lon) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': lat.toStringAsFixed(4),
      'longitude': lon.toStringAsFixed(4),
      'current': [
        'temperature_2m',
        'apparent_temperature',
        'relative_humidity_2m',
        'precipitation',
        'weather_code',
        'wind_speed_10m',
      ].join(','),
      'timezone': 'auto',
    });

    final client = _factory();
    try {
      final response =
          await client.get(uri).timeout(_requestTimeout);

      if (response.statusCode != 200) {
        AppLog.d('Weather', 'HTTP ${response.statusCode}');
        throw WeatherException(
          WeatherFailure.server,
          'Server merespons dengan kode ${response.statusCode}.',
        );
      }

      final json =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final current = json['current'] as Map<String, dynamic>?;

      if (current == null) {
        throw const WeatherException(
          WeatherFailure.invalidData,
          'Data cuaca tidak valid.',
        );
      }

      return WeatherReading(
        code: (current['weather_code'] as num).toInt(),
        temperature: (current['temperature_2m'] as num).toDouble(),
        apparentTemperature:
            (current['apparent_temperature'] as num?)?.toDouble(),
        humidity: (current['relative_humidity_2m'] as num?)?.toInt(),
        windSpeed: (current['wind_speed_10m'] as num?)?.toDouble(),
        precipitation: (current['precipitation'] as num?)?.toDouble() ?? 0,
        timestamp: DateTime.now(),
      );
    } on WeatherException {
      rethrow;
    } on TimeoutException {
      throw const WeatherException(
        WeatherFailure.timeout,
        'Waktu habis saat mengambil data cuaca.',
      );
    } on SocketException {
      throw const WeatherException(
        WeatherFailure.offline,
        'Tidak ada koneksi internet.',
      );
    } on http.ClientException {
      throw const WeatherException(
        WeatherFailure.offline,
        'Koneksi ke server cuaca gagal.',
      );
    } on FormatException {
      throw const WeatherException(
        WeatherFailure.invalidData,
        'Format data cuaca tidak dapat diproses.',
      );
    } catch (e) {
      AppLog.d('Weather', 'Unexpected error: ${e.runtimeType}');
      throw const WeatherException(
        WeatherFailure.server,
        'Terjadi kesalahan tak terduga.',
      );
    } finally {
      client.close();
    }
  }

  /// Cek apakah koordinat masih di area yang sama (< 1km).
  bool _isSameArea(double lat, double lon) {
    if (_cacheLat == null || _cacheLon == null) return false;
    // Perkiraan cepat tanpa trigonometri (cukup akurat untuk ~1km)
    final dLat = (lat - _cacheLat!).abs();
    final dLon = (lon - _cacheLon!).abs();
    return dLat < 0.01 && dLon < 0.01; // ~1km
  }
}
