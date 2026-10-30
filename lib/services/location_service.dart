import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../core/app_log.dart';

// ──────────────────────────────────────────────────────────────────────────────
//  ENUM & EXCEPTION
// ──────────────────────────────────────────────────────────────────────────────

enum LocationFailure {
  denied,
  deniedForever,
  serviceOff,
  timeout,
  networkError,
  failed,
}

class LocationException implements Exception {
  const LocationException(this.failure, [this.message]);
  final LocationFailure failure;
  final String? message;

  @override
  String toString() =>
      'LocationException(${failure.name}${message != null ? ': $message' : ''})';
}

// ──────────────────────────────────────────────────────────────────────────────
//  DATA MODELS
// ──────────────────────────────────────────────────────────────────────────────

/// Koordinat GPS mentah beserta metadata akurasi.
class LocationFix {
  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.timestamp,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime timestamp;

  /// Apakah fix ini sudah terlalu tua (> 10 menit).
  bool get isStale =>
      DateTime.now().difference(timestamp) > const Duration(minutes: 10);

  Map<String, dynamic> toJson() => {
        'lat': latitude,
        'lon': longitude,
        'acc': accuracyMeters,
        'ts': timestamp.millisecondsSinceEpoch,
      };

  factory LocationFix.fromJson(Map<String, dynamic> json) => LocationFix(
        latitude: (json['lat'] as num).toDouble(),
        longitude: (json['lon'] as num).toDouble(),
        accuracyMeters: (json['acc'] as num).toDouble(),
        timestamp:
            DateTime.fromMillisecondsSinceEpoch((json['ts'] as num).toInt()),
      );
}

/// Informasi tempat hasil reverse geocoding.
class PlaceInfo {
  const PlaceInfo({
    this.building,
    this.road,
    this.subDistrict,
    this.city,
    this.province,
    this.country,
    this.displayName,
    required this.timestamp,
  });

  /// Nama gedung / kompleks (bila tersedia).
  final String? building;

  /// Nama jalan.
  final String? road;

  /// Kecamatan / kelurahan / desa.
  final String? subDistrict;

  /// Kota / kabupaten.
  final String? city;

  /// Provinsi.
  final String? province;

  /// Negara.
  final String? country;

  /// Alamat lengkap dari API.
  final String? displayName;

  /// Kapan data ini diperoleh.
  final DateTime timestamp;

  /// Format ringkas siap-baca untuk TTS.
  String toSpokenString() {
    final parts = <String>[];
    if (building != null && building!.isNotEmpty) parts.add(building!);
    if (road != null && road!.isNotEmpty) parts.add(road!);
    if (subDistrict != null && subDistrict!.isNotEmpty) parts.add(subDistrict!);
    if (city != null && city!.isNotEmpty) parts.add(city!);
    if (province != null && province!.isNotEmpty) parts.add(province!);
    if (country != null && country!.isNotEmpty) parts.add(country!);
    return parts.isEmpty ? 'Lokasi tidak diketahui' : parts.join(', ');
  }

  /// Nama singkat (kecamatan/kota) untuk label cuaca.
  String get shortName {
    if (subDistrict != null && subDistrict!.isNotEmpty) return subDistrict!;
    if (city != null && city!.isNotEmpty) return city!;
    if (province != null && province!.isNotEmpty) return province!;
    return 'lokasi Anda';
  }

  Map<String, dynamic> toJson() => {
        'building': building,
        'road': road,
        'subDistrict': subDistrict,
        'city': city,
        'province': province,
        'country': country,
        'displayName': displayName,
        'ts': timestamp.millisecondsSinceEpoch,
      };

  factory PlaceInfo.fromJson(Map<String, dynamic> json) => PlaceInfo(
        building: json['building'] as String?,
        road: json['road'] as String?,
        subDistrict: json['subDistrict'] as String?,
        city: json['city'] as String?,
        province: json['province'] as String?,
        country: json['country'] as String?,
        displayName: json['displayName'] as String?,
        timestamp:
            DateTime.fromMillisecondsSinceEpoch((json['ts'] as num).toInt()),
      );
}

/// Hasil lengkap lokasi (koordinat + informasi tempat).
class LocationResult {
  const LocationResult({
    required this.fix,
    this.place,
    this.isFromCache = false,
  });

  final LocationFix fix;
  final PlaceInfo? place;
  final bool isFromCache;
}

// ──────────────────────────────────────────────────────────────────────────────
//  ABSTRACT INTERFACE (agar bisa di-mock di test)
// ──────────────────────────────────────────────────────────────────────────────

