import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../services/geofence_service.dart';

/// Choices only: native iOS owns all geofence command delivery.
class GeofenceExitOptions extends StatefulWidget {
  const GeofenceExitOptions({super.key});
  @override
  State<GeofenceExitOptions> createState() => _GeofenceExitOptionsState();
}

class _GeofenceExitOptionsState extends State<GeofenceExitOptions> {
  StreamSubscription<User?>? _auth;
  String? _owner;
  Stream<DatabaseEvent>? _lights;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _bind(FirebaseAuth.instance.currentUser);
    _auth = FirebaseAuth.instance.authStateChanges().listen(_bind);
  }

  void _bind(User? user) {
    if (_owner == user?.uid && _lights != null) return;
    void apply() {
      _owner = user?.uid;
      _lights = user == null ? null : FirebaseDatabase.instance
          .ref('wizHomes/${user.uid}/config/lights').onValue;
    }
    if (mounted) { setState(apply); } else { apply(); }
  }

  @override
  void dispose() { _auth?.cancel(); super.dispose(); }

  Future<void> _save(Future<void> Function() save) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await save();
      final synced = await ThermostatGeofenceService().syncExitActions();
      if (!synced && mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seçim kaydedildi ancak konum hizmeti hazır değil. Konum iznini kontrol edip uygulamayı yeniden aç.')),
      );
    }
    catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seçim kaydedilemedi. Tekrar dene.')),
      );
    } finally { if (mounted) setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final owner = _owner;
    final enabled = settings.geofenceEnabled && !settings.isLoading && !_saving && owner != null;
    final selected = settings.exitLightIds;
    return Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text(
          'Evden çıkınca neler kapatılsın?',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        )),
        CheckboxListTile(
          title: const Text('Kombi / ısıtma'),
          subtitle: const Text('Isıtmayı kapatır; hedef sıcaklığı değiştirmez.'),
          value: settings.exitHeating,
          onChanged: enabled ? (v) => _save(() => settings.setExitHeating(v ?? false)) : null,
        ),
        if (owner == null) const Padding(padding: EdgeInsets.all(16), child: Text('Ampul seçmek için giriş yap.'))
        else StreamBuilder<DatabaseEvent>(
          key: ValueKey(owner), stream: _lights,
          builder: (context, snapshot) {
            final raw = snapshot.data?.snapshot.value;
            final lights = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
            final ids = <String>{...lights.keys, ...selected}.toList()..sort();
            return Column(children: [
              if (snapshot.hasError) const Padding(padding: EdgeInsets.all(16), child: Text(
                'Ampul listesi okunamadı. Mevcut seçimlerin korunuyor; bağlantıyı ve WiZ kurallarını kontrol et.',
              ))
              else if (!snapshot.hasData) const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
              if (snapshot.hasData && ids.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text(
                'Önce Işıklar ekranından ampul ekle. Sonra burada ayrı ayrı seçebilirsin.',
              )),
              for (final id in ids)
                if (RegExp(r'^lamp[1-8]$').hasMatch(id))
                  CheckboxListTile(
                    title: Text(lights[id] is Map ? (lights[id]['name'] as String? ?? id) : id),
                    subtitle: Text(lights.containsKey(id)
                      ? (lights[id] is Map && settings.exitLightIPs[id] != null &&
                          settings.exitLightIPs[id] != lights[id]['ip']
                          ? 'IP değişmiş; seçimi kaldırıp yeniden seç.'
                          : 'Çıkışta bu ampule kapatma komutu gönderilir.')
                      : 'Listede bulunamıyor; eski seçimi buradan kaldırabilirsin.'),
                    value: selected.contains(id),
                    onChanged: enabled && (lights.containsKey(id) || selected.contains(id))
                      ? (v) => _save(() => settings.setExitLightSelected(owner, id, v ?? false,
                        ip: lights[id] is Map ? lights[id]['ip'] as String? : null)) : null,
                  ),
            ]);
          },
        ),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text(
          'Yalnızca seçtiklerin kapanır. Bu seçimler bu telefona ve ampuller için giriş yaptığın hesaba aittir. '
          'Eve dönüşte ışıklar otomatik açılmaz; mevcut ısıtma otomasyonu devam eder.',
          style: TextStyle(fontSize: 12),
        )),
        if (!settings.geofenceEnabled) const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text(
          'Konum otomasyonu kapalı. Seçimler saklanır ancak çalıştırılmaz.',
        )),
      ],
    )));
  }
}
