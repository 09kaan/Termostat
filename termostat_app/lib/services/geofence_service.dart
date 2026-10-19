import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/settings_provider.dart';

/// iOS is the single command writer, including when Flutter is not running.
/// Flutter receives state/results only; it never duplicates heating/light commands.
class ThermostatGeofenceService extends ChangeNotifier {
  static final ThermostatGeofenceService _instance = ThermostatGeofenceService._internal();
  factory ThermostatGeofenceService() => _instance;
  ThermostatGeofenceService._internal();
  static const _channel = MethodChannel('geofence_channel');
  bool _isStarted = false;
  bool _isInitialized = false;
  bool _isInsideGeofence = true;
  double _lastDistance = 0;
  String? _lastAutomationMessage;
  SettingsProvider? _settingsProvider;
  StreamSubscription<User?>? _authSubscription;
  bool get _supported => defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> initialize(BuildContext context) async {
    if (_isInitialized) return;
    if (!_supported) return;
    try {
      final settings = Provider.of<SettingsProvider>(context, listen: false);
      await settings.ready;
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
      _settingsProvider = settings;
      final prefs = await SharedPreferences.getInstance();
      _isInsideGeofence = prefs.getBool('isInsideGeofence') ?? true;
      _channel.setMethodCallHandler(_handleNativeEvent);
      _isInitialized = true;
      _authSubscription?.cancel();
      _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user == null) {
          unawaited(stop());
        } else {
          unawaited(_syncNativePolicy());
        }
      });
      await _syncNativePolicy();
      _lastAutomationMessage = await _channel.invokeMethod<String>('getLastAutomationResult');
      notifyListeners();
    } catch (_) { debugPrint('Konum otomasyonu başlatılamadı.'); }
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
        'lightIds': settings.exitLightIds.toList()..sort(),
        'lightIPs': settings.exitLightIPs,
      });
      return true;
    } catch (_) {
      _lastAutomationMessage = 'Konum cihaz seçimleri iOS tarafına aktarılamadı. Uygulamayı yeniden aç.';
      notifyListeners();
      return false;
    }
  }

  Future<void> start(BuildContext context) async {
    if (!_isInitialized || _isStarted) return;
    if (context.mounted) _settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    if (!await _syncNativePolicy()) return;
    final settings = _settingsProvider;
    if (settings == null || !settings.geofenceEnabled || FirebaseAuth.instance.currentUser == null) return;
    try {
      _isStarted = await _channel.invokeMethod<bool>('startMonitoring', {
        'latitude': settings.homeLatitude,
        'longitude': settings.homeLongitude,
        'radius': settings.homeRadiusMeters,
      }) ?? false;
      await _updateDistance();
      notifyListeners();
    } catch (_) { _isStarted = false; }
  }

  Future<dynamic> _handleNativeEvent(MethodCall call) async {
    switch (call.method) {
      case 'onEnterRegion':
        _isInsideGeofence = true;
        _lastDistance = 0;
        await _saveState(true);
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
          if (_isInsideGeofence) { _lastDistance = 0; } else { await _updateDistance(); }
        }
        break;
      case 'onAutomationResult':
        final args = call.arguments as Map?;
        _lastAutomationMessage = args?['message'] as String?;
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
  Future<void> _updateDistance() async {
    final settings = _settingsProvider;
    if (settings == null) return;
    try {
      _lastDistance = await _channel.invokeMethod<double>('getDistance', {
        'latitude': settings.homeLatitude, 'longitude': settings.homeLongitude,
      }) ?? 0;
    } catch (_) {}
  }
  Future<void> updateGeofence(BuildContext context) async {
    if (!_isInitialized || !_isStarted) return;
    if (context.mounted) _settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    if (!await _syncNativePolicy()) return;
    final settings = _settingsProvider!;
    try {
      _isStarted = await _channel.invokeMethod<bool>('startMonitoring', {
        'latitude': settings.homeLatitude, 'longitude': settings.homeLongitude,
        'radius': settings.homeRadiusMeters,
      }) ?? false;
      await _updateDistance();
      notifyListeners();
    } catch (_) {}
  }
  Future<void> stop() async {
    if (_supported) {
      try {
        await _channel.invokeMethod('configureExitActions', {
          'enabled': false, 'ownerUid': '', 'heating': false, 'lightIds': <String>[],
        });
        await _channel.invokeMethod('stopMonitoring');
      } catch (_) {}
    }
    _isStarted = false;
    notifyListeners();
  }
  bool get isRunning => _isStarted;
  bool get isInitialized => _isInitialized;
  bool get isInsideGeofence => _isInsideGeofence;
  double get lastDistance => _lastDistance;
  String? get lastAutomationMessage => _lastAutomationMessage;
  void resetState() {
    unawaited(stop());
    _authSubscription?.cancel();
    _authSubscription = null;
    _isInitialized = false;
    _isInsideGeofence = true;
  }
}
