import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import '../providers/thermostat_provider.dart';
import '../widgets/room_overview.dart';

/// WiZ commands go through an authenticated ESP bridge. No local-network
/// permission, bulb credentials or administrative database secret in this UI.
class WizLightsScreen extends StatefulWidget {
  const WizLightsScreen({super.key});
  @override
  State<WizLightsScreen> createState() => _WizLightsScreenState();
}

class _WizLightsScreenState extends State<WizLightsScreen> {
  String? _owner;
  String? _roomLightId;
  DatabaseReference? _home;
  Stream<DatabaseEvent>? _events;
  StreamSubscription<User?>? _auth;
  StreamSubscription<DatabaseEvent>? _offset;
  StreamSubscription<DatabaseEvent>? _connection;
  bool _connected = false;
  Timer? _clock;
  int _serverOffset = 0;
  bool _timeReady = false;
  final Set<String> _sending = {};

  @override
  void initState() {
    super.initState();
    _bindUser(FirebaseAuth.instance.currentUser);
    _auth = FirebaseAuth.instance.authStateChanges().listen(_bindUser);
    _offset = FirebaseDatabase.instance.ref('.info/serverTimeOffset').onValue.listen((e) {
      if (!mounted) return;
      setState(() {
        _serverOffset = (e.snapshot.value as num?)?.toInt() ?? 0;
        _timeReady = e.snapshot.value is num;
      });
    });
    _connection = FirebaseDatabase.instance.ref('.info/connected').onValue.listen((e) {
      if (mounted) setState(() => _connected = e.snapshot.value == true);
    });
    _clock = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  void _bindUser(User? user) {
    if (_owner == user?.uid && _home != null) return;
    void apply() {
      _owner = user?.uid;
      _home = user == null ? null : FirebaseDatabase.instance.ref('wizHomes/${user.uid}');
      _events = _home?.onValue;
      _sending.clear();
      _roomLightId = null;
    }
    if (mounted) { setState(apply); } else { apply(); }
  }

  @override
  void dispose() {
    _auth?.cancel();
    _offset?.cancel();
    _connection?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
  int get _now => DateTime.now().millisecondsSinceEpoch + _serverOffset;
  bool _fresh(dynamic stamp, int limitMs) {
    if (!_timeReady || stamp is! num) return false;
    final age = _now - stamp.toInt();
    return age >= -5000 && age <= limitMs;
  }
  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _send(String id, Map<String, dynamic> params) async {
    final home = _home;
    final uid = _owner;
    if (home == null || uid == null || _sending.contains(id)) return;
    if (FirebaseAuth.instance.currentUser?.uid != uid) return;
    if (!_connected || !_timeReady) { _message('Firebase bağlantısı hazır değil.'); return; }
    setState(() => _sending.add(id));
    try {
      final ref = home.child('commands/$id');
      final commandId = ref.push().key!;
      // These are absolute, idempotent values, never toggle commands.
      await ref.set({
        'id': commandId,
        'issuedAt': ServerValue.timestamp,
        'requestedAt': _now,
        'ttlMs': 60000,
        'params': params,
      });
      _message('Komut gönderildi. Ampul yanıtı bekleniyor.');
    } catch (_) {
      _message('Komut gönderilemedi. İnterneti ve Firebase izinlerini kontrol et.');
    } finally {
      if (mounted) setState(() => _sending.remove(id));
    }
  }

  Future<void> _addLight(Map<String, dynamic> currentLights) async {
    final home = _home;
    final owner = _owner;
    if (home == null || owner == null) return;
    final currentCount = currentLights.length;
    if (currentCount >= 8) { _message('Bu sürüm en fazla 8 ampul destekliyor.'); return; }
    final name = TextEditingController();
    final ip = TextEditingController();
    String? error;
    Map<String, String>? result;
    try {
      result = await showDialog<Map<String, String>>(
        context: context,
        builder: (context) => StatefulBuilder(builder: (context, update) => AlertDialog(
          title: const Text('WiZ ampul ekle'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, maxLength: 40, decoration: const InputDecoration(labelText: 'Ad', hintText: 'Salon')),
            TextField(controller: ip, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Ampulün yerel IP adresi', hintText: '192.168.1.50')),
            const SizedBox(height: 12),
            const Text('IP adresini WiZ cihaz bilgilerinden veya modemden bul. Modemde bu IP için DHCP rezervasyonu önerilir.'),
            if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
            FilledButton(onPressed: () {
              final parts = ip.text.trim().split('.');
              final valid = parts.length == 4 && parts.every((p) =>
                RegExp(r'^\d{1,3}$').hasMatch(p) && (int.tryParse(p) ?? 999) <= 255);
              if (name.text.trim().isEmpty || !valid) {
                update(() => error = 'Bir ad ve geçerli IPv4 adresi gir.'); return;
              }
              Navigator.pop(context, {'name': name.text.trim(), 'ip': parts.map((p) => int.parse(p)).join('.')});
            }, child: const Text('Ekle')),
          ],
        )),
      );
    } finally {
      // Let the dialog route finish its dismissal animation before disposal.
      Future<void>.delayed(const Duration(milliseconds: 400), () { name.dispose(); ip.dispose(); });
    }
    if (result == null || !mounted || owner != _owner) return;
    try {
      final slot = List<String>.generate(8, (i) => 'lamp${i + 1}')
          .firstWhere((id) => !currentLights.containsKey(id));
      final saved = await home.child('config/lights/$slot').runTransaction((current) {
        if (current != null) return Transaction.abort();
        return Transaction.success(result);
      }, applyLocally: false);
      if (!saved.committed) _message('Bu alan başka cihazdan dolduruldu. Tekrar dene.');
    } catch (_) { _message('Ampul eklenemedi. Firebase izinlerini kontrol et.'); }
  }

  Future<void> _remove(String id, String name) async {
    final home = _home;
    final owner = _owner;
    if (home == null || owner == null) return;
    final confirmed = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Ampul kaldırılsın mı?'), content: Text(name), actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Kaldır')),
      ],
    ));
    if (confirmed != true || !mounted || owner != _owner) return;
    try { await home.update({'config/lights/$id': null, 'commands/$id': null}); }
    catch (_) { _message('Ampul kaldırılamadı.'); }
  }

  @override
  Widget build(BuildContext context) {
    final home = _home;
    return Scaffold(
      appBar: AppBar(title: const Text('Işıklar · KD')),
      body: home == null
        ? const Center(child: Text('Önce uygulamada giriş yap.'))
        : StreamBuilder<DatabaseEvent>(
            key: ValueKey(_owner), stream: _events,
            builder: (context, event) {
              if (event.hasError) return const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Işık verileri okunamadı. Firebase WiZ kurallarını ve bağlantıyı kontrol et.'),
              ));
              if (!event.hasData) return const Center(child: CircularProgressIndicator());
              final data = _map(event.data!.snapshot.value);
              final lights = _map(_map(data['config'])['lights']);
              final status = _map(data['status']);
              final reported = _map(status['lights']);
              final commands = _map(data['commands']);
              final bridgeOnline = _fresh(_map(status['bridge'])['lastSeen'], 90000);
              return ListView(padding: const EdgeInsets.all(16), children: [
                _roomOverview(lights, reported, commands, bridgeOnline),
                Card(child: ListTile(
                  leading: Icon(bridgeOnline ? Icons.hub : Icons.cloud_off),
                  title: Text(!_connected ? 'Telefonun Firebase bağlantısı yok'
                    : bridgeOnline ? 'ESP köprüsü yanıt veriyor' : 'ESP köprüsünden güncel yanıt yok'),
                  subtitle: const Text('Komutlar Firebase üzerinden evdeki ESP’ye iletilir.'),
                )),
                ExpansionTile(title: const Text('ESP kurulumu için kullanıcı kimliği'), children: [
                  Padding(padding: const EdgeInsets.all(12), child: SelectableText(_owner ?? '')),
                  TextButton.icon(onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _owner ?? ''));
                    _message('Kullanıcı kimliği kopyalandı.');
                  }, icon: const Icon(Icons.copy), label: const Text('Kopyala')),
                ]),
                const SizedBox(height: 8),
                FilledButton.icon(onPressed: () => _addLight(lights),
                  icon: const Icon(Icons.add), label: const Text('Ampul ekle')),
                const SizedBox(height: 12),
                if (lights.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text(
                  'WiZ uygulamasında yerel iletişime izin ver. Sonra ampulü adı ve yerel IP adresiyle ekle.')),
                for (final item in lights.entries)
                  _lightCard(item.key, _map(item.value), _map(reported[item.key]),
                    _map(commands[item.key]), bridgeOnline),
              ]);
            },
          ),
    );
  }

  Widget _roomOverview(Map<String, dynamic> lights, Map<String, dynamic> reported,
      Map<String, dynamic> commands, bool bridgeOnline) {
    final ids = lights.keys.toList()..sort();
    final id = lights.containsKey(_roomLightId)
        ? _roomLightId : ids.isEmpty ? null : ids.first;
    final config = _map(lights[id]);
    final report = _map(reported[id]);
    final command = _map(commands[id]);
    final fresh = _connected && bridgeOnline && report['online'] == true
        && report['ip'] == config['ip'] && _fresh(report['reportedAt'], 90000);
    final bool? on = fresh && report['state'] is bool ? report['state'] as bool : null;
    final applied = command['id'] != null && report['lastCommandId'] == command['id'];
    final pending = id != null && (_sending.contains(id)
        || (command['id'] != null && !applied && _fresh(command['issuedAt'], 60000)));
    final enabled = id != null && on != null && _connected && _timeReady
        && bridgeOnline && !pending;
    final thermostat = context.watch<ThermostatProvider>();
    final sensor = thermostat.thermostat;
    final hasReading = sensor != null && !thermostat.isLoading && thermostat.error == null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (ids.length > 1) Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          key: ValueKey(id),
          value: id,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Odada gösterilen ampul'),
          items: [for (final key in ids) DropdownMenuItem(
            value: key,
            child: Text(_map(lights[key])['name'] as String? ?? key,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          )],
          onChanged: (value) => setState(() => _roomLightId = value),
        ),
      ),
      RoomOverview(
        isLightOn: on,
        pending: pending,
        lightName: id == null ? null : config['name'] as String? ?? 'Ampul',
        onToggle: enabled ? () => _send(id, {'state': !on}) : null,
        temperature: hasReading && sensor.currentTemperature.isFinite
            ? sensor.currentTemperature : null,
        humidity: hasReading && sensor.humidity.isFinite ? sensor.humidity : null,
      ),
    ]);
  }

  Widget _lightCard(String id, Map<String, dynamic> config, Map<String, dynamic> report,
      Map<String, dynamic> command, bool bridgeOnline) {
    final name = config['name'] as String? ?? 'Ampul';
    final fresh = bridgeOnline && report['online'] == true
        && report['ip'] == config['ip'] && _fresh(report['reportedAt'], 90000);
    final knownState = fresh && report['state'] is bool;
    final applied = command['id'] != null && report['lastCommandId'] == command['id'];
    final pending = command['id'] != null && !applied && _fresh(command['issuedAt'], 60000);
    final text = pending ? 'Ampul yanıtı bekleniyor'
      : applied && report['commandStatus'] == 'expired' ? 'Komutun süresi doldu'
      : applied && report['commandStatus'] == 'no_response' ? 'Komuta yanıt alınamadı'
      : !fresh ? 'Güncel ampul yanıtı yok'
      : knownState ? (report['state'] == true ? 'Ampul bildirimi: Açık' : 'Ampul bildirimi: Kapalı')
      : 'Durum bilinmiyor';
    final enabled = _connected && _timeReady && bridgeOnline && !_sending.contains(id) && !pending;
    final brightness = report['dimming'] is num
      ? (report['dimming'] as num).toDouble().clamp(10.0, 100.0).toDouble() : 50.0;
    return Card(margin: const EdgeInsets.only(bottom: 12), child: Padding(
      padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(knownState && report['state'] == true ? Icons.lightbulb : Icons.lightbulb_outline),
          const SizedBox(width: 8), Expanded(child: Text(name, style: Theme.of(context).textTheme.titleMedium)),
          IconButton(onPressed: () => _remove(id, name), icon: const Icon(Icons.delete_outline), tooltip: 'Ampulü kaldır'),
        ]),
        Text(text),
        Text(config['ip'] as String? ?? '', style: Theme.of(context).textTheme.bodySmall),
        if (report['commandStatus'] == 'rejected') const Text('ESP komutu reddetti; cihaz ayarını kontrol et.'),
        if (fresh && report['dimming'] is num) Text('Bildirilen parlaklık: %${(report['dimming'] as num).round()}'),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: FilledButton(onPressed: enabled ? () => _send(id, {'state': true}) : null, child: const Text('Aç'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton(onPressed: enabled ? () => _send(id, {'state': false}) : null, child: const Text('Kapat'))),
        ]),
        const SizedBox(height: 8),
        _BrightnessControl(key: ValueKey('$id:${report['reportedAt']}'), value: brightness,
          enabled: enabled, onCommit: (v) => _send(id, {'state': true, 'dimming': v.round()})),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final preset in <String, Map<String, dynamic>>{
            'Sıcak beyaz': {'state': true, 'temp': 2700},
            'Soğuk beyaz': {'state': true, 'temp': 6500},
            'Kırmızı': {'state': true, 'r': 255, 'g': 0, 'b': 0},
            'Yeşil': {'state': true, 'r': 0, 'g': 255, 'b': 0},
            'Mavi': {'state': true, 'r': 0, 'g': 0, 'b': 255},
          }.entries)
            OutlinedButton(onPressed: enabled ? () => _send(id, preset.value) : null, child: Text(preset.key)),
        ]),
      ]),
    ));
  }
}

class _BrightnessControl extends StatefulWidget {
  const _BrightnessControl({super.key, required this.value, required this.enabled, required this.onCommit});
  final double value;
  final bool enabled;
  final ValueChanged<double> onCommit;
  @override
  State<_BrightnessControl> createState() => _BrightnessControlState();
}
class _BrightnessControlState extends State<_BrightnessControl> {
  late double _value;
  @override
  void initState() { super.initState(); _value = widget.value; }
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('Parlaklık: %${_value.round()}'),
    Slider(value: _value, min: 10, max: 100, divisions: 90,
      onChanged: widget.enabled ? (v) => setState(() => _value = v) : null,
      onChangeEnd: widget.enabled ? widget.onCommit : null),
  ]);
}
