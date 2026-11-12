import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/settings_provider.dart';
import '../models/geofence_diagnostics.dart';

/// iOS is the single command writer, including when Flutter is not running.
/// If native write fails during Wi-Fi -> Cellular handoff, Flutter automatically
/// retries and settles the failed automation command.
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
  String? _settledNativeFailureSnapshot;
  bool _retryingFailedAutomation = false;
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
        _settledNativeFailureSnapshot = null;
        await _saveState(true);
        await _updateDistance();
        break;
      case 'onExitRegion':
        _isInsideGeofence = false;
        _settledNativeFailureSnapshot = null;
        await _saveState(false);
        await _updateDistance();
        break;
      case 'onStateChanged':
        final args = call.arguments as Map?;
        final state = args?['state'];
        if (state == 'inside' || state == 'outside') {
          final nextInside = state == 'inside';
          if (nextInside != _isInsideGeofence) {
            _settledNativeFailureSnapshot = null;
          }
          _isInsideGeofence = nextInside;
          await _saveState(_isInsideGeofence);
          await _updateDistance();
        }
        break;
      case 'onDiagnosticsChanged':
        await refreshDiagnostics();
        break;
      case 'onAutomationResult':
        final args = call.arguments as Map?;
        final msg = args?['message'] as String?;
        _lastAutomationMessage = msg;
        if (_isUnverifiedFailureMessage(msg)) {
          _settledNativeFailureSnapshot = null;
          unawaited(_retryFailedAutomationIfNeeded(force: true));
        }
        await refreshDiagnostics();
        break;
    }
    notifyListeners();
    return null;
  }

  bool _isUnverifiedFailureMessage(String? msg) {
    if (msg == null || msg.isEmpty) return false;
    final lower = msg.toLowerCase();
    return lower.contains('doğrulanamadı') ||
        lower.contains('dogrulanamadi') ||
        lower.contains('kontrol et') ||
        lower.contains('hata');
  }

  /// Wi-Fi -> 5G geçişinde iOS'un gönderemediği konum otomasyonunu
  /// 3 saniye arayla 3 kez deneyerek tamamlar ve ekrandaki hatayı temizler.
  Future<void> _retryFailedAutomationIfNeeded({bool force = false}) async {
    if (_retryingFailedAutomation) return;
    final settings = _settingsProvider;
    final user = FirebaseAuth.instance.currentUser;
    if (settings == null || !settings.geofenceEnabled || user == null) return;

    final currentMsg = _lastAutomationMessage;
    if (!_isUnverifiedFailureMessage(currentMsg)) return;
    if (!force &&
        _settledNativeFailureSnapshot != null &&
        _settledNativeFailureSnapshot == currentMsg) {
      return;
    }

    _retryingFailedAutomation = true;
    try {
      await settings.ready;
      final isOutside = !_isInsideGeofence;

      for (int attempt = 1; attempt <= 3; attempt++) {
        if (attempt > 1 || force) {
          // Wi-Fi -> Hücresel veri (5G) geçişinin oturması için kısa bekleme
          await Future<void>.delayed(Duration(seconds: attempt == 1 ? 2 : 3));
        }
        try {
          // Token'ı ve sunucu zaman farkını doğrula
          await user.getIdToken();
          int serverOffset = 0;
          try {
            final offsetSnap = await FirebaseDatabase.instance
                .ref('.info/serverTimeOffset')
                .get()
                .timeout(const Duration(seconds: 3));
            if (offsetSnap.value is num) {
              serverOffset = (offsetSnap.value as num).toInt();
            }
          } catch (_) {}

          final nowMs = DateTime.now().millisecondsSinceEpoch + serverOffset;
          final uid = user.uid;
          final homeRef = FirebaseDatabase.instance.ref('wizHomes/$uid');

          if (isOutside) {
            // Dışarı çıkıldı: Seçili çıkış ışıklarını ve kombiyi kapat
            for (final lightId in settings.exitLightIds) {
              final cmdRef = homeRef.child('commands/$lightId');
              final cmdId = cmdRef.push().key!;
              await cmdRef.set({
                'id': cmdId,
                'issuedAt': ServerValue.timestamp,
                'requestedAt': nowMs,
                'ttlMs': 60000,
                'params': {'state': false},
              }).timeout(const Duration(seconds: 6));
            }
            if (settings.exitHeating) {
              await FirebaseDatabase.instance
                  .ref('devices/device1')
                  .update({
                    'mode': 'off',
                    'isHeating': false,
                    'updatedAt': (nowMs / 1000).round(),
                  })
                  .timeout(const Duration(seconds: 6));
            }
          } else {
            // Eve girildi: Seçili giriş ışıklarını ve kombiyi aç
            for (final lightId in settings.entryLightIds) {
              final cmdRef = homeRef.child('commands/$lightId');
              final cmdId = cmdRef.push().key!;
              await cmdRef.set({
                'id': cmdId,
                'issuedAt': ServerValue.timestamp,
                'requestedAt': nowMs,
                'ttlMs': 60000,
                'params': {'state': true},
              }).timeout(const Duration(seconds: 6));
            }
            if (settings.entryHeating) {
              await FirebaseDatabase.instance
                  .ref('devices/device1')
                  .update({
                    'mode': 'on',
                    'updatedAt': (nowMs / 1000).round(),
                  })
                  .timeout(const Duration(seconds: 6));
            }
          }

          final hh = DateTime.now().hour.toString().padLeft(2, '0');
          final mm = DateTime.now().minute.toString().padLeft(2, '0');
          _settledNativeFailureSnapshot = currentMsg;
          _lastAutomationMessage =
              'Konum otomasyonu tamamlandı (${isOutside ? "Çıkış" : "Giriş"} · $hh:$mm)';
          notifyListeners();
          return;
        } catch (e) {
          debugPrint('[GeofenceRetry] Deneme $attempt başarısız: $e');
        }
      }
    } finally {
      _retryingFailedAutomation = false;
    }
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
        final nativeMsg =
            raw['lastResult'] is String ? raw['lastResult'] as String : null;
        if (_settledNativeFailureSnapshot != null &&
            nativeMsg == _settledNativeFailureSnapshot &&
            _lastAutomationMessage != null &&
            !_isUnverifiedFailureMessage(_lastAutomationMessage)) {
          // Daha önce kurtardığımız hata mesajının tekrar üstüne yazılmasını engelle
        } else {
          _lastAutomationMessage = nativeMsg;
        }
        if (_isUnverifiedFailureMessage(_lastAutomationMessage)) {
          unawaited(_retryFailedAutomationIfNeeded());
        }
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
    _settledNativeFailureSnapshot = null;
    _sampleExpiry?.cancel();
    if (_observingLifecycle) WidgetsBinding.instance.removeObserver(this);
    _observingLifecycle = false;
  }
}
