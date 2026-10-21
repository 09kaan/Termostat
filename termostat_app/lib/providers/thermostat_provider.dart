import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/heating_feedback.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/thermostat.dart';
import '../services/widget_service.dart';

class ThermostatProvider with ChangeNotifier {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  Thermostat? _thermostat;
  Map<String, dynamic> _raw = {};
  StreamSubscription<DatabaseEvent>? _deviceSub, _connectionSub, _offsetSub;
  StreamSubscription<User?>? _authSub;
  Timer? _feedbackClock;
  bool _connected = false, _timeReady = false;
  int _serverOffset = 0, _generation = 0;
  String? _pendingControlId;
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
  HeatingFeedback get heatingFeedback => HeatingFeedback.fromDevice(_raw,
      now: DateTime.now().millisecondsSinceEpoch + _serverOffset,
      connected: _connected,
      timeReady: _timeReady,
      pendingControlId: _pendingControlId);
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
      final snapshot = await _database.child('devices/$deviceId').get();
      if (!current()) return;
      if (snapshot.exists && snapshot.value is Map) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        data['id'] = deviceId;
        _raw = data;
        _thermostat = Thermostat.fromJson(data);
        _pushWidgetUpdate(data);

        // Log the initial thermostat state
        if (_thermostat != null &&
            (_thermostat!.mode == 'on' || _thermostat!.mode == 'off')) {
          final timestamp = DateTime.now().toIso8601String();
          print('Logging initial state - Device ID: ${_thermostat!.id}');
          print(
              'Attempting to log initial state for device: ${_thermostat!.id} at $timestamp with mode: ${_thermostat!.mode}');
          await _database.child('devices/${_thermostat!.id}/log').push().set({
            'timestamp': timestamp,
            'mode': _thermostat!.mode
          }).catchError((e) {
            print('Firebase logging error (initialize): $e');
          });
        }
      } else {
        _error = 'Device not found or invalid format';
      }
    } catch (e) {
      if (current()) _error = e.toString();
    } finally {
      if (current()) {
        _isLoading = false;
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
      final id = _database.push().key!;
      final updates = <String, dynamic>{
        'control/id': id,
        'control/requestedAt': ServerValue.timestamp,
        'control/source': 'app',
        if (mode != null) ...{'mode': mode, 'control/mode': mode},
        if (temperature != null) ...{
          'targetTemperature': temperature,
          'control/targetTemperature': temperature
        },
        if (mode == 'off' || mode == 'manual') 'isHeating': false,
      };
      _pendingControlId = id;
      notifyListeners();
      try {
        // No timeout wrapper: a queued SDK write is not cancellable by Future.timeout.
        await _database.child('devices/${_thermostat!.id}').update(updates);
        if (generation != _generation) return;
        _error = null;
      } catch (e) {
        if (generation == _generation) {
          _error = 'Ayar gönderilemedi: $e';
          _pendingControlId = null;
        }
      }
      if (generation == _generation) notifyListeners();
    });
    _writeQueue = operation.catchError((Object _) {});
    return operation;
  }

  /// Firebase'e tek seferlik Wake-on-LAN komutu yazar.
  Future<bool> wakePc() async {
    if (_thermostat == null || _wakeRequestInProgress) return false;

    _wakeRequestInProgress = true;
    _wakeError = null;
    notifyListeners();

    try {
      await _database.child('devices/${_thermostat!.id}/commands/wakePc').set({
        'requested': true,
        'requestedAt': ServerValue.timestamp,
        'requestedBy': 'thermostat_app',
        'status': 'pending',
      });
      return true;
    } catch (e) {
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
    _deviceSub = _database.child('devices/$device').onValue.listen((event) {
      if (generation != _generation || event.snapshot.value is! Map) return;
      final data = Map<String, dynamic>.from(event.snapshot.value as Map)
        ..['id'] = device;
      _raw = data;
      _thermostat = Thermostat.fromJson(data);
      final control = data['control'];
      if (control is Map && control['id'] == _pendingControlId)
        _pendingControlId = null;
      _pushWidgetUpdate(data);
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
      notifyListeners();
    });
    _offsetSub = _database.child('.info/serverTimeOffset').onValue.listen((e) {
      if (generation != _generation) return;
      _timeReady = e.snapshot.value is num;
      _serverOffset = (e.snapshot.value as num?)?.toInt() ?? 0;
      notifyListeners();
    });
    _feedbackClock = Timer.periodic(const Duration(seconds: 5), (_) {
      if (generation == _generation) notifyListeners();
    });
  }

  void stopListening() {
    _generation++;
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
    WidgetService.updateWidget(
      temperature: temperature.toDouble(),
      humidity: humidity.toDouble(),
      isHeating: heatingFeedback.relay == RelayState.on
          ? true
          : heatingFeedback.relay == RelayState.off
              ? false
              : null,
      mode: mode,
      targetTemp: target.toDouble(),
    );
  }
}