abstract class LocationProvider {
  /// Ambil koordinat GPS terkini.
  Future<LocationFix> currentFix();

  /// Reverse geocoding dari koordinat → nama tempat.
  Future<PlaceInfo?> placeName(LocationFix fix);
}

// ──────────────────────────────────────────────────────────────────────────────
//  IMPLEMENTATION
// ──────────────────────────────────────────────────────────────────────────────

class DeviceLocationService implements LocationProvider {
  DeviceLocationService({
    http.Client Function()? httpFactory,
    Duration gpsTimeout = const Duration(seconds: 15),
    Duration geocodeTimeout = const Duration(seconds: 8),
  })  : _httpFactory = httpFactory ?? http.Client.new,
        _gpsTimeout = gpsTimeout,
        _geocodeTimeout = geocodeTimeout;

  final http.Client Function() _httpFactory;
  final Duration _gpsTimeout;
  final Duration _geocodeTimeout;

  // ── Cache in-memory ──
  LocationFix? _cachedFix;
  PlaceInfo? _cachedPlace;

  /// Akses cache lokasi terakhir tanpa request baru (berguna saat offline).
  LocationFix? get lastKnownFix => _cachedFix;
  PlaceInfo? get lastKnownPlace => _cachedPlace;

  // ────────────────────────────────────────────────────────────────────────────
  //  GPS FIX
  // ────────────────────────────────────────────────────────────────────────────

