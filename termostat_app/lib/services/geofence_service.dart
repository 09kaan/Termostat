import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/thermostat_provider.dart';
import '../providers/settings_provider.dart';
import '../constants/app_constants.dart';
import 'notifications_service.dart';

class ThermostatGeofenceService extends ChangeNotifier {
  static final ThermostatGeofenceService _instance =
      ThermostatGeofenceService._internal();
  factory ThermostatGeofenceService() => _instance;
  ThermostatGeofenceService._internal();

  static const _channel = MethodChannel('geofence_channel');

  bool _isStarted = false;
  bool _isInitialized = false;
  bool _isInsideGeofence = true;
  double _lastDistance = 0.0;

  // Store context-independent callbacks
  ThermostatProvider? _thermostatProvider;
  SettingsProvider? _settingsProvider;

  /// Initialize the geofence service
  Future<void> initialize(BuildContext context) async {
    if (_isInitialized) return;

    try {
      // Check and request location permissions
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('Location permissions denied');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permissions permanently denied');
        return;
      }

      // Load saved state
      final prefs = await SharedPreferences.getInstance();
      _isInsideGeofence = prefs.getBool('isInsideGeofence') ?? true;

      // Store provider references
      if (context.mounted) {
        _thermostatProvider = Provider.of<ThermostatProvider>(context, listen: false);
        _settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
      }

      // Listen for native geofence events from iOS
      _channel.setMethodCallHandler(_handleNativeEvent);

      _isInitialized = true;
      debugPrint('Geofence service initialized (inside=$_isInsideGeofence)');
    } catch (e) {
      debugPrint('Failed to initialize geofence: $e');
    }
  }

  /// Start native iOS geofence monitoring
  Future<void> start(BuildContext context) async {
    if (_isStarted || !_isInitialized) return;

    try {
      if (context.mounted) {
        _thermostatProvider = Provider.of<ThermostatProvider>(context, listen: false);
        _settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
      }

      final lat = _settingsProvider!.homeLatitude;
      final lng = _settingsProvider!.homeLongitude;
      final radius = _settingsProvider!.homeRadiusMeters;

      // Start native iOS CLLocationManager geofencing
      await _channel.invokeMethod('startMonitoring', {
        'latitude': lat,
        'longitude': lng,
        'radius': radius,
      });

      // Get initial distance
      await _updateDistance();

      _isStarted = true;
      debugPrint('🎯 Native geofence started: lat=$lat, lng=$lng, radius=${radius}m');
    } catch (e) {
      debugPrint('Failed to start native geofence: $e');
      _isStarted = false;
    }
  }

  /// Handle events from native iOS
  Future<dynamic> _handleNativeEvent(MethodCall call) async {
    switch (call.method) {
      case 'onEnterRegion':
        debugPrint('🏠 [Native] Entered home region!');
        _isInsideGeofence = true;
        _lastDistance = 0;
        _saveState(true);
        _handleEnterHome();
        notifyListeners();
        break;

      case 'onExitRegion':
        debugPrint('🚶 [Native] Exited home region!');
        _isInsideGeofence = false;
        _saveState(false);
        _handleExitHome();
        await _updateDistance();
        notifyListeners();
        break;

      case 'onStateChanged':
        final args = call.arguments as Map?;
        final state = args?['state'] as String? ?? 'unknown';
        debugPrint('📍 [Native] State: $state');
        if (state == 'inside') {
          _isInsideGeofence = true;
          _lastDistance = 0;
        } else if (state == 'outside') {
          _isInsideGeofence = false;
          await _updateDistance();
        }
        notifyListeners();
        break;
    }
    return null;
  }

  /// Get current distance from home
  Future<void> _updateDistance() async {
    try {
      if (_settingsProvider == null) return;
      final distance = await _channel.invokeMethod<double>('getDistance', {
        'latitude': _settingsProvider!.homeLatitude,
        'longitude': _settingsProvider!.homeLongitude,
      });
      _lastDistance = distance ?? 0.0;
      notifyListeners();
    } catch (e) {
      debugPrint('Error getting distance: $e');
    }
  }

  /// Save geofence state to persist across app restarts
  Future<void> _saveState(bool isInside) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isInsideGeofence', isInside);
    } catch (e) {
      debugPrint('Error saving geofence state: $e');
    }
  }

  /// Handle entering home
  Future<void> _handleEnterHome() async {
    debugPrint('🏠 GEOFENCE: Entered home zone!');
    await notificationsService.showNotification(
      id: 1,
      title: 'Termostat',
      body: 'Eve hoş geldiniz! Isıtma açılıyor.',
    );

    if (_thermostatProvider?.thermostat != null) {
      _thermostatProvider!.updateTemperature(AppConstants.homeTemperature);
      _thermostatProvider!.updateMode('on');
    }
  }

  /// Handle exiting home
  Future<void> _handleExitHome() async {
    debugPrint('🚶 GEOFENCE: Exited home zone!');
    await notificationsService.showNotification(
      id: 1,
      title: 'Termostat',
      body: 'Evden ayrıldınız. Eko moda geçiliyor.',
    );

    if (_thermostatProvider?.thermostat != null) {
      _thermostatProvider!.updateTemperature(AppConstants.awayTemperature);
      _thermostatProvider!.updateMode('off');
    }
  }

  /// Update geofence with new settings (live)
  Future<void> updateGeofence(BuildContext context) async {
    if (!_isInitialized || !_isStarted) return;
    if (context.mounted) {
      _settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    }

    final lat = _settingsProvider!.homeLatitude;
    final lng = _settingsProvider!.homeLongitude;
    final radius = _settingsProvider!.homeRadiusMeters;

    // Restart monitoring with new coordinates
    await _channel.invokeMethod('startMonitoring', {
      'latitude': lat,
      'longitude': lng,
      'radius': radius,
    });
    await _updateDistance();
    debugPrint('Geofence updated: lat=$lat, lng=$lng, radius=${radius}m');
  }

  /// Stop the geofence service
  Future<void> stop() async {
    try {
      await _channel.invokeMethod('stopMonitoring');
    } catch (e) {
      debugPrint('Error stopping native geofence: $e');
    }
    _isStarted = false;
    debugPrint('Geofence service stopped');
  }

  /// Check if the service is running
  bool get isRunning => _isStarted;

  /// Check if the service is initialized
  bool get isInitialized => _isInitialized;

  /// Whether currently inside the geofence
  bool get isInsideGeofence => _isInsideGeofence;

  /// Last measured distance from home in meters
  double get lastDistance => _lastDistance;

  /// Reset the service state
  void resetState() {
    _isStarted = false;
    _isInitialized = false;
    _isInsideGeofence = true;
  }
}
