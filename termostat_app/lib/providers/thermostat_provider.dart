import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/thermostat.dart';

class ThermostatProvider with ChangeNotifier {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  Thermostat? _thermostat;
  bool _isLoading = false;
  String? _error;

  Thermostat? get thermostat => _thermostat;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> initializeThermostat(String deviceId) async {
    _isLoading = true;
    _error = null;

    try {
      final snapshot = await _database.child('devices/$deviceId').get();
      if (snapshot.exists && snapshot.value is Map) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        data['id'] = deviceId;
        _thermostat = Thermostat.fromJson(data);

        // Log the initial thermostat state
        if (_thermostat != null && (_thermostat!.mode == 'on' || _thermostat!.mode == 'off')) {
           final timestamp = DateTime.now().toIso8601String();
           print('Logging initial state - Device ID: ${_thermostat!.id}');
           print('Attempting to log initial state for device: ${_thermostat!.id} at $timestamp with mode: ${_thermostat!.mode}');
           await _database.child('devices/${_thermostat!.id}/log').push().set({'timestamp': timestamp, 'mode': _thermostat!.mode}).catchError((e) {
               print('Firebase logging error (initialize): $e');
           });
        }

      } else {
        _error = 'Device not found or invalid format';
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateTemperature(double temperature) async {
    if (_thermostat == null) return;
    try {
      await _database.child('devices/${_thermostat!.id}/targetTemperature').set(temperature);
      _thermostat = _thermostat!.copyWith(targetTemperature: temperature);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> updateMode(String mode) async {
    if (_thermostat == null) return;

    try {
      await _database.child('devices/${_thermostat!.id}/mode').set(mode);
      _thermostat = _thermostat!.copyWith(mode: mode);

      // Log the thermostat state change
      if (mode == 'on' || mode == 'off') {
        final timestamp = DateTime.now().toIso8601String();
        print('Logging state change - Device ID: ${_thermostat!.id}');
        print('Attempting to log state change for device: ${_thermostat!.id} at $timestamp with mode: $mode');
        await _database.child('devices/${_thermostat!.id}/log').push().set({'timestamp': timestamp, 'mode': mode}).catchError((e) {
            print('Firebase logging error (updateMode): $e');
        });
      }

      notifyListeners();
    } catch (e) {
      _error = 'Failed to update mode: $e';
      notifyListeners();
    }
  }

  Future<void> startListening() async {
    if (_thermostat == null) return;
    _database.child('devices/${_thermostat!.id}').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value is Map) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        data['id'] = _thermostat!.id;
        _thermostat = Thermostat.fromJson(data);
        notifyListeners();
      }
    });
  }

  void stopListening() {
    // No-op for now
  }
} 