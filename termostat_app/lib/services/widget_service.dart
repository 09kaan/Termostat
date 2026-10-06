import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

class WidgetService {
  static const String appGroupId = 'group.com.example.termostatApp';
  static const String _widgetName = 'ThermostatWidget';
  static const String _snapshotKey = 'widget.snapshot.v1';
  static bool _initialized = false;
  static bool _sharingReady = false;

  /// Call before building AuthProvider so Flutter and the extension use the same
  /// Firebase Keychain group. On the first upgrade, the user may need to sign in.
  static Future<void> configureSharedAuthentication() async {
    if (defaultTargetPlatform != TargetPlatform.iOS || kIsWeb) return;
    try {
      await FirebaseAuth.instance.setSettings(userAccessGroup: appGroupId);
      _sharingReady = true;
    } catch (_) {
      _sharingReady = false;
      debugPrint('Widget oturum paylaşımı kurulamadı. App Groups ve profilleri kontrol edin.');
    }
  }

  static Future<void> initialize() async {
    if (_initialized || defaultTargetPlatform != TargetPlatform.iOS || kIsWeb) return;
    await HomeWidget.setAppGroupId(appGroupId);
    _initialized = true;
  }

  static Future<void> setSessionActive(bool active) async {
    if (defaultTargetPlatform != TargetPlatform.iOS || kIsWeb) return;
    try {
      await initialize();
      final owner = active ? FirebaseAuth.instance.currentUser?.uid : null;
      final previousOwner = await HomeWidget.getWidgetData<String>('widget.owner.uid.v1');
      if (previousOwner != owner) await clearWidget();
      await HomeWidget.saveWidgetData<String>('widget.owner.uid.v1', owner);
      await HomeWidget.saveWidgetData<bool>('widget.session.active.v1', active && _sharingReady);
      if (!active) await clearWidget();
    } catch (_) {
      debugPrint('Widget oturum durumu güncellenemedi.');
    }
  }

  static Future<void> updateWidget({
    required double temperature,
    required double humidity,
    required bool? isHeating,
    required String mode,
    required double targetTemp,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.iOS || kIsWeb || !_sharingReady) return;
    if (FirebaseAuth.instance.currentUser == null) return;
    if (!temperature.isFinite || !humidity.isFinite || !targetTemp.isFinite) return;
    if (temperature < -40 || temperature > 85 || humidity < 0 || humidity > 100 ||
        targetTemp < 10 || targetTemp > 30 || !['on', 'off'].contains(mode)) return;
    try {
      await initialize();
      await HomeWidget.saveWidgetData<String>(_snapshotKey, jsonEncode({
        'temperature': temperature,
        'humidity': humidity,
        'targetTemperature': targetTemp,
        'mode': mode,
        'isHeating': isHeating,
        'observedAtMilliseconds': DateTime.now().millisecondsSinceEpoch,
        'commandAtMilliseconds': null,
      }));
      await HomeWidget.updateWidget(iOSName: _widgetName);
    } catch (_) {
      debugPrint('Widget verileri güncellenemedi.');
    }
  }

  static Future<void> clearWidget() async {
    if (defaultTargetPlatform != TargetPlatform.iOS || kIsWeb) return;
    try {
      await initialize();
      await HomeWidget.saveWidgetData<String>(_snapshotKey, null);
      await HomeWidget.updateWidget(iOSName: _widgetName);
    } catch (_) {
      debugPrint('Widget önbelleği temizlenemedi.');
    }
  }
}
