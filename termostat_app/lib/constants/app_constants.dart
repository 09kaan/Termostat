class AppConstants {
  // Default geofence settings
  static const double defaultHomeLatitude = 39.905556;
  static const double defaultHomeLongitude = 32.870278;
  static const double defaultHomeRadiusMeters = 200.0;
  
  // Temperature limits
  static const double minTemperature = 10.0;
  static const double maxTemperature = 30.0;
  static const double defaultTargetTemperature = 20.0;
  
  // Humidity thresholds
  static const double lowHumidityThreshold = 40.0;
  static const double highHumidityThreshold = 60.0;
  
  // Geofence configuration
  static const int geofenceIntervalMs = 5000;
  static const int geofenceAccuracyMeters = 100;
  static const int geofenceLoiteringDelayMs = 60000;
  static const int geofenceStatusChangeDelayMs = 10000;
  
  // Notification settings
  static const int defaultNotificationId = 0;
  static const String defaultNotificationTitle = 'Thermostat';
  
  // Default temperature presets
  static const double homeTemperature = 25.0;
  static const double awayTemperature = 18.0;
  static const double sleepTemperature = 22.0;
}

