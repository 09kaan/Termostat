import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:weather/weather.dart';

class WeatherProvider with ChangeNotifier {
  // !!! IMPORTANT: Replace with your actual weather API key !!!
  final String _apiKey = 'b651e31ee2e0cd1e62be2bbd9c2f999c'; 
  final WeatherFactory _wf;

  Weather? _weatherData;
  bool _isLoading = false;
  String? _error;

  Weather? get weatherData => _weatherData;
  bool get isLoading => _isLoading;
  String? get error => _error;

  WeatherProvider() : _wf = WeatherFactory('b651e31ee2e0cd1e62be2bbd9c2f999c', language: Language.ENGLISH) { // !!! IMPORTANT: Replace with your actual weather API key here too !!!
    // Optionally fetch weather data when the provider is created
    fetchWeatherForCurrentLocation();
  }

  Future<void> fetchWeatherForCurrentLocation() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Request/check permission and get device's current position
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final double latitude = position.latitude;
      final double longitude = position.longitude;
      print('Using device location: $latitude, $longitude');

      // Fetch weather data using device's coordinates
      _weatherData = await _wf.currentWeatherByLocation(latitude, longitude);
      _error = null;
    } catch (e) {
      print('Could not get device location, using Ankara as fallback. Error: $e');
      // Fallback to Ankara
      const double ankaraLatitude = 39.933363;
      const double ankaraLongitude = 32.859742;
      _weatherData = await _wf.currentWeatherByLocation(ankaraLatitude, ankaraLongitude);
      _error = 'Could not get device location, showing weather for Ankara.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
} 