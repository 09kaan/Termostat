import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

class SettingsProvider extends ChangeNotifier {
  bool _isLoading = false;
  String? _error;

  double hysteresis = 0.5;
  int overrideTimeout = 60; // in minutes
  String _theme = 'light'; // Default theme is light
  
  // Geofence settings
  double _homeLatitude = AppConstants.defaultHomeLatitude;
  double _homeLongitude = AppConstants.defaultHomeLongitude;
  double _homeRadiusMeters = AppConstants.defaultHomeRadiusMeters;

  SettingsProvider() {
    _loadSettings();
  }

  bool get isLoading => _isLoading;
  String? get error => _error;
  String get theme => _theme; // Getter for the theme
  
  // Geofence getters
  double get homeLatitude => _homeLatitude;
  double get homeLongitude => _homeLongitude;
  double get homeRadiusMeters => _homeRadiusMeters;

  Future<void> _loadSettings() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      hysteresis = prefs.getDouble('hysteresis') ?? 0.5;
      overrideTimeout = prefs.getInt('overrideTimeout') ?? 60;
      _theme = prefs.getString('theme') ?? 'light';
      
      // Load geofence settings
      _homeLatitude = prefs.getDouble('homeLatitude') ?? AppConstants.defaultHomeLatitude;
      _homeLongitude = prefs.getDouble('homeLongitude') ?? AppConstants.defaultHomeLongitude;
      _homeRadiusMeters = prefs.getDouble('homeRadiusMeters') ?? AppConstants.defaultHomeRadiusMeters;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setHysteresis(double value) async {
    hysteresis = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('hysteresis', value);
    notifyListeners();
  }

  Future<void> setOverrideTimeout(int value) async {
    overrideTimeout = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('overrideTimeout', value);
    notifyListeners();
  }

  Future<void> setTheme(String value) async {
    _theme = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme', value);
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _theme = _theme == 'light' ? 'dark' : 'light';
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme', _theme); // Save theme to preferences
  }

  // Geofence settings methods
  Future<void> setHomeLocation(double latitude, double longitude) async {
    _homeLatitude = latitude;
    _homeLongitude = longitude;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('homeLatitude', latitude);
    await prefs.setDouble('homeLongitude', longitude);
    notifyListeners();
  }

  Future<void> setHomeRadius(double radiusMeters) async {
    _homeRadiusMeters = radiusMeters;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('homeRadiusMeters', radiusMeters);
    notifyListeners();
  }
} 