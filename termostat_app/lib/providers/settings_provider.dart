import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

class SettingsProvider extends ChangeNotifier {
  bool _isLoading = false;
  String? _error;

  double hysteresis = 0.5;
  int overrideTimeout = 60; // in minutes
  String _theme = 'light'; // Default theme is light
  String _appearance = 'original';
  Future<void> _appearanceWrite = Future<void>.value();

  // Geofence settings
  double _homeLatitude = AppConstants.defaultHomeLatitude;
  double _homeLongitude = AppConstants.defaultHomeLongitude;
  double _homeRadiusMeters = AppConstants.defaultHomeRadiusMeters;
  bool _geofenceEnabled = true;

  final Map<String, Map<String, String>> _exitLightsByOwner = {};
  bool _exitHeating = true;
  late final Future<void> ready;

  SettingsProvider() {
    ready = _loadSettings();
  }

  bool get exitHeating => _exitHeating;
  Set<String> get exitLightIds {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Set<String>.unmodifiable(
        _exitLightsByOwner[uid]?.keys ?? <String>[]);
  }

  Map<String, String> get exitLightIPs {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Map<String, String>.unmodifiable(
        _exitLightsByOwner[uid] ?? <String, String>{});
  }

  Future<void> setExitHeating(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setBool('geofence_exit_heating', value)) {
      throw StateError('Ayar kaydedilemedi');
    }
    _exitHeating = value;
    notifyListeners();
  }

  Future<void> setExitLightSelected(String ownerUid, String id, bool selected,
      {String? ip}) async {
    if (FirebaseAuth.instance.currentUser?.uid != ownerUid ||
        !RegExp(r'^lamp[1-8]$').hasMatch(id)) return;
    final next = Map<String, String>.from(
        _exitLightsByOwner[ownerUid] ?? <String, String>{});
    if (selected) {
      if (ip == null || ip.isEmpty) throw StateError('Ampul IP bilgisi yok');
      next[id] = ip;
    } else {
      next.remove(id);
    }
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
        'geofence_exit_lights_$ownerUid', jsonEncode(next))) {
      throw StateError('Ayar kaydedilemedi');
    }
    _exitLightsByOwner[ownerUid] = next;
    notifyListeners();
  }

  bool get isLoading => _isLoading;
  String? get error => _error;
  String get theme => _theme; // Getter for the theme
  String get appearance => _appearance;

  // Geofence getters
  double get homeLatitude => _homeLatitude;
  double get homeLongitude => _homeLongitude;
  double get homeRadiusMeters => _homeRadiusMeters;
  bool get geofenceEnabled => _geofenceEnabled;

  Future<void> _loadSettings() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      hysteresis = prefs.getDouble('hysteresis') ?? 0.5;
      overrideTimeout = prefs.getInt('overrideTimeout') ?? 60;
      _theme = prefs.getString('theme') ?? 'light';
      final appearance = prefs.getString('app_appearance_v1');
      _appearance = appearance == 'warm_minimal' ? 'warm_minimal' : 'original';

      // Load geofence settings
      _homeLatitude =
          prefs.getDouble('homeLatitude') ?? AppConstants.defaultHomeLatitude;
      _homeLongitude =
          prefs.getDouble('homeLongitude') ?? AppConstants.defaultHomeLongitude;
      _homeRadiusMeters = prefs.getDouble('homeRadiusMeters') ??
          AppConstants.defaultHomeRadiusMeters;
      _geofenceEnabled = prefs.getBool('geofenceEnabled') ?? true;
      _exitHeating = prefs.getBool('geofence_exit_heating') ?? true;
      const prefix = 'geofence_exit_lights_';
      for (final key in prefs.getKeys().where((k) => k.startsWith(prefix))) {
        try {
          final raw = jsonDecode(prefs.getString(key) ?? '{}');
          if (raw is Map) {
            _exitLightsByOwner[key.substring(prefix.length)] = {
              for (final entry in raw.entries)
                if (entry.key is String &&
                    entry.value is String &&
                    RegExp(r'^lamp[1-8]$').hasMatch(entry.key as String))
                  entry.key as String: entry.value as String,
            };
          }
        } catch (_) {/* Invalid saved selection stays unselected. */}
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setHysteresis(double value) async {
    hysteresis = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('hysteresis', value);
    notifyListeners();
  }

  Future<void> setOverrideTimeout(int value) async {
    overrideTimeout = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('overrideTimeout', value);
    notifyListeners();
  }

  /// Appearance is independent of the existing light/dark setting. Serialize
  /// writes so rapid taps cannot leave a different style saved on disk.
  Future<void> setAppearance(String value) {
    if (value != 'original' && value != 'warm_minimal') {
      return Future<void>.error(ArgumentError.value(value, 'appearance'));
    }
    final operation = _appearanceWrite.then((_) async {
      await ready;
      if (_appearance == value) return;
      final prefs = await SharedPreferences.getInstance();
      final previous = prefs.getString('app_appearance_v1');
      try {
        if (!await prefs.setString('app_appearance_v1', value)) {
          throw StateError('Tema kaydedilemedi');
        }
      } catch (_) {
        // SharedPreferences updates its in-memory cache before disk writes.
        // Restore that cache as well if persistence fails.
        try {
          if (previous == null) {
            await prefs.remove('app_appearance_v1');
          } else {
            await prefs.setString('app_appearance_v1', previous);
          }
        } catch (_) {/* Keep the visible setting unchanged. */}
        rethrow;
      }
      _appearance = value;
      notifyListeners();
    });
    _appearanceWrite = operation.catchError((Object error) {});
    return operation;
  }

  Future<void> setTheme(String value) async {
    _theme = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme', value);
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _theme = _theme == 'light' ? 'dark' : 'light';
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme', _theme); // Save theme to preferences
  }

  // Geofence settings methods
  Future<void> setHomeLocation(double latitude, double longitude) async {
    _homeLatitude = latitude;
    _homeLongitude = longitude;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('homeLatitude', latitude);
    await prefs.setDouble('homeLongitude', longitude);
    notifyListeners();
  }

  Future<void> setHomeRadius(double radiusMeters) async {
    _homeRadiusMeters = radiusMeters;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('homeRadiusMeters', radiusMeters);
    notifyListeners();
  }

  Future<void> setGeofenceEnabled(bool enabled) async {
    _geofenceEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('geofenceEnabled', enabled);
    notifyListeners();
  }
}
