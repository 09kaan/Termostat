import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weather/weather.dart';

class WeatherProvider with ChangeNotifier {
  final WeatherFactory _wf;

  Weather? _weatherData;
  bool _isLoading = false;
  String? _error;

  Weather? get weatherData => _weatherData;
  bool get isLoading => _isLoading;
  String? get error => _error;
  double? get outdoorCelsius => _weatherData?.temperature?.celsius;

  WeatherProvider()
      : _wf = WeatherFactory(
          'b651e31ee2e0cd1e62be2bbd9c2f999c',
          language: Language.TURKISH,
        ) {
    fetchWeatherForCurrentLocation();
  }

  Future<void> fetchWeatherForCurrentLocation() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      double? latitude;
      double? longitude;

      // 1. Önce pil harcamamak için kayıtlı ev konumunu veya son bilinen konumu dene
      final prefs = await SharedPreferences.getInstance();
      final savedHomeLat = prefs.getDouble('homeLatitude');
      final savedHomeLng = prefs.getDouble('homeLongitude');

      Position? lastKnown;
      try {
        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse) {
          lastKnown = await Geolocator.getLastKnownPosition();
        }
      } catch (_) {}

      if (lastKnown != null) {
        latitude = lastKnown.latitude;
        longitude = lastKnown.longitude;
      } else if (savedHomeLat != null && savedHomeLng != null) {
        latitude = savedHomeLat;
        longitude = savedHomeLng;
      } else {
        // Sadece hiç konum yoksa düşük güçte (low/medium) tek seferlik konum al
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
        ).timeout(const Duration(seconds: 5));
        latitude = position.latitude;
        longitude = position.longitude;
      }

      _weatherData = await _wf.currentWeatherByLocation(latitude, longitude);
      _error = null;
      unawaited(_syncOutdoorWeatherToFirebase());
    } catch (e) {
      // Varsayılan olarak Ankara koordinatlarını kullan
      const double ankaraLatitude = 39.933363;
      const double ankaraLongitude = 32.859742;
      try {
        _weatherData = await _wf.currentWeatherByLocation(
          ankaraLatitude,
          ankaraLongitude,
        );
        _error = 'Cihaz konumu alınamadı, Ankara hava durumu gösteriliyor.';
        unawaited(_syncOutdoorWeatherToFirebase());
      } catch (_) {
        _error = 'Hava durumu verisi alınamadı.';
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// ESP32'nin Optimum Start ve Sıcak Hava Koruması kararlarında kullanabilmesi için
  /// güncel dış hava sıcaklığını Firebase'e yazar.
  Future<void> _syncOutdoorWeatherToFirebase() async {
    try {
      final temp = _weatherData?.temperature?.celsius;
      if (temp == null || FirebaseAuth.instance.currentUser == null) return;
      await FirebaseDatabase.instance
          .ref('devices/device1/weather')
          .update({
        'outdoorTemperature': double.parse(temp.toStringAsFixed(1)),
        'outdoorHumidity': _weatherData?.humidity,
        'city': _weatherData?.areaName ?? '',
        'updatedAt': ServerValue.timestamp,
      });
    } catch (_) {}
  }
}
