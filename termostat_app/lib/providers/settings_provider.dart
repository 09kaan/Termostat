import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../utils/haptics_helper.dart';

class SettingsProvider extends ChangeNotifier {
  final String? Function() _ownerUid;
  static String? _currentOwnerUid() => FirebaseAuth.instance.currentUser?.uid;
  bool _isLoading = false;
  String? _error;

  double hysteresis = 0.5;
  int overrideTimeout = 60; // in minutes
  String _theme = 'light'; // Default theme is light
  String _appearance = 'original';
  Future<void> _appearanceWrite = Future<void>.value();

  // Görsel durum geçişleri, Haptik ve Enerji maliyeti ayarları
  bool _enableDynamicBackground = true;
  bool _enableHaptics = true;
  double _hourlyEnergyCost = 12.5;

  // Hava durumu destekli akıllı şalterler
  bool _optimumStartEnabled = false;
  bool _frostProtectionEnabled = true;
  double _frostProtectionTemp = 12.0;
  bool _warmWeatherAutoOff = false;

  bool get enableDynamicBackground => _enableDynamicBackground;
  bool get enableHaptics => _enableHaptics;
  double get hourlyEnergyCost => _hourlyEnergyCost;
  bool get optimumStartEnabled => _optimumStartEnabled;
  bool get frostProtectionEnabled => _frostProtectionEnabled;
  double get frostProtectionTemp => _frostProtectionTemp;
  bool get warmWeatherAutoOff => _warmWeatherAutoOff;

  // Geofence settings
  double _homeLatitude = AppConstants.defaultHomeLatitude;
  double _homeLongitude = AppConstants.defaultHomeLongitude;
  double _homeRadiusMeters = AppConstants.defaultHomeRadiusMeters;
  bool _geofenceEnabled = true;

  final Map<String, Map<String, String>> _exitLightsByOwner = {};
  bool _exitHeating = true;
  bool _entryHeating = true;
  double _heatEntryRadius = 200,
      _heatExitRadius = 200,
      _lightEntryRadius = 200,
      _lightExitRadius = 200;
  final Map<String, Map<String, String>> _entryLightsByOwner = {};
  bool get entryHeating => _entryHeating;
  double get heatEntryRadius => _heatEntryRadius;
  double get heatExitRadius => _heatExitRadius;
  double get lightEntryRadius => _lightEntryRadius;
  double get lightExitRadius => _lightExitRadius;
  Map<String, String> get entryLightIPs => Map<String, String>.unmodifiable(
      _entryLightsByOwner[_ownerUid()] ?? <String, String>{});
  Set<String> get entryLightIds => entryLightIPs.keys.toSet();

