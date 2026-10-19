import 'dart:async';

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../core/app_log.dart';

enum LocationFailure { denied, deniedForever, serviceOff, failed }

class LocationException implements Exception {
  const LocationException(this.failure);
  final LocationFailure failure;
}

class LocationFix {
  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
  });
  final double latitude;
  final double longitude;
  final double accuracyMeters;
}

abstract class LocationProvider {
  Future<LocationFix> currentFix();

  /// Nama tempat dalam bahasa manusia (kelurahan, kecamatan, kota, provinsi),
  /// atau null bila tidak dapat ditentukan.
  Future<String?> placeName(LocationFix fix);
}

class DeviceLocationService implements LocationProvider {
  @override
  Future<LocationFix> currentFix() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        throw const LocationException(LocationFailure.deniedForever);
      }
      if (permission == LocationPermission.denied) {
        throw const LocationException(LocationFailure.denied);
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const LocationException(LocationFailure.serviceOff);
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return LocationFix(
        latitude: p.latitude,
        longitude: p.longitude,
        accuracyMeters: p.accuracy,
      );
    } on LocationException {
      rethrow;
    } on LocationServiceDisabledException {
      throw const LocationException(LocationFailure.serviceOff);
    } on PermissionDeniedException {
      throw const LocationException(LocationFailure.denied);
    } on TimeoutException {
      throw const LocationException(LocationFailure.failed);
    } catch (e) {
      AppLog.d('Location', 'gagal: ${e.runtimeType}');
      throw const LocationException(LocationFailure.failed);
    }
  }

  @override
  Future<String?> placeName(LocationFix fix) async {
    try {
      final marks = await placemarkFromCoordinates(fix.latitude, fix.longitude)
          .timeout(const Duration(seconds: 6));
      if (marks.isEmpty) return null;
      final m = marks.first;
      final parts = <String>[];
      for (final s in [
        m.subLocality,
        m.locality,
        m.subAdministrativeArea,
        m.administrativeArea,
      ]) {
        final v = s?.trim() ?? '';
        if (v.isNotEmpty && !parts.contains(v)) parts.add(v);
      }
      return parts.isEmpty ? null : parts.join(', ');
    } catch (e) {
      AppLog.d('Location', 'geocoding gagal: ${e.runtimeType}');
      return null;
    }
  }
}
