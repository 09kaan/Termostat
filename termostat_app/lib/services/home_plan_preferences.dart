import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/home_plan.dart';

/// Device-local and scoped per authenticated owner. No Firebase schema changes.
class HomePlanPreferences {
  static String key(String owner) => 'home_plan_v1_$owner';
  Future<Map<String, FixtureBinding>> load(String owner) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key(owner));
    if (raw == null) return {};
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! Map) return {};
      final result = <String, FixtureBinding>{};
      final used = <String>{};
      for (final f in HomePlan.fixtures) {
        final v = parsed[f.id];
        if (v is! Map || v['lightId'] is! String || v['ip'] is! String)
          continue;
        final id = v['lightId'] as String, ip = v['ip'] as String;
        if (!RegExp(r'^lamp[1-8]$').hasMatch(id) || ip.isEmpty || !used.add(id))
          continue;
        result[f.id] = FixtureBinding(id, ip);
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  Future<void> save(String owner, Map<String, FixtureBinding> bindings) async {
    final prefs = await SharedPreferences.getInstance();
    final previous = prefs.getString(key(owner));
    try {
      if (!await prefs.setString(
          key(owner),
          jsonEncode(
              {for (final e in bindings.entries) e.key: e.value.toJson()})))
        throw StateError('Eşleştirme kaydedilemedi');
    } catch (_) {
      try {
        if (previous == null) {
          await prefs.remove(key(owner));
        } else {
          await prefs.setString(key(owner), previous);
        }
      } catch (_) {}
      rethrow;
    }
  }

  /// Reject stale IPs and duplicate assignments; never infer placement by name.
  static String? resolve(String fixture, Map<String, FixtureBinding> bindings,
      Map<String, dynamic> lights) {
    final b = bindings[fixture];
    if (b == null) return null;
    final config = lights[b.lightId];
    return config is Map && config['ip'] == b.ip ? b.lightId : null;
  }

  static Map<String, FixtureBinding> assign(Map<String, FixtureBinding> current,
      String fixture, String? lightId, Map<String, dynamic> lights) {
    if (!HomePlan.fixtures.any((f) => f.id == fixture))
      throw ArgumentError('Bilinmeyen lamba konumu');
    final next = Map<String, FixtureBinding>.from(current)..remove(fixture);
    if (lightId != null) {
      final c = lights[lightId];
      if (!RegExp(r'^lamp[1-8]$').hasMatch(lightId) ||
          c is! Map ||
          c['ip'] is! String) throw ArgumentError('Geçersiz ampul');
      next.removeWhere((_, b) => b.lightId == lightId);
      next[fixture] = FixtureBinding(lightId, c['ip'] as String);
    }
    return next;
  }
}
