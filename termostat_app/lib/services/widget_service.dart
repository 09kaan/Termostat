import 'package:home_widget/home_widget.dart';
import 'package:flutter/material.dart';

/// Service to push thermostat data to the iOS home screen widget
class WidgetService {
  static const String _appGroupId = 'group.com.example.termostatApp';
  static const String _iOSWidgetName = 'ThermostatWidget';

  /// Initialize widget service
  static Future<void> initialize() async {
    try {
      await HomeWidget.setAppGroupId(_appGroupId);
      debugPrint('WidgetService initialized');
    } catch (e) {
      debugPrint('WidgetService init error: $e');
    }
  }

  /// Update widget with latest thermostat data
  static Future<void> updateWidget({
    required double temperature,
    required int humidity,
    required bool isHeating,
    required String mode,
    required double targetTemp,
  }) async {
    try {
      await HomeWidget.saveWidgetData<double>('temperature', temperature);
      await HomeWidget.saveWidgetData<int>('humidity', humidity);
      await HomeWidget.saveWidgetData<bool>('isHeating', isHeating);
      await HomeWidget.saveWidgetData<String>('mode', mode);
      await HomeWidget.saveWidgetData<double>('targetTemp', targetTemp);
      await HomeWidget.updateWidget(
        iOSName: _iOSWidgetName,
        androidName: 'ThermostatWidgetProvider',
      );
      debugPrint('Widget updated: ${temperature}°C, ${humidity}%, heating=$isHeating');
    } catch (e) {
      debugPrint('Widget update error: $e');
    }
  }
}
