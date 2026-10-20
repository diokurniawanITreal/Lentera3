import '../command/command_router.dart';
import '../core/indonesian_speech.dart';
import '../core/messages.dart';
import 'location_service.dart';
import 'weather_service.dart';

/// Menghasilkan kalimat jawaban (siap dibacakan) untuk layanan Mode Dasar.
abstract class InfoAnswerer {
  Future<String> answer(BasicIntent intent);
}

class BasicInfoService implements InfoAnswerer {
  BasicInfoService({
    required LocationProvider location,
    required WeatherProvider weather,
    DateTime Function()? clock,
  })  : _location = location,
        _weather = weather,
        _clock = clock ?? DateTime.now;

  final LocationProvider _location;
  final WeatherProvider _weather;
  final DateTime Function() _clock;

  @override
  Future<String> answer(BasicIntent intent) {
    switch (intent) {
      case BasicIntent.time:
        return Future.value(IndonesianSpeech.time(_clock()));
      case BasicIntent.date:
        return Future.value(IndonesianSpeech.date(_clock()));
      case BasicIntent.location:
        return _locationAnswer();
      case BasicIntent.weather:
        return _weatherAnswer(rainQuestion: false);
      case BasicIntent.rain:
        return _weatherAnswer(rainQuestion: true);
    }
  }

  String _locationMessage(LocationFailure f) {
    switch (f) {
      case LocationFailure.denied:
        return Msg.locPermission;
      case LocationFailure.deniedForever:
        return Msg.locPermissionForever;
      case LocationFailure.serviceOff:
        return Msg.locServiceOff;
      case LocationFailure.timeout:
        return Msg.locTimeout;
      case LocationFailure.networkError:
        return Msg.locNetworkError;
      case LocationFailure.failed:
        return Msg.locFailed;
    }
  }

  Future<String> _locationAnswer() async {
    final LocationFix fix;
    try {
      fix = await _location.currentFix();
    } on LocationException catch (e) {
      return _locationMessage(e.failure);
    }
    final place = await _location.placeName(fix);
    final accuracy = fix.accuracyMeters > 200
        ? ' Akurasi rendah, sekitar ${fix.accuracyMeters.round()} meter.'
        : '';
    if (place == null) {
      return 'Lokasi Anda ditemukan, tetapi nama tempatnya belum dapat '
          'ditentukan. Koordinatnya sekitar lintang '
          '${fix.latitude.toStringAsFixed(3)}, bujur '
          '${fix.longitude.toStringAsFixed(3)}.$accuracy';
    }
    return 'Anda berada di ${place.toSpokenString()}.$accuracy';
  }

  Future<String> _weatherAnswer({required bool rainQuestion}) async {
    final LocationFix fix;
    try {
      fix = await _location.currentFix();
    } on LocationException catch (e) {
      // Lokasi dibutuhkan untuk cuaca; jelaskan keterbatasannya.
      return _locationMessage(e.failure);
    }
    final WeatherReading w;
    try {
      w = await _weather.fetch(fix.latitude, fix.longitude);
    } on WeatherException catch (e) {
      switch (e.failure) {
        case WeatherFailure.offline:
          return Msg.offline;
        case WeatherFailure.timeout:
          return Msg.weatherTimeout;
        case WeatherFailure.invalidData:
        case WeatherFailure.server:
          return Msg.weatherFailed;
      }
    }

    final place = await _location.placeName(fix);
    final where = place?.shortName ?? 'lokasi Anda';
    final temp = w.temperature.round();

    final detail = StringBuffer('Suhu $temp derajat Celsius');
    final feels = w.apparentTemperature?.round();
    if (feels != null && (feels - temp).abs() >= 2) {
      detail.write(', terasa seperti $feels derajat');
    }
    if (w.humidity != null) {
      detail.write(', kelembapan ${w.humidity} persen');
    }
    if (w.windSpeed != null) {
      detail.write(', angin ${w.windSpeed!.round()} kilometer per jam');
    }
    detail.write('.');

    // Tambahan info cache
    final cacheNote = w.isFromCache ? ' Data ini dari pembaruan terakhir.' : '';

    if (rainQuestion) {
      return w.isRaining
          ? 'Ya, saat ini di $where sedang ${w.description}. $detail$cacheNote'
          : 'Tidak, saat ini di $where tidak hujan. Cuaca ${w.description}. $detail$cacheNote';
    }
    return 'Cuaca di $where saat ini ${w.description}. $detail$cacheNote';
  }
}
