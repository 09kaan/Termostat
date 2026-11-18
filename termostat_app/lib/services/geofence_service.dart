import 'dart:async';
import 'dart:convert';

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

/// iOS is the single command writer when online, including when Flutter is closed.
/// If native write fails because internet is off or transitioning (Wi-Fi -> 5G),
/// Flutter persists the pending exit/entry command locally and executes it
/// automatically the moment internet/Firebase reconnects.
class ThermostatGeofenceService extends ChangeNotifier
    with WidgetsBindingObserver {
  static final ThermostatGeofenceService _instance =
      ThermostatGeofenceService._internal();
  factory ThermostatGeofenceService() => _instance;
  ThermostatGeofenceService._internal();

  static const _channel = MethodChannel('geofence_channel');
  static const _pendingQueuePrefKey = 'pending_geofence_automation_v1';
  static const int _maxQueueAgeMs = 4 * 60 * 60 * 1000; // 4 saat geçerlilik

  bool _isStarted = false;
  bool _isInitialized = false;
  bool _isInsideGeofence = true;
  bool _lanHomeLock = false;
  bool _firebaseConnected = false;
  GeofenceDiagnostics? _diagnostics;
  Timer? _sampleExpiry;
  bool _observingLifecycle = false;
  String? _lastAutomationMessage;
  String? _settledNativeFailureSnapshot;
  bool _retryingFailedAutomation = false;
  SettingsProvider? _settingsProvider;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<DatabaseEvent>? _connectionSubscription;

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
          unawaited(_processQueuedAutomationIfConnected());
        }
      });

      // İnternet / Firebase bağlantısı geri geldiği an bekleyen konum komutunu işle
      _connectionSubscription?.cancel();
      _connectionSubscription = FirebaseDatabase.instance
          .ref('.info/connected')
          .onValue
          .listen((event) {
        final connected = event.snapshot.value == true;
        _firebaseConnected = connected;
        if (connected) {
          unawaited(_processQueuedAutomationIfConnected());
        }
      });

      await _syncNativePolicy();
      _lastAutomationMessage = await _channel.invokeMethod<String>(
        'getLastAutomationResult',
      );
      await refreshDiagnostics();
      await _processQueuedAutomationIfConnected();
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
      await _clearQueuedAction();
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
        await _enqueuePendingAction(isOutside: false);
        await _updateDistance();
        unawaited(_processQueuedAutomationIfConnected());
        break;
      case 'onExitRegion':
        _isInsideGeofence = false;
        _settledNativeFailureSnapshot = null;
        await _saveState(false);
        await _enqueuePendingAction(isOutside: true);
        await _updateDistance();
        unawaited(_processQueuedAutomationIfConnected());
        break;
      case 'onStateChanged':
        final args = call.arguments as Map?;
        final state = args?['state'];
        if (state == 'inside' || state == 'outside') {
          final nextInside = state == 'inside';
          if (nextInside != _isInsideGeofence) {
            _settledNativeFailureSnapshot = null;
            await _enqueuePendingAction(isOutside: !nextInside);
          }
          _isInsideGeofence = nextInside;
          await _saveState(_isInsideGeofence);
          await _updateDistance();
          unawaited(_processQueuedAutomationIfConnected());
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
          await _enqueuePendingAction(isOutside: !_isInsideGeofence);
          unawaited(_processQueuedAutomationIfConnected(force: true));
        } else if (msg != null && msg.isNotEmpty) {
          // iOS tarafı başarıyla yazdıysa kuyruktaki yedek görevi temizle
          await _clearQueuedAction();
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
        lower.contains('hata') ||
        lower.contains('internet bekleniyor');
  }

  Future<void> _enqueuePendingAction({required bool isOutside}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final payload = jsonEncode({
        'isOutside': isOutside,
        'queuedAtMs': now.millisecondsSinceEpoch,
      });
      await prefs.setString(_pendingQueuePrefKey, payload);
      if (!_firebaseConnected) {
        final hh = now.hour.toString().padLeft(2, '0');
        final mm = now.minute.toString().padLeft(2, '0');
        _lastAutomationMessage =
            'İnternet bekleniyor · ${isOutside ? "Çıkış" : "Giriş"} komutu sıraya alındı ($hh:$mm)';
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _readQueuedAction() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pendingQueuePrefKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final queuedAt = (map['queuedAtMs'] as num?)?.toInt() ?? 0;
      final age = DateTime.now().millisecondsSinceEpoch - queuedAt;
      if (age < 0 || age > _maxQueueAgeMs) {
        await prefs.remove(_pendingQueuePrefKey);
        return null;
      }
      return map;
    } catch (_) {
      return null;
    }
  }

  Future<void> _clearQueuedAction() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingQueuePrefKey);
    } catch (_) {}
  }

  /// İnternet kapalıyken sıraya alınan veya ağ geçişinde yarım kalan
  /// konum otomasyonunu internet bağlandığı anda otomatik olarak işler.
  Future<void> _processQueuedAutomationIfConnected({bool force = false}) async {
    if (_retryingFailedAutomation) return;
    final settings = _settingsProvider;
    final user = FirebaseAuth.instance.currentUser;
    if (settings == null || !settings.geofenceEnabled || user == null) return;

    final queued = await _readQueuedAction();
    final currentMsg = _lastAutomationMessage;
    final hasFailureMsg = _isUnverifiedFailureMessage(currentMsg);

    if (queued == null && !hasFailureMsg) return;
    if (queued == null &&
        !force &&
        _settledNativeFailureSnapshot != null &&
        _settledNativeFailureSnapshot == currentMsg) {
      return;
    }

    final bool isOutside = queued != null
        ? (queued['isOutside'] == true)
        : !_isInsideGeofence;

    if (!_firebaseConnected) {
      final hh = DateTime.now().hour.toString().padLeft(2, '0');
      final mm = DateTime.now().minute.toString().padLeft(2, '0');
      _lastAutomationMessage =
          'İnternet bekleniyor · ${isOutside ? "Çıkış" : "Giriş"} komutu internet açılınca işlenecek ($hh:$mm)';
      notifyListeners();
      return;
    }

    _retryingFailedAutomation = true;
    try {
      await settings.ready;

      for (int attempt = 1; attempt <= 3; attempt++) {
        if (attempt > 1 || force) {
          await Future<void>.delayed(Duration(seconds: attempt == 1 ? 1 : 3));
        }
        try {
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

          await _clearQueuedAction();
          final hh = DateTime.now().hour.toString().padLeft(2, '0');
          final mm = DateTime.now().minute.toString().padLeft(2, '0');
          _settledNativeFailureSnapshot = currentMsg;
          _lastAutomationMessage =
              'Konum otomasyonu tamamlandı (${isOutside ? "Çıkış" : "Giriş"} · $hh:$mm)';
          notifyListeners();
          return;
        } catch (e) {
          debugPrint('[GeofenceOfflineQueue] Deneme $attempt başarısız: $e');
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
        } else if (nativeMsg != null && nativeMsg.isNotEmpty) {
          _lastAutomationMessage = nativeMsg;
        }

        if (_isUnverifiedFailureMessage(_lastAutomationMessage)) {
          final existing = await _readQueuedAction();
          if (existing == null) {
            await _enqueuePendingAction(isOutside: !_isInsideGeofence);
          }
          unawaited(_processQueuedAutomationIfConnected());
        } else {
          unawaited(_processQueuedAutomationIfConnected());
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
    if (state == AppLifecycleState.resumed) {
      unawaited(refreshDiagnostics());
      unawaited(_processQueuedAutomationIfConnected());
    }
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
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _isInitialized = false;
    _isInsideGeofence = true;
    _lanHomeLock = false;
    _firebaseConnected = false;
    _diagnostics = null;
    _lastAutomationMessage = null;
    _settledNativeFailureSnapshot = null;
    _sampleExpiry?.cancel();
    if (_observingLifecycle) WidgetsBinding.instance.removeObserver(this);
    _observingLifecycle = false;
  }
}
