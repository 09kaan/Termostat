import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/heating_feedback.dart';
import '../models/thermostat.dart';
import '../services/widget_service.dart';
import '../services/offline_lan_service.dart';

class ThermostatProvider with ChangeNotifier {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final OfflineLanService _lanService = OfflineLanService();
  Thermostat? _thermostat;
  Map<String, dynamic> _raw = {};
  StreamSubscription<DatabaseEvent>? _deviceSub, _connectionSub, _offsetSub;
  StreamSubscription<User?>? _authSub;
  Timer? _feedbackClock;
  bool _connected = false, _timeReady = false;
  int _serverOffset = 0, _generation = 0;
  String? _pendingControlId;
  String? _lastFeedbackSignature;
  Future<void> _writeQueue = Future<void>.value();

  ThermostatProvider() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        stopListening();
        _thermostat = null;
        _raw = {};
        notifyListeners();
      }
    });
  }

  HeatingFeedback get heatingFeedback => HeatingFeedback.fromDevice(
        _raw,
        now: DateTime.now().millisecondsSinceEpoch + _serverOffset,
        connected: _connected,
        timeReady: _timeReady,
        pendingControlId: _pendingControlId,
      );

  bool _isLoading = false;
  String? _error;
  bool _disposed = false;
  bool _wakeRequestInProgress = false;
  String? _wakeError;

  Thermostat? get thermostat => _thermostat;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get wakeRequestInProgress => _wakeRequestInProgress;
  String? get wakeError => _wakeError;

  String _computeFeedbackSignature() {
    final fb = heatingFeedback;
    return '${fb.relay.name}|${fb.link.name}|${fb.esp32.name}|${fb.esp8266.name}|${fb.detail}|$_pendingControlId';
  }

  Future<void> initializeThermostat(String deviceId) async {
    final generation = _generation;
    final owner = FirebaseAuth.instance.currentUser?.uid;
    bool current() =>
        !_disposed &&
        generation == _generation &&
        owner == FirebaseAuth.instance.currentUser?.uid;
    _isLoading = true;
    _error = null;

    try {
      final snapshot = await _database
          .child('devices/$deviceId')
          .get()
          .timeout(const Duration(seconds: 6));
      if (!current()) return;
      if (snapshot.exists && snapshot.value is Map) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        data['id'] = deviceId;
        _raw = data;
        _thermostat = Thermostat.fromJson(data);
        _lanService.setOfflineMode(false);
        _pushWidgetUpdate(data);
      } else {
        _error = 'Cihaz bulunamadı veya veri formatı geçersiz';
      }
    } catch (e) {
      // Buluta ulaşılamadığında yerel ağ (Offline LAN) yedeğini dene
      final localData = await _lanService.fetchLocalStatus();
      if (current()) {
        if (localData != null) {
          final merged = Map<String, dynamic>.from(localData)..['id'] = deviceId;
          _raw = merged;
          _thermostat = Thermostat.fromJson(merged);
          _lanService.setOfflineMode(true);
          _error = null;
        } else {
          _error = e.toString();
        }
      }
    } finally {
      if (current()) {
        _isLoading = false;
        _lastFeedbackSignature = _computeFeedbackSignature();
        notifyListeners();
      }
    }
  }

  Future<void> updateTemperature(double temperature) =>
      updateControl(temperature: temperature);
  Future<void> updateMode(String mode) => updateControl(mode: mode);

  Future<void> updateControl({String? mode, double? temperature}) {
    if (mode != null && !const {'on', 'off', 'manual'}.contains(mode)) {
      return Future<void>.error(ArgumentError.value(mode));
    }
    if (temperature != null &&
        (!temperature.isFinite || temperature < 10 || temperature > 30)) {
      return Future<void>.error(ArgumentError.value(temperature));
    }
    final generation = _generation;
    final operation = _writeQueue.then((_) async {
      if (_thermostat == null || generation != _generation) return;

      final previousMode = _thermostat!.mode;
      final effectiveMode = mode ?? previousMode;
      final effectiveTemp = temperature ?? _thermostat!.targetTemperature;

      // 1. Ev ağında ESP32 IP'si tanımlıysa yerel ağdan milisaniyeler içinde ilet
      bool sentOverLan = false;
      if (_lanService.espLocalIp != null) {
        sentOverLan = await _lanService.sendLocalCommand(
          mode: mode,
          targetTemp: temperature,
        );
      }

      // 2. İnternet/Firebase yoksa ve LAN başarılıysa yerel state'i anında güncelle
      if (!_connected && sentOverLan) {
        _lanService.setOfflineMode(true);
        _thermostat = _thermostat!.copyWith(
          mode: effectiveMode,
          targetTemperature: effectiveTemp,
          lastUpdated: DateTime.now(),
        );
        _error = null;
        notifyListeners();
        return;
      }

      final id = _database.push().key!;
      final updates = <String, dynamic>{
        'control/id': id,
        'control/requestedAt': ServerValue.timestamp,
        'control/source': 'app',
        if (mode != null) ...{'mode': mode, 'control/mode': mode},
        if (temperature != null) ...{
          'targetTemperature': temperature,
          'control/targetTemperature': temperature,
        },
        if (mode == 'off' || mode == 'manual') 'isHeating': false,
      };
      _pendingControlId = id;
      notifyListeners();
      try {
        await _database.child('devices/${_thermostat!.id}').update(updates);
        if (generation != _generation) return;

        // Sadece mod gerçekten değiştiğinde (on <-> off/manual) log kaydı ekle
        if (mode != null && mode != previousMode) {
          final logMode = (mode == 'on') ? 'on' : 'off';
          unawaited(
            _database.child('devices/${_thermostat!.id}/log').push().set({
              'timestamp': DateTime.now().toIso8601String(),
              'mode': logMode,
              'source': 'app',
            }).catchError((Object _) {}),
          );
        }

        _error = null;
      } catch (e) {
        if (generation == _generation) {
          if (sentOverLan) {
            _lanService.setOfflineMode(true);
            _thermostat = _thermostat!.copyWith(
              mode: effectiveMode,
              targetTemperature: effectiveTemp,
              lastUpdated: DateTime.now(),
            );
            _error = null;
          } else {
            _error = 'Ayar gönderilemedi: $e';
          }
          _pendingControlId = null;
        }
      }
      if (generation == _generation) {
        _lastFeedbackSignature = _computeFeedbackSignature();
        notifyListeners();
      }
    });
    _writeQueue = operation.catchError((Object _) {});
    return operation;
  }

  /// Firebase'e (veya çevrimdışıysa yerel ağa) tek seferlik Wake-on-LAN komutu yazar.
  Future<bool> wakePc() async {
    if (_thermostat == null || _wakeRequestInProgress) return false;

    _wakeRequestInProgress = true;
    _wakeError = null;
    notifyListeners();

    try {
      if (!_connected && _lanService.espLocalIp != null) {
        final lanOk = await _lanService.sendLocalWakePc();
        if (lanOk) return true;
      }
      await _database.child('devices/${_thermostat!.id}/commands/wakePc').set({
        'requested': true,
        'requestedAt': ServerValue.timestamp,
        'requestedBy': 'thermostat_app',
        'status': 'pending',
      });
      return true;
    } catch (e) {
      final lanOk = await _lanService.sendLocalWakePc();
      if (lanOk) return true;
      _wakeError = 'PC açma komutu gönderilemedi: $e';
      return false;
    } finally {
      _wakeRequestInProgress = false;
      notifyListeners();
    }
  }

  Future<void> startListening() async {
    if (_thermostat == null) return;
    final device = _thermostat!.id;
    stopListening();
    final generation = _generation;
    _lanService.startPeriodicCheck();

    _deviceSub = _database.child('devices/$device').onValue.listen((event) {
      if (generation != _generation || event.snapshot.value is! Map) return;
      final data = Map<String, dynamic>.from(event.snapshot.value as Map)
        ..['id'] = device;
      _raw = data;
      _thermostat = Thermostat.fromJson(data);
      final control = data['control'];
      if (control is Map && control['id'] == _pendingControlId) {
        _pendingControlId = null;
      }
      _pushWidgetUpdate(data);
      _lastFeedbackSignature = _computeFeedbackSignature();
      notifyListeners();
    }, onError: (Object e) {
      if (generation == _generation) {
        _error = 'Cihaz verisi okunamadı';
        _connected = false;
        notifyListeners();
      }
    });

    _connectionSub = _database.child('.info/connected').onValue.listen((e) {
      if (generation != _generation) return;
      _connected = e.snapshot.value == true;
      if (_connected) {
        _lanService.setOfflineMode(false);
      } else if (_lanService.isLanReachable) {
        _lanService.setOfflineMode(true);
      }
      _pushWidgetUpdate(_raw);
      _lastFeedbackSignature = _computeFeedbackSignature();
      notifyListeners();
    });

    _offsetSub = _database.child('.info/serverTimeOffset').onValue.listen((e) {
      if (generation != _generation) return;
      _timeReady = e.snapshot.value is num;
      _serverOffset = (e.snapshot.value as num?)?.toInt() ?? 0;
      _pushWidgetUpdate(_raw);
      _lastFeedbackSignature = _computeFeedbackSignature();
      notifyListeners();
    });

    // Performans optimizasyonu: Sadece geri bildirim durumu (örn. süre aşımı)
    // gerçekten değiştiğinde ekranı yenile.
    _feedbackClock = Timer.periodic(const Duration(seconds: 5), (_) {
      if (generation != _generation) return;
      final nextSig = _computeFeedbackSignature();
      if (nextSig != _lastFeedbackSignature) {
        _lastFeedbackSignature = nextSig;
        notifyListeners();
      }
    });
  }

  void stopListening() {
    _generation++;
    _lanService.stopPeriodicCheck();
    _deviceSub?.cancel();
    _connectionSub?.cancel();
    _offsetSub?.cancel();
    _feedbackClock?.cancel();
    _deviceSub = null;
    _connectionSub = null;
    _offsetSub = null;
    _feedbackClock = null;
    _connected = false;
    _timeReady = false;
    _pendingControlId = null;
  }

  @override
  void dispose() {
    _disposed = true;
    stopListening();
    _authSub?.cancel();
    super.dispose();
  }

  /// Publish real sensor fields only; mode=on does not mean the relay is on.
  void _pushWidgetUpdate(Map<String, dynamic> raw) {
    final temperature = raw['currentTemperature'];
    final humidity = raw['currentHumidity'] ?? raw['humidity'];
    final control = raw['control'] is Map ? raw['control'] as Map : const {};
    final target = control['targetTemperature'] ?? raw['targetTemperature'];
    final mode = control['mode'] ?? raw['mode'];
    if (temperature is! num ||
        humidity is! num ||
        target is! num ||
        mode is! String) return;
    final feedback = heatingFeedback;
    WidgetService.updateWidget(
      temperature: temperature.toDouble(),
      humidity: humidity.toDouble(),
      isHeating: feedback.relay == RelayState.on
          ? true
          : feedback.relay == RelayState.off
              ? false
              : null,
      heatingValidUntilMilliseconds: feedback.heatingValidUntil == null
          ? null
          : feedback.heatingValidUntil! - _serverOffset,
      mode: mode,
      targetTemp: target.toDouble(),
    );
  }
}
