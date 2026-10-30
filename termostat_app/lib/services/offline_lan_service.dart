import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'geofence_service.dart';

class OfflineLanService extends ChangeNotifier {
  static final OfflineLanService _instance = OfflineLanService._internal();
  factory OfflineLanService() => _instance;
  OfflineLanService._internal() {
    _loadSavedIp();
  }

  static const String _prefIpKey = 'esp_local_ip_v1';

  bool _isOfflineMode = false;
  bool _isLanReachable = false;
  String? _espLocalIp;
  Timer? _discoveryTimer;
  Map<String, dynamic>? _lastLocalStatus;

  bool get isOfflineMode => _isOfflineMode;
  bool get isLanReachable => _isLanReachable;
  String? get espLocalIp => _espLocalIp;
  Map<String, dynamic>? get lastLocalStatus => _lastLocalStatus;

  Future<void> _loadSavedIp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefIpKey);
      if (saved != null && saved.trim().isNotEmpty) {
        _espLocalIp = saved.trim();
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> saveIpAddress(String ipAddress) async {
    final trimmed = ipAddress.trim();
    _espLocalIp = trimmed.isEmpty ? null : trimmed;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_espLocalIp == null) {
        await prefs.remove(_prefIpKey);
      } else {
        await prefs.setString(_prefIpKey, _espLocalIp!);
      }
    } catch (_) {}
    notifyListeners();
  }

  /// ESP32 yerel IP kontrolü ve durum okuma (/status)
  Future<bool> checkLocalConnection([String? ipAddress]) async {
    final targetIp = (ipAddress ?? _espLocalIp)?.trim();
    if (targetIp == null || targetIp.isEmpty) return false;

    try {
      final response = await http
          .get(Uri.parse('http://$targetIp/status'))
          .timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        await saveIpAddress(targetIp);
        _isLanReachable = true;
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            _lastLocalStatus = decoded;
          }
        } catch (_) {}
        // Ev Wi-Fi ağında ESP'ye ulaşıldığında iOS Geofence'e evde olduğumuzu bildir
        unawaited(ThermostatGeofenceService().setLanHomeLock(true));
        notifyListeners();
        return true;
      }
    } catch (_) {}

    _isLanReachable = false;
    unawaited(ThermostatGeofenceService().setLanHomeLock(false));
    notifyListeners();
    return false;
  }

  /// Yerel ağdan güncel termostat verisini çeker
  Future<Map<String, dynamic>?> fetchLocalStatus() async {
    if (_espLocalIp == null || _espLocalIp!.isEmpty) return null;
    final ok = await checkLocalConnection(_espLocalIp);
    return ok ? _lastLocalStatus : null;
  }

  /// Yerel ağda komut gönder (İnternet yokken veya ev ağında hızlı HTTP API)
  Future<bool> sendLocalCommand({
    String? mode,
    double? targetTemp,
  }) async {
    if (_espLocalIp == null || _espLocalIp!.isEmpty) return false;
    try {
      final payload = <String, dynamic>{
        if (mode != null) 'mode': mode,
        if (targetTemp != null) 'targetTemperature': targetTemp,
      };
      final response = await http
          .post(
            Uri.parse('http://$_espLocalIp/control'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 2));

      final ok = response.statusCode == 200;
      if (ok) {
        _isLanReachable = true;
        unawaited(ThermostatGeofenceService().setLanHomeLock(true));
        notifyListeners();
      }
      return ok;
    } catch (e) {
      debugPrint('Offline LAN Command Error: $e');
      _isLanReachable = false;
      notifyListeners();
      return false;
    }
  }

  /// Yerel ağdan Wake-on-LAN tetikleme
  Future<bool> sendLocalWakePc() async {
    if (_espLocalIp == null || _espLocalIp!.isEmpty) return false;
    try {
      final response = await http
          .post(Uri.parse('http://$_espLocalIp/wake-pc'))
          .timeout(const Duration(seconds: 2));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void setOfflineMode(bool offline, {String? ip}) {
    final changed = _isOfflineMode != offline || (ip != null && ip != _espLocalIp);
    _isOfflineMode = offline;
    if (ip != null) {
      unawaited(saveIpAddress(ip));
    }
    if (changed) notifyListeners();
  }

  void startPeriodicCheck({Duration interval = const Duration(seconds: 15)}) {
    _discoveryTimer?.cancel();
    _discoveryTimer = Timer.periodic(interval, (_) {
      if (_espLocalIp != null && _espLocalIp!.isNotEmpty) {
        unawaited(checkLocalConnection(_espLocalIp));
      }
    });
  }

  void stopPeriodicCheck() {
    _discoveryTimer?.cancel();
    _discoveryTimer = null;
  }
}
