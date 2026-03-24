import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../providers/thermostat_provider.dart';
import '../providers/settings_provider.dart';
import '../constants/app_constants.dart';
import 'notifications_service.dart';

class ThermostatGeofenceService {
  static final ThermostatGeofenceService _instance =
      ThermostatGeofenceService._internal();
  factory ThermostatGeofenceService() => _instance;
  ThermostatGeofenceService._internal();

  bool _isStarted = false;
  bool _isInitialized = false;
  bool _isInsideGeofence = true; // Assume inside at start
  Timer? _locationCheckTimer;
  StreamSubscription<Position>? _positionSubscription;

  /// Initialize the geofence service
  Future<void> initialize(BuildContext context) async {
    if (_isInitialized) return;

    try {
      // Check and request location permissions
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

      _isInitialized = true;
      debugPrint('Geofence service initialized');
    } catch (e) {
      debugPrint('Failed to initialize geofence: $e');
    }
  }

  /// Start the geofence service
  Future<void> start(BuildContext context) async {
    if (_isStarted || !_isInitialized) return;

    try {
      // Do initial location check
      await _checkLocation(context);

      // Check location every 60 seconds with a timer
      _locationCheckTimer = Timer.periodic(
        const Duration(seconds: 60),
        (_) => _checkLocation(context),
      );

      // Also listen to significant location changes
      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 50, // Only trigger when moved 50+ meters
      );

      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen((Position position) {
        _evaluatePosition(context, position);
      });

      _isStarted = true;
      debugPrint('Geofence service started');
    } catch (e) {
      debugPrint('Failed to start geofence: $e');
      _isStarted = false;
    }
  }

  /// Check current location against home
  Future<void> _checkLocation(BuildContext context) async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _evaluatePosition(context, position);
    } catch (e) {
      debugPrint('Error checking location: $e');
    }
  }

  /// Evaluate if position is inside or outside geofence
  void _evaluatePosition(BuildContext context, Position position) {
    if (!context.mounted) return;

    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      settings.homeLatitude,
      settings.homeLongitude,
    );

    final isInside = distance <= settings.homeRadiusMeters;

    debugPrint('Geofence: distance=${distance.toStringAsFixed(0)}m, '
        'radius=${settings.homeRadiusMeters}m, '
        'inside=$isInside, wasInside=$_isInsideGeofence');

    // Only trigger on state change
    if (isInside && !_isInsideGeofence) {
      _isInsideGeofence = true;
      _handleEnterHome(context);
    } else if (!isInside && _isInsideGeofence) {
      _isInsideGeofence = false;
      _handleExitHome(context);
    }
  }

  /// Handle entering home
  Future<void> _handleEnterHome(BuildContext context) async {
    debugPrint('GEOFENCE: Entered home zone!');
    await notificationsService.showNotification(
      id: 0,
      title: 'Termostat',
      body: 'Eve hoş geldiniz! Isıtma açılıyor.',
    );

    if (context.mounted) {
      final thermostat =
          Provider.of<ThermostatProvider>(context, listen: false);
      if (thermostat.thermostat != null) {
        thermostat.updateTemperature(AppConstants.homeTemperature);
        thermostat.updateMode('on');
      }
    }
  }

  /// Handle exiting home
  Future<void> _handleExitHome(BuildContext context) async {
    debugPrint('GEOFENCE: Exited home zone!');
    await notificationsService.showNotification(
      id: 0,
      title: 'Termostat',
      body: 'Evden ayrıldınız. Eko moda geçiliyor.',
    );

    if (context.mounted) {
      final thermostat =
          Provider.of<ThermostatProvider>(context, listen: false);
      if (thermostat.thermostat != null) {
        thermostat.updateTemperature(AppConstants.awayTemperature);
        thermostat.updateMode('off');
      }
    }
  }

  /// Update geofence with new settings (live update, no restart needed)
  Future<void> updateGeofence(BuildContext context) async {
    if (!_isInitialized) return;
    // Settings are read live from SettingsProvider in _evaluatePosition,
    // so no restart needed - just do a fresh check
    await _checkLocation(context);
    debugPrint('Geofence settings updated - live!');
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

  /// Reset the service state
  void resetState() {
    _isStarted = false;
    _isInitialized = false;
    _isInsideGeofence = true;
  }
}
