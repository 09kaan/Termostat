import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/settings_provider.dart';
import '../models/geofence_diagnostics.dart';

/// iOS is the single command writer, including when Flutter is not running.
/// Flutter receives state/results only; it never duplicates heating/light commands.
class ThermostatGeofenceService extends ChangeNotifier
    with WidgetsBindingObserver {
  static final ThermostatGeofenceService _instance =
      ThermostatGeofenceService._internal();
  factory ThermostatGeofenceService() => _instance;
  ThermostatGeofenceService._internal();
  static const _channel = MethodChannel('geofence_channel');
  bool _isStarted = false;
  bool _isInitialized = false;
  bool _isInsideGeofence = true;
  bool _lanHomeLock = false;
  GeofenceDiagnostics? _diagnostics;
  Timer? _sampleExpiry;
  bool _observingLifecycle = false;
  String? _lastAutomationMessage;
  SettingsProvider? _settingsProvider;
  StreamSubscription<User?>? _authSubscription;
  bool get _supported => defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> initialize(BuildContext context) async {
    if (_isInitialized) return;
    if (!_supported) return;
    if (!_observingLifecycle) {
      WidgetsBinding.instance.addObserver(this);
      _observingLifecycle = true;
    }
    await refreshDiagnostics();
    try {
      final settings = Provider.of<SettingsProvider>(context, listen: false);
      await settings.ready;
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        await refreshDiagnostics();
        return;
      }
      _settingsProvider = settings;
      final prefs = await SharedPreferences.getInstance();
      _isInsideGeofence = prefs.getBool('isInsideGeofence') ?? true;
      _channel.setMethodCallHandler(_handleNativeEvent);
      _isInitialized = true;
      _authSubscription?.cancel();
      _authSubscription = FirebaseAuth.instance.authStateChanges().listen((
        user,
      ) {
        if (user == null) {
          unawaited(stop());
        } else {
          unawaited(_syncNativePolicy());
        }
      });
      await _syncNativePolicy();
      _lastAutomationMessage = await _channel.invokeMethod<String>(
        'getLastAutomationResult',
      );
      await refreshDiagnostics();
      notifyListeners();
    } catch (_) {
      debugPrint('Konum otomasyonu başlatılamadı.');
    }
  }

  /// Ev Wi-Fi ağında ESP32'ye doğrudan ulaşıldığında iOS tarafına
  /// evde olduğumuzu bildirerek GPS sapmalarından kaynaklı sahte çıkışları engeller.
  Future<void> setLanHomeLock(bool onHomeLan) async {
    if (!_supported || _lanHomeLock == onHomeLan) return;
    _lanHomeLock = onHomeLan;
    if (onHomeLan) {
      _isInsideGeofence = true;
      await _saveState(true);
    }
    try {
      await _channel.invokeMethod('setLanHomeLock', {'onHomeLan': onHomeLan});
    } catch (_) {}
    notifyListeners();
  }

  Future<bool> syncExitActions() => _syncNativePolicy();

  Future<bool> _syncNativePolicy() async {
    final settings = _settingsProvider;
    if (!_supported || settings == null || !_isInitialized) return false;
    await settings.ready;
    final user = FirebaseAuth.instance.currentUser;
    try {
      await _channel.invokeMethod('configureExitActions', {
        'enabled': settings.geofenceEnabled && user != null,
        'ownerUid': user?.uid ?? '',
        'heating': settings.exitHeating,
        'entryHeating': settings.entryHeating,
        'entryLightIds': settings.entryLightIds.toList()..sort(),
        'entryLightIPs': settings.entryLightIPs,
        'heatEntry': settings.heatEntryRadius,
        'heatExit': settings.heatExitRadius,
        'lightEntry': settings.lightEntryRadius,
        'lightExit': settings.lightExitRadius,
        'lightIds': settings.exitLightIds.toList()..sort(),
        'lightIPs': settings.exitLightIPs,
      });
      return true;
    } catch (_) {
      _lastAutomationMessage =
          'Konum ayarları iOS tarafına aktarılamadı. Uygulamayı yeniden aç.';
      notifyListeners();
      return false;
    }
  }

  Future<void> start(BuildContext context) async {
    if (!_isInitialized || _isStarted) return;
    if (context.mounted) {
      _settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    }
    if (!await _syncNativePolicy()) return;
    final settings = _settingsProvider;
    if (settings == null ||
        !settings.geofenceEnabled ||
        FirebaseAuth.instance.currentUser == null) return;
    try {
      _isStarted = await _channel.invokeMethod<bool>('startMonitoring', {
            'latitude': settings.homeLatitude,
            'longitude': settings.homeLongitude,
            'radius': settings.homeRadiusMeters,
          }) ??
          false;
      await _updateDistance();
      notifyListeners();
    } catch (_) {
      _isStarted = false;
    }
  }

  Future<dynamic> _handleNativeEvent(MethodCall call) async {
    switch (call.method) {
      case 'onEnterRegion':
        _isInsideGeofence = true;
        await _saveState(true);
        await _updateDistance();
        break;
      case 'onExitRegion':
        _isInsideGeofence = false;
        await _saveState(false);
        await _updateDistance();
        break;
      case 'onStateChanged':
        final args = call.arguments as Map?;
        final state = args?['state'];
        if (state == 'inside' || state == 'outside') {
          _isInsideGeofence = state == 'inside';
          await _saveState(_isInsideGeofence);
          await _updateDistance();
        }
        break;
      case 'onDiagnosticsChanged':
        await refreshDiagnostics();
        break;
      case 'onAutomationResult':
        final args = call.arguments as Map?;
        _lastAutomationMessage = args?['message'] as String?;
        await refreshDiagnostics();
        break;
    }
    notifyListeners();
    return null;
  }

  Future<void> _saveState(bool inside) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isInsideGeofence', inside);
    } catch (_) {}
  }

  Future<void> _updateDistance() => refreshDiagnostics();

  Future<void> refreshDiagnostics() async {
    if (!_supported) return;
    _sampleExpiry?.cancel();
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'getMonitoringDiagnostics',
      );
      if (raw != null) {
        _diagnostics = GeofenceDiagnostics.fromMap(
          raw,
          now: DateTime.now().millisecondsSinceEpoch,
        );
        if (_diagnostics!.inside != null) {
          _isInsideGeofence = _diagnostics!.inside!;
        }
        _lastAutomationMessage =
            raw['lastResult'] is String ? raw['lastResult'] as String : null;
        final sampledAt = _diagnostics!.sampledAt;
        if (_diagnostics!.enabled &&
            _diagnostics!.distance != null &&
            sampledAt != null) {
          final remaining = sampledAt.millisecondsSinceEpoch +
              300001 -
              DateTime.now().millisecondsSinceEpoch;
          if (remaining > 0) {
            _sampleExpiry =
                Timer(Duration(milliseconds: remaining), notifyListeners);
          }
        }
      }
    } catch (_) {
      _diagnostics = null;
    }
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refreshDiagnostics());
  }

  Future<void> updateGeofence(BuildContext context) async {
    if (!_isInitialized || !_isStarted) return;
    if (context.mounted) {
      _settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    }
    if (!await _syncNativePolicy()) return;
    final settings = _settingsProvider!;
    try {
      _isStarted = await _channel.invokeMethod<bool>('startMonitoring', {
            'latitude': settings.homeLatitude,
            'longitude': settings.homeLongitude,
            'radius': settings.homeRadiusMeters,
          }) ??
          false;
      await _updateDistance();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> stop() async {
    if (_supported) {
      try {
        await _channel.invokeMethod('configureExitActions', {
          'enabled': false,
          'ownerUid': '',
          'heating': false,
          'lightIds': <String>[],
        });
        await _channel.invokeMethod('stopMonitoring');
      } catch (_) {}
    }
    _isStarted = false;
    await refreshDiagnostics();
    notifyListeners();
  }

  bool get isRunning => _isStarted;
  bool get isInitialized => _isInitialized;
  bool get isInsideGeofence => _isInsideGeofence;
  bool get isLanHomeLocked => _lanHomeLock;
  double? get lastDistance {
    final sample = _diagnostics?.sampledAt;
    if (sample == null) return null;
    final age =
        DateTime.now().millisecondsSinceEpoch - sample.millisecondsSinceEpoch;
    return age >= -5000 && age <= 300000 ? _diagnostics?.distance : null;
  }

  GeofenceDiagnostics? get diagnostics => _diagnostics;
  String? get lastAutomationMessage => _lastAutomationMessage;
  void resetState() {
    unawaited(stop());
    _authSubscription?.cancel();
    _authSubscription = null;
    _isInitialized = false;
    _isInsideGeofence = true;
    _lanHomeLock = false;
    _diagnostics = null;
    _lastAutomationMessage = null;
    _sampleExpiry?.cancel();
    if (_observingLifecycle) WidgetsBinding.instance.removeObserver(this);
    _observingLifecycle = false;
  }
}