  Future<void> setEntryHeating(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setBool('geo_v10_entry_heating', value)) {
      throw StateError('Kaydedilemedi');
    }
    _entryHeating = value;
    notifyListeners();
  }

  Future<void> setEntryLightSelected(String ownerUid, String id, bool selected,
      {String? ip}) async {
    if (_ownerUid() != ownerUid || !RegExp(r'^lamp[1-8]$').hasMatch(id)) return;
    final next = Map<String, String>.from(_entryLightsByOwner[ownerUid] ?? {});
    if (selected) {
      if (ip == null || ip.isEmpty) throw StateError('IP yok');
      next[id] = ip;
    } else {
      next.remove(id);
    }
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
        'geo_v10_entry_lights_$ownerUid', jsonEncode(next))) {
      throw StateError('Kaydedilemedi');
    }
    _entryLightsByOwner[ownerUid] = next;
    notifyListeners();
  }

  Future<void> setAutomationRadius(String key, double value) async {
    if (!value.isFinite || value < 50 || value > 2000) {
      throw ArgumentError.value(value);
    }
    final current = <String, double>{
      'heatEntry': _heatEntryRadius,
      'heatExit': _heatExitRadius,
      'lightEntry': _lightEntryRadius,
      'lightExit': _lightExitRadius
    };
    if (!current.containsKey(key)) throw ArgumentError.value(key);
    current[key] = value;
    if (current['heatExit']! < current['heatEntry']! ||
        current['lightExit']! < current['lightEntry']!) {
      throw StateError(
          'Çıkış mesafesi giriş mesafesinden küçük olamaz. Önce çıkış mesafesini artır.');
    }
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setDouble('geo_v10_$key', value)) {
      throw StateError('Kaydedilemedi');
    }
    _heatEntryRadius = current['heatEntry']!;
    _heatExitRadius = current['heatExit']!;
    _lightEntryRadius = current['lightEntry']!;
    _lightExitRadius = current['lightExit']!;
    notifyListeners();
  }

  late final Future<void> ready;

  SettingsProvider({String? Function()? ownerUid})
      : _ownerUid = ownerUid ?? _currentOwnerUid {
    ready = _loadSettings();
  }

  bool get exitHeating => _exitHeating;
  Set<String> get exitLightIds {
    final uid = _ownerUid();
    return Set<String>.unmodifiable(
        _exitLightsByOwner[uid]?.keys ?? <String>[]);
  }

  Map<String, String> get exitLightIPs {
    final uid = _ownerUid();
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
    if (_ownerUid() != ownerUid || !RegExp(r'^lamp[1-8]$').hasMatch(id)) return;
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
  String get theme => _theme;
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

      _enableDynamicBackground = prefs.getBool('enable_dynamic_bg') ?? true;
      _enableHaptics = prefs.getBool('enable_haptics') ?? true;
      _hourlyEnergyCost = prefs.getDouble('hourly_energy_cost') ?? 12.5;

      // Hava durumu destekli akıllı şalterleri yükle
      _optimumStartEnabled = prefs.getBool('weather_optimum_start') ?? false;
      _frostProtectionEnabled =
          prefs.getBool('weather_frost_protection') ?? true;
      _frostProtectionTemp =
          prefs.getDouble('weather_frost_temp') ?? 12.0;
      _warmWeatherAutoOff = prefs.getBool('weather_warm_auto_off') ?? false;

      // Load geofence settings
      _homeLatitude =
          prefs.getDouble('homeLatitude') ?? AppConstants.defaultHomeLatitude;
      _homeLongitude =
          prefs.getDouble('homeLongitude') ?? AppConstants.defaultHomeLongitude;
      _homeRadiusMeters = prefs.getDouble('homeRadiusMeters') ??
          AppConstants.defaultHomeRadiusMeters;
      _geofenceEnabled = prefs.getBool('geofenceEnabled') ?? true;
      _exitHeating = prefs.getBool('geofence_exit_heating') ?? true;
      _entryHeating = prefs.getBool('geo_v10_entry_heating') ?? true;
      double radius(String key) {
        final v = prefs.getDouble('geo_v10_$key') ?? _homeRadiusMeters;
        return v.isFinite ? v.clamp(50.0, 2000.0).toDouble() : 200.0;
      }

      _heatEntryRadius = radius('heatEntry');
      _heatExitRadius = radius('heatExit');
      _lightEntryRadius = radius('lightEntry');
      _lightExitRadius = radius('lightExit');
      if (_heatExitRadius < _heatEntryRadius) {
        _heatExitRadius = _heatEntryRadius;
      }
      if (_lightExitRadius < _lightEntryRadius) {
        _lightExitRadius = _lightEntryRadius;
      }
      const entryPrefix = 'geo_v10_entry_lights_';
      for (final key
          in prefs.getKeys().where((k) => k.startsWith(entryPrefix))) {
        try {
          final raw = jsonDecode(prefs.getString(key) ?? '{}');
          if (raw is Map) {
            _entryLightsByOwner[key.substring(entryPrefix.length)] = {
              for (final e in raw.entries)
                if (e.key is String &&
                    e.value is String &&
                    RegExp(r'^lamp[1-8]$').hasMatch(e.key))
                  e.key as String: e.value as String
            };
          }
        } catch (_) {}
      }
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
        } catch (_) {}
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _syncWeatherAssistantToCloud() async {
    try {
      if (FirebaseAuth.instance.currentUser == null) return;
      await FirebaseDatabase.instance
          .ref('devices/device1/weatherAssistant')
          .update({
        'optimumStartEnabled': _optimumStartEnabled,
        'optimumStartLeadMinutes': 25,
        'optimumStartOutdoorThreshold': 5.0,
        'frostProtectionEnabled': _frostProtectionEnabled,
        'frostProtectionTemp': _frostProtectionTemp,
        'warmWeatherAutoOff': _warmWeatherAutoOff,
        'warmWeatherOutdoorThreshold': 20.0,
        'updatedAt': ServerValue.timestamp,
      });
    } catch (_) {}
  }

  Future<void> setOptimumStartEnabled(bool value) async {
    _optimumStartEnabled = value;
    HapticsHelper.modeToggle(enabled: _enableHaptics);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('weather_optimum_start', value);
    unawaited(_syncWeatherAssistantToCloud());
  }

  Future<void> setFrostProtectionEnabled(bool value) async {
    _frostProtectionEnabled = value;
    HapticsHelper.modeToggle(enabled: _enableHaptics);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('weather_frost_protection', value);
    unawaited(_syncWeatherAssistantToCloud());
  }

  Future<void> setFrostProtectionTemp(double value) async {
    if (!value.isFinite || value < 5.0 || value > 18.0) return;
    _frostProtectionTemp = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('weather_frost_temp', value);
    unawaited(_syncWeatherAssistantToCloud());
  }

  Future<void> setWarmWeatherAutoOff(bool value) async {
    _warmWeatherAutoOff = value;
    HapticsHelper.modeToggle(enabled: _enableHaptics);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('weather_warm_auto_off', value);
    unawaited(_syncWeatherAssistantToCloud());
  }

  Future<void> setDynamicBackground(bool value) async {
    _enableDynamicBackground = value;
    HapticsHelper.modeToggle(enabled: _enableHaptics);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('enable_dynamic_bg', value);
  }

  Future<void> setEnableHaptics(bool value) async {
    _enableHaptics = value;
    if (value) HapticsHelper.modeToggle(enabled: true);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('enable_haptics', value);
  }

  Future<void> setHourlyEnergyCost(double value) async {
    if (!value.isFinite || value < 0) return;
    _hourlyEnergyCost = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('hourly_energy_cost', value);
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
        try {
          if (previous == null) {
            await prefs.remove('app_appearance_v1');
          } else {
            await prefs.setString('app_appearance_v1', previous);
          }
        } catch (_) {}
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
    HapticsHelper.modeToggle(enabled: _enableHaptics);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme', _theme);
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
    HapticsHelper.modeToggle(enabled: _enableHaptics);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('geofenceEnabled', enabled);
    notifyListeners();
  }
}
