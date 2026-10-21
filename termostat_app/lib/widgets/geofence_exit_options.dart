import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../services/geofence_service.dart';

class GeofenceExitOptions extends StatefulWidget {
  const GeofenceExitOptions({super.key});
  @override
  State<GeofenceExitOptions> createState() => _GeofenceExitOptionsState();
}

class _GeofenceExitOptionsState extends State<GeofenceExitOptions> {
  StreamSubscription<User?>? _auth;
  Stream<DatabaseEvent>? _lights;
  String? _owner;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _bind(FirebaseAuth.instance.currentUser);
    _auth = FirebaseAuth.instance.authStateChanges().listen(_bind);
  }

  void _bind(User? user) {
    if (_owner == user?.uid && _lights != null) return;
    setState(() {
      _owner = user?.uid;
      _lights = user == null
          ? null
          : FirebaseDatabase.instance
              .ref('wizHomes/${user.uid}/config/lights')
              .onValue;
    });
  }

  @override
  void dispose() {
    _auth?.cancel();
    super.dispose();
  }

  Future<void> _save(Future<void> Function() operation) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await operation();
      final ok = await ThermostatGeofenceService().syncExitActions();
      if (!ok && mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Ayar saklandı; iOS konum hizmetine aktarılamadı. Konum iznini kontrol et.')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is StateError
                ? e.message.toString()
                : 'Ayar kaydedilemedi.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _radius(
      SettingsProvider s, String key, String title, double current) async {
    double value = current;
    final result = await showDialog<double>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, update) => AlertDialog(
                    title: Text(title),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('${value.round()} m',
                          style: Theme.of(ctx).textTheme.headlineSmall),
                      Slider(
                          value: value,
                          min: 50,
                          max: 2000,
                          divisions: 39,
                          label: '${value.round()} m',
                          onChanged: (v) => update(() => value = v)),
                      const Text(
                          'Konum yaklaşık ölçülür. iOS arka planda gecikmeli tetikleyebilir.')
                    ]),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Vazgeç')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, value),
                          child: const Text('Kaydet'))
                    ])));
    if (result != null && mounted)
      await _save(() => s.setAutomationRadius(key, result));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>();
    final owner = _owner;
    final enabled =
        s.geofenceEnabled && !s.isLoading && !_saving && owner != null;
    Widget radius(String key, String title, double value) => ListTile(
        title: Text(title),
        subtitle: Text('${value.round()} m'),
        trailing: const Icon(Icons.chevron_right),
        onTap: enabled ? () => _radius(s, key, title, value) : null);
    return Card(
        child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Konum otomasyonları',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold))),
              const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                      'Kombi ve ışıkların mesafeleri bağımsızdır. Çıkış mesafesi girişten küçük olamaz. '
                      'Ayar değiştirmek cihaz komutu göndermez. Manuel modda konum otomasyonu ısıtmayı açmaz.')),
              ExpansionTile(
                  initiallyExpanded: true,
                  title: const Text('Kombi'),
                  children: [
                    SwitchListTile(
                        title: const Text('Eve yaklaşınca aç'),
                        subtitle: const Text(
                            'Mevcut eve dönüş davranışı: 25 °C hedef.'),
                        value: s.entryHeating,
                        onChanged: enabled
                            ? (v) => _save(() => s.setEntryHeating(v))
                            : null),
                    radius(
                        'heatEntry', 'Kombi giriş mesafesi', s.heatEntryRadius),
                    SwitchListTile(
                        title: const Text('Evden uzaklaşınca kapat'),
                        value: s.exitHeating,
                        onChanged: enabled
                            ? (v) => _save(() => s.setExitHeating(v))
                            : null),
                    radius(
                        'heatExit', 'Kombi çıkış mesafesi', s.heatExitRadius),
                  ]),
              ExpansionTile(title: const Text('Işıklar'), children: [
                radius('lightEntry', 'Işık giriş mesafesi', s.lightEntryRadius),
                radius('lightExit', 'Işık çıkış mesafesi', s.lightExitRadius),
                if (owner == null)
                  const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Ampul seçmek için giriş yap.'))
                else
                  StreamBuilder<DatabaseEvent>(
                      key: ValueKey(owner),
                      stream: _lights,
                      builder: (ctx, snapshot) {
                        final raw = snapshot.data?.snapshot.value;
                        final lights = raw is Map
                            ? Map<String, dynamic>.from(raw)
                            : <String, dynamic>{};
                        final ids = <String>{
                          ...lights.keys,
                          ...s.entryLightIds,
                          ...s.exitLightIds
                        }.toList()
                          ..sort();
                        Widget selection(String id, bool entry) {
                          final config =
                              lights[id] is Map ? lights[id] as Map : const {};
                          final saved =
                              entry ? s.entryLightIPs : s.exitLightIPs;
                          final selected = saved.containsKey(id);
                          final changed = selected && saved[id] != config['ip'];
                          return CheckboxListTile(
                              dense: true,
                              title:
                                  Text(entry ? 'Girişte aç' : 'Çıkışta kapat'),
                              value: selected,
                              subtitle: changed
                                  ? const Text(
                                      'IP değişmiş; kaldırıp yeniden seç.')
                                  : null,
                              onChanged:
                                  enabled && (config.isNotEmpty || selected)
                                      ? (v) => _save(() => entry
                                          ? s.setEntryLightSelected(
                                              owner, id, v ?? false,
                                              ip: config['ip'] as String?)
                                          : s.setExitLightSelected(
                                              owner, id, v ?? false,
                                              ip: config['ip'] as String?))
                                      : null);
                        }

                        return Column(children: [
                          if (snapshot.hasError)
                            const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text(
                                    'Ampul listesi okunamadı; seçimlerin korunuyor.'))
                          else if (!snapshot.hasData)
                            const LinearProgressIndicator(),
                          if (snapshot.hasData && ids.isEmpty)
                            const Padding(
                                padding: EdgeInsets.all(16),
                                child:
                                    Text('Önce Evim ayarlarından ampul ekle.')),
                          for (final id in ids
                              .where((v) => RegExp(r'^lamp[1-8]$').hasMatch(v)))
                            ExpansionTile(
                                title: Text(lights[id] is Map
                                    ? (lights[id]['name'] as String? ?? id)
                                    : id),
                                children: [
                                  selection(id, true),
                                  selection(id, false)
                                ]),
                        ]);
                      }),
                const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Yalnız seçili ampuller kontrol edilir. '
                        'Giriş seçimleri başlangıçta boştur. Seçimler bu telefon ve kullanıcı hesabı içindir.')),
              ]),
              const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                      '50 m gibi küçük yarıçaplar kesin sınır değildir. '
                      'Konum doğruluğu, izinler ve iOS arka plan koşulları tetiklemeyi etkiler.')),
              if (!s.geofenceEnabled)
                const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Konum otomasyonu kapalı; seçimler saklanır.')),
            ])));
  }
}
