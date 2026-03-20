import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geofence_service/geofence_service.dart';
import '../providers/thermostat_provider.dart';
import '../providers/settings_provider.dart';
import '../constants/app_constants.dart';
import 'notifications_service.dart';

class ThermostatGeofenceService {
  static final ThermostatGeofenceService _instance =
      ThermostatGeofenceService._internal();
  factory ThermostatGeofenceService() => _instance;
  ThermostatGeofenceService._internal();

  final GeofenceService _geofenceService = GeofenceService.instance.setup(
    interval: AppConstants.geofenceIntervalMs,
    accuracy: AppConstants.geofenceAccuracyMeters,
    loiteringDelayMs: AppConstants.geofenceLoiteringDelayMs,
    statusChangeDelayMs: AppConstants.geofenceStatusChangeDelayMs,
    useActivityRecognition: false,
    allowMockLocations: false,
    printDevLog: true,
  );

  bool _isStarted = false;
  bool _isInitialized = false;

  /// Initialize the geofence service
  Future<void> initialize(BuildContext context) async {
    if (_isInitialized) return;

    try {
      final settings = Provider.of<SettingsProvider>(context, listen: false);
      _geofenceService.addGeofence(
        Geofence(
          id: 'home',
          latitude: settings.homeLatitude,
          longitude: settings.homeLongitude,
          radius: [
            GeofenceRadius(id: 'radius_200m', length: settings.homeRadiusMeters)
          ],
        ),
      );
      _isInitialized = true;
    } catch (e) {
      debugPrint('Failed to initialize geofence: $e');
    }
  }

  /// Start the geofence service
  Future<void> start(BuildContext context) async {
    if (_isStarted || !_isInitialized) return;

    try {
      _geofenceService.addGeofenceStatusChangeListener((Geofence geofence,
          GeofenceRadius radius, GeofenceStatus status, location) async {
        if (geofence.id == 'home') {
          await _handleGeofenceStatusChange(context, status);
        }
      });

      _geofenceService.start();
      _isStarted = true;
    } catch (e) {
      debugPrint('Failed to start geofence: $e');
      // Reset state on error
      _isStarted = false;
    }
  }

  /// Handle geofence status changes
  Future<void> _handleGeofenceStatusChange(
      BuildContext context, GeofenceStatus status) async {
    try {
      if (status == GeofenceStatus.ENTER) {
        await _handleEnterHome(context);
      } else if (status == GeofenceStatus.EXIT) {
        await _handleExitHome(context);
      }
    } catch (e) {
      debugPrint('Error handling geofence status change: $e');
    }
  }

  /// Handle entering home
  Future<void> _handleEnterHome(BuildContext context) async {
    await notificationsService.showNotification(
      id: 0,
      title: 'Thermostat',
      body: 'Welcome home! Adjusting temperature and turning heating on.',
    );

    if (context.mounted) {
      final thermostat =
          Provider.of<ThermostatProvider>(context, listen: false);
      if (thermostat.thermostat != null) {
        thermostat.updateTemperature(25.0);
        thermostat.updateMode('on');
      }
    }
  }

  /// Handle exiting home
  Future<void> _handleExitHome(BuildContext context) async {
    await notificationsService.showNotification(
      id: 0,
      title: 'Thermostat',
      body:
          'You left home. "Hanıma haber vermeyi unutmayın." Setting eco mode and turning heating off.',
    );

    if (context.mounted) {
      final thermostat =
          Provider.of<ThermostatProvider>(context, listen: false);
      if (thermostat.thermostat != null) {
        thermostat.updateTemperature(18.0);
        thermostat.updateMode('off');
      }
    }
  }

  /// Update geofence with new settings
  Future<void> updateGeofence(BuildContext context) async {
    if (!_isInitialized) return;

    try {
      // For now, just log that settings changed
      // The geofence will use the new settings on the next restart
      debugPrint('Geofence settings updated. Restart app to apply changes.');

      // Show a message to the user that they need to restart
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Geofence settings updated. Restart app to apply changes.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('Failed to update geofence: $e');
    }
  }

  /// Stop the geofence service
  Future<void> stop() async {
    if (!_isStarted) return;

    try {
      _geofenceService.stop();
      _isStarted = false;
    } catch (e) {
      debugPrint('Failed to stop geofence: $e');
      // Reset state even if stop fails
      _isStarted = false;
    }
  }

  /// Check if the service is running
  bool get isRunning => _isStarted;

  /// Check if the service is initialized
  bool get isInitialized => _isInitialized;

  /// Reset the service state (useful for error recovery)
  void resetState() {
    _isStarted = false;
    _isInitialized = false;
  }
}
