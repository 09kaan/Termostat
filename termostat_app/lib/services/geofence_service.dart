import 'dart:async';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/thermostat_provider.dart';
import '../providers/settings_provider.dart';
import '../constants/app_constants.dart';
import 'notifications_service.dart';

// This callback is called from the background isolate
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(GeofenceTaskHandler());
}

/// Background task handler for geofence monitoring
class GeofenceTaskHandler extends TaskHandler {
  bool _isInsideGeofence = true;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('GeofenceTaskHandler started');
    // Load saved geofence state
    final prefs = await SharedPreferences.getInstance();
    _isInsideGeofence = prefs.getBool('isInsideGeofence') ?? true;
  }

  @override
  void onRepeatEvent(DateTime timestamp) async {
    try {
      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint('Background: Location permission denied');
        return;
      }

      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Read home location from shared preferences
      final prefs = await SharedPreferences.getInstance();
      final homeLat = prefs.getDouble('homeLatitude') ??
          AppConstants.defaultHomeLatitude;
      final homeLng = prefs.getDouble('homeLongitude') ??
          AppConstants.defaultHomeLongitude;
      final homeRadius = prefs.getDouble('homeRadiusMeters') ??
          AppConstants.defaultHomeRadiusMeters;

      // Calculate distance
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        homeLat,
        homeLng,
      );

      final isInside = distance <= homeRadius;

      debugPrint('Background Geofence: distance=${distance.toStringAsFixed(0)}m, '
          'radius=${homeRadius}m, inside=$isInside, wasInside=$_isInsideGeofence');

      // State changed - send data to main isolate
      if (isInside && !_isInsideGeofence) {
        _isInsideGeofence = true;
        await prefs.setBool('isInsideGeofence', true);
        // Send event to main isolate
        FlutterForegroundTask.sendDataToMain({'event': 'enter_home'});
        // Also update notification
        FlutterForegroundTask.updateService(
          notificationTitle: 'Termostat - Evdesiniz',
          notificationText: 'Konum takibi aktif | Mesafe: ${distance.toStringAsFixed(0)}m',
        );
      } else if (!isInside && _isInsideGeofence) {
        _isInsideGeofence = false;
        await prefs.setBool('isInsideGeofence', false);
        FlutterForegroundTask.sendDataToMain({'event': 'exit_home'});
        FlutterForegroundTask.updateService(
          notificationTitle: 'Termostat - Dışarıdasınız',
          notificationText: 'Konum takibi aktif | Mesafe: ${distance.toStringAsFixed(0)}m',
        );
      } else {
        // Just update the distance in notification
        final statusText = isInside ? 'Evdesiniz' : 'Dışarıdasınız';
        FlutterForegroundTask.updateService(
          notificationTitle: 'Termostat - $statusText',
          notificationText: 'Konum takibi aktif | Mesafe: ${distance.toStringAsFixed(0)}m',
        );
      }
    } catch (e) {
      debugPrint('Background geofence error: $e');
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('GeofenceTaskHandler destroyed');
  }
}

/// Main service class managing the foreground task
class ThermostatGeofenceService {
  static final ThermostatGeofenceService _instance =
      ThermostatGeofenceService._internal();
  factory ThermostatGeofenceService() => _instance;
  ThermostatGeofenceService._internal();

  bool _isStarted = false;
  bool _isInitialized = false;
  ReceivePort? _receivePort;

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

      // Request "always" permission for background
      if (permission == LocationPermission.whileInUse) {
        permission = await Geolocator.requestPermission();
      }

      // Initialize foreground task
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'geofence_channel',
          channelName: 'Geofence Service',
          channelDescription: 'Konum takibi ile termostat kontrolü',
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: false,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.repeat(60000), // Check every 60 seconds
          autoRunOnBoot: true,
          autoRunOnMyPackageReplaced: true,
          allowWakeLock: true,
          allowWifiLock: true,
        ),
      );

      _isInitialized = true;
      debugPrint('Geofence service initialized');
    } catch (e) {
      debugPrint('Failed to initialize geofence: $e');
    }
  }

  /// Start the geofence service (foreground task)
  Future<void> start(BuildContext context) async {
    if (_isStarted || !_isInitialized) return;

    try {
      // Set up receive port to get messages from background
      _receivePort = FlutterForegroundTask.receivePort;
      _receivePort?.listen((data) {
        if (data is Map) {
          final event = data['event'];
          if (event == 'enter_home') {
            _handleEnterHome(context);
          } else if (event == 'exit_home') {
            _handleExitHome(context);
          }
        }
      });

      // Start the foreground task
      if (await FlutterForegroundTask.isRunningService) {
        debugPrint('Foreground task already running, restarting...');
        await FlutterForegroundTask.restartService();
      } else {
        await FlutterForegroundTask.startService(
          serviceId: 256,
          notificationTitle: 'Termostat - Konum Takibi',
          notificationText: 'Geofence aktif, konum izleniyor...',
          callback: startCallback,
        );
      }

      _isStarted = true;
      debugPrint('Geofence foreground service started');
    } catch (e) {
      debugPrint('Failed to start geofence: $e');
      _isStarted = false;
    }
  }

  /// Handle entering home
  Future<void> _handleEnterHome(BuildContext context) async {
    debugPrint('GEOFENCE: Entered home zone!');
    await notificationsService.showNotification(
      id: 1,
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
      id: 1,
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

  /// Update geofence with new settings (live)
  Future<void> updateGeofence(BuildContext context) async {
    if (!_isInitialized) return;
    debugPrint('Geofence settings updated - takes effect on next check');
  }

  /// Stop the geofence service
  Future<void> stop() async {
    _receivePort?.close();
    _receivePort = null;
    await FlutterForegroundTask.stopService();
    _isStarted = false;
    debugPrint('Geofence foreground service stopped');
  }

  /// Check if the service is running
  bool get isRunning => _isStarted;

  /// Check if the service is initialized
  bool get isInitialized => _isInitialized;

  /// Reset the service state
  void resetState() {
    _isStarted = false;
    _isInitialized = false;
  }
}