  @override
  Future<LocationFix> currentFix() async {
    // 1. Cek & request permission
    await _ensurePermission();

    // 2. Cek apakah GPS aktif
    if (!await Geolocator.isLocationServiceEnabled()) {
      // Kembalikan cache jika ada, kalau tidak throw
      if (_cachedFix != null) {
        AppLog.d('Location', 'GPS mati, mengembalikan cache');
        return _cachedFix!;
      }
      throw const LocationException(
        LocationFailure.serviceOff,
        'Layanan lokasi perangkat sedang mati.',
      );
    }

    // 3. Ambil posisi dengan timeout
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
          timeLimit: Duration(seconds: 15),
        ),
      ).timeout(_gpsTimeout);

      final fix = LocationFix(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        timestamp: DateTime.now(),
      );

      _cachedFix = fix;
      AppLog.d(
          'Location', 'GPS fix didapat, akurasi ± ${fix.accuracyMeters.round()}m');
      return fix;
    } on TimeoutException {
      // Timeout → coba ambil posisi terakhir yang diketahui platform
      return _fallbackToLastKnown(
        const LocationException(
          LocationFailure.timeout,
          'Waktu habis saat mencari lokasi GPS.',
        ),
      );
    } on LocationServiceDisabledException {
      return _fallbackToLastKnown(
        const LocationException(
          LocationFailure.serviceOff,
          'Layanan lokasi perangkat mati.',
        ),
      );
    } on PermissionDeniedException {
      throw const LocationException(
        LocationFailure.denied,
        'Izin lokasi ditolak.',
      );
    } catch (e) {
      AppLog.d('Location', 'GPS error: ${e.runtimeType} – $e');
      return _fallbackToLastKnown(
        const LocationException(
          LocationFailure.failed,
          'Tidak dapat menentukan lokasi saat ini.',
        ),
      );
    }
  }

  /// Jika GPS gagal, coba cache atau last-known dari platform.
  Future<LocationFix> _fallbackToLastKnown(LocationException fallback) async {
    if (_cachedFix != null) {
      AppLog.d('Location', 'Fallback ke cache fix');
      return _cachedFix!;
    }

    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        final fix = LocationFix(
          latitude: last.latitude,
          longitude: last.longitude,
          accuracyMeters: last.accuracy,
          timestamp: DateTime.now(),
        );
        _cachedFix = fix;
        AppLog.d('Location', 'Fallback ke last-known platform');
        return fix;
      }
    } catch (e) {
      AppLog.d('Location', 'getLastKnownPosition gagal: ${e.runtimeType}');
    }

    throw fallback;
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  PERMISSION HANDLING
  // ────────────────────────────────────────────────────────────────────────────

  Future<void> _ensurePermission() async {
    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
        LocationFailure.deniedForever,
        'Izin lokasi ditolak secara permanen. Buka Pengaturan untuk mengaktifkan.',
      );
    }

    if (permission == LocationPermission.denied) {
      throw const LocationException(
        LocationFailure.denied,
        'Izin lokasi diperlukan agar fitur ini berfungsi.',
      );
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  REVERSE GEOCODING (Nominatim – gratis, akurat, tanpa API key)
  // ────────────────────────────────────────────────────────────────────────────

  @override
  Future<PlaceInfo?> placeName(LocationFix fix) async {
    // Jika koordinat belum bergeser jauh dan cache masih segar → gunakan cache
    if (_cachedPlace != null &&
        _cachedFix != null &&
        _isNearby(fix, _cachedFix!) &&
        !_cachedPlace!.timestamp
            .isBefore(DateTime.now().subtract(const Duration(minutes: 5)))) {
      return _cachedPlace;
    }

    // Coba reverse geocoding online
    try {
      final place = await _reverseGeocodeOnline(fix);
      if (place != null) {
        _cachedPlace = place;
        return place;
      }
    } on SocketException {
      AppLog.d('Location', 'Reverse geocode gagal: tidak ada internet');
    } on TimeoutException {
      AppLog.d('Location', 'Reverse geocode gagal: timeout');
    } on http.ClientException catch (e) {
      AppLog.d('Location', 'Reverse geocode gagal: ${e.message}');
    } catch (e) {
      AppLog.d('Location', 'Reverse geocode gagal: ${e.runtimeType}');
    }

    // Offline → kembalikan cache jika ada
    if (_cachedPlace != null) {
      AppLog.d('Location', 'Reverse geocode offline → cache');
      return _cachedPlace;
    }

    return null;
  }

  /// Reverse geocoding via OpenStreetMap Nominatim.
  /// Nominatim mengembalikan detail yang sangat lengkap termasuk nama gedung,
  /// jalan, kecamatan, kota, provinsi, dan negara – cocok untuk Indonesia.
  Future<PlaceInfo?> _reverseGeocodeOnline(LocationFix fix) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'lat': fix.latitude.toStringAsFixed(6),
      'lon': fix.longitude.toStringAsFixed(6),
      'format': 'json',
      'addressdetails': '1',
      'accept-language': 'id',
      'zoom': '18',
    });

    final client = _httpFactory();
    try {
      final response = await client
          .get(uri, headers: {
            'User-Agent': 'LenteraApp/1.0 (accessibility-app)',
          })
          .timeout(_geocodeTimeout);

      if (response.statusCode != 200) {
        AppLog.d('Location',
            'Nominatim HTTP ${response.statusCode}');
        return null;
      }

      final json =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final address = json['address'] as Map<String, dynamic>?;
      if (address == null) return null;

      // Nominatim structure untuk Indonesia:
      //   building, road, neighbourhood, village/suburb,
      //   city_district (kecamatan), city/town/county,
      //   state (provinsi), country
      final place = PlaceInfo(
        building: _pick(address, ['building', 'amenity', 'shop']),
        road: _pick(address, ['road', 'pedestrian', 'footway']),
        subDistrict: _pick(address, [
          'city_district',
          'suburb',
          'neighbourhood',
          'village',
          'hamlet',
        ]),
        city: _pick(address, [
          'city',
          'town',
          'municipality',
          'county',
          'regency',
        ]),
        province: _pick(address, ['state', 'state_district']),
        country: address['country'] as String?,
        displayName: json['display_name'] as String?,
        timestamp: DateTime.now(),
      );

      AppLog.d('Location', 'Reverse geocode berhasil');
      return place;
    } finally {
      client.close();
    }
  }

  /// Ambil value pertama yang tidak kosong dari daftar key kandidat.
  static String? _pick(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final val = map[key];
      if (val is String && val.trim().isNotEmpty) return val.trim();
    }
    return null;
  }

  /// Dua koordinat dianggap "nearby" jika jaraknya < 200m.
  bool _isNearby(LocationFix a, LocationFix b) {
    final distance = Geolocator.distanceBetween(
        a.latitude, a.longitude, b.latitude, b.longitude);
    return distance < 200;
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  FULL LOCATION RESULT (convenience method)
  // ────────────────────────────────────────────────────────────────────────────

  /// Ambil koordinat + nama tempat sekaligus. Cocok untuk dipanggil dari
  /// BasicInfoService.
  Future<LocationResult> getFullLocation() async {
    final fix = await currentFix();

    PlaceInfo? place;
    try {
      place = await placeName(fix);
    } catch (_) {
      // Jika reverse geocoding gagal, lokasi tetap valid tanpa nama
    }

    return LocationResult(
      fix: fix,
      place: place,
      isFromCache: identical(fix, _cachedFix) && fix.isStale,
    );
  }
}
