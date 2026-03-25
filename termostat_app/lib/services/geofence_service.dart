import 'dart:async';
import 'package:flutter/material.dart';
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

  bool _isStarted = false;
  bool _isInitialized = false;
  bool _isInsideGeofence = true; // Assume inside at start
  double _lastDistance = 0.0; // meters from home
  Timer? _locationCheckTimer;
  StreamSubscription<Position>? _positionSubscription;

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

      // Store provider references (these persist beyond widget lifecycle)
      if (context.mounted) {
        _thermostatProvider = Provider.of<ThermostatProvider>(context, listen: false);
        _settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
      }

      _isInitialized = true;
      debugPrint('Geofence service initialized (inside=$_isInsideGeofence)');
    } catch (e) {
      debugPrint('Failed to initialize geofence: $e');
    }
  }

  /// Start the geofence service
  Future<void> start(BuildContext context) async {
    if (_isStarted || !_isInitialized) return;

    try {
      // Update provider references
      if (context.mounted) {
        _thermostatProvider = Provider.of<ThermostatProvider>(context, listen: false);
        _settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
      }

      // Do initial location check
      await _checkLocation();

      // Start adaptive timer (interval depends on distance)
      _scheduleNextCheck();

      // Listen to location changes — works in foreground AND background on iOS
      // if "Location updates" background mode is enabled in Info.plist
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: AppleSettings(
          accuracy: LocationAccuracy.low, // Battery-friendly
          activityType: ActivityType.automotiveNavigation,
          distanceFilter: 50, // Only trigger when moved 50+ meters
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: false, // No blue bar
          allowBackgroundLocationUpdates: true,  // Critical for background
        ),
      ).listen(
        (Position position) {
          _evaluatePosition(position);
        },
        onError: (error) {
          debugPrint('Location stream error: $error');
        },
      );

      _isStarted = true;
      debugPrint('Geofence service started with background location updates');
    } catch (e) {
      debugPrint('Failed to start geofence: $e');
      _isStarted = false;
    }
  }

  /// Get adaptive polling interval based on distance from home
  int _getPollingIntervalSeconds() {
    if (_lastDistance < 1000) return 60;       // < 1km → 60 sn
    if (_lastDistance < 5000) return 180;      // 1-5km → 3 dk
    return 300;                                // > 5km → 5 dk
  }

  /// Schedule next location check with adaptive interval
  void _scheduleNextCheck() {
    _locationCheckTimer?.cancel();
    final interval = _getPollingIntervalSeconds();
    _locationCheckTimer = Timer(
      Duration(seconds: interval),
      () {
        _checkLocation();
        _scheduleNextCheck(); // Reschedule with potentially new interval
      },
    );
    debugPrint('⏱️ Next check in ${interval}s (distance: ${_lastDistance.toStringAsFixed(0)}m)');
  }

  /// Check current location against home
  Future<void> _checkLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      _evaluatePosition(position);
    } catch (e) {
      debugPrint('Error checking location: $e');
    }
  }

  /// Evaluate if position is inside or outside geofence
  void _evaluatePosition(Position position) {
    if (_settingsProvider == null) return;

    final homeLat = _settingsProvider!.homeLatitude;
    final homeLng = _settingsProvider!.homeLongitude;
    final homeRadius = _settingsProvider!.homeRadiusMeters;

    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      homeLat,
      homeLng,
    );

    final isInside = distance <= homeRadius;

    // Update distance and reschedule if interval changed
    final oldInterval = _getPollingIntervalSeconds();
    _lastDistance = distance;
    notifyListeners();
    final newInterval = _getPollingIntervalSeconds();
    if (oldInterval != newInterval && _isStarted) {
      _scheduleNextCheck();
    }

    debugPrint('📍 Geofence: distance=${distance.toStringAsFixed(0)}m, '
        'radius=${homeRadius}m, '
        'inside=$isInside, wasInside=$_isInsideGeofence, '
        'poll=${newInterval}s');

    // Only trigger on state change
    if (isInside && !_isInsideGeofence) {
      _isInsideGeofence = true;
      _saveState(true);
      _handleEnterHome();
    } else if (!isInside && _isInsideGeofence) {
      _isInsideGeofence = false;
      _saveState(false);
      _handleExitHome();
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
    if (!_isInitialized) return;
    // Settings are read live from SettingsProvider, just do a fresh check
    await _checkLocation();
    debugPrint('Geofence settings updated - checked immediately');
  }

  /// Stop the geofence service
  Future<void> stop() async {
    _locationCheckTimer?.cancel();
    _locationCheckTimer = null;
    await _positionSubscription?.cancel();
    _positionSubscription = null;
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
