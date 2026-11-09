import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';

import '../providers/thermostat_provider.dart';
import '../models/heating_feedback.dart';
import '../widgets/room_overview.dart';
import '../widgets/bedroom_3d_card.dart';
import '../widgets/home_floor_plan.dart';
import '../widgets/home_pager.dart';
import '../models/home_plan.dart';
import '../models/wiz_command_feedback.dart';
import '../models/wiz_auto_retry.dart';
import '../services/home_plan_preferences.dart';
import '../services/morning_weather_notification_service.dart';

class WizLightsScreen extends StatefulWidget {
  const WizLightsScreen({super.key, this.embedded = false});
  final bool embedded;
  @override
  State<WizLightsScreen> createState() => WizLightsScreenState();
}

class WizLightsScreenState extends State<WizLightsScreen> {
  final _revision = ValueNotifier<int>(0);

  void _refresh(VoidCallback update) {
    if (!mounted) return;
    setState(update);
    _revision.value++;
  }

  String? _owner;
  String? _selectedRoom;
  String? _selectedFixture;
  Map<String, FixtureBinding> _bindings = {};
  final _planPreferences = HomePlanPreferences();
  bool _planReady = false;
  bool _savingPlan = false;
  DatabaseReference? _home;
  StreamSubscription<DatabaseEvent>? _homeSubscription;
  Map<String, dynamic> _homeData = {};
  bool _dataReady = false;
  bool _dataError = false;
  int _binding = 0;
  StreamSubscription<User?>? _auth;
  StreamSubscription<DatabaseEvent>? _offset;
  StreamSubscription<DatabaseEvent>? _connection;
  bool _connected = false;
  Timer? _clock;
  int _serverOffset = 0;
  bool _timeReady = false;
  final Set<String> _sending = {};
  final Map<String, int> _writeStarted = {};
  final Map<String, WizAutoRetry> _autoRetries = {};
  double _roomDrag = 0;
  int _clockTick = 0;

  @override
  void initState() {
    super.initState();
    _bindUser(FirebaseAuth.instance.currentUser);
    _auth = FirebaseAuth.instance.authStateChanges().listen(_bindUser);
    _offset = FirebaseDatabase.instance
        .ref('.info/serverTimeOffset')
        .onValue
        .listen((e) {
      if (!mounted) return;
      _refresh(() {
        _serverOffset = (e.snapshot.value as num?)?.toInt() ?? 0;
        _timeReady = e.snapshot.value is num;
      });
    });
    _connection =
        FirebaseDatabase.instance.ref('.info/connected').onValue.listen((e) {
      if (mounted) _refresh(() => _connected = e.snapshot.value == true);
    });
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      _clockTick++;
      _runAutoRetries();
      final commands = _map(_homeData['commands']);
      final reports = _map(_map(_homeData['status'])['lights']);
      final waiting = _sending.isNotEmpty ||
          commands.entries.any(
            (e) => _commandFeedback(
              e.key,
              _map(e.value),
              _map(reports[e.key]),
              false,
            ).pending,
          );
      if (mounted && (waiting || _clockTick % 5 == 0)) _refresh(() {});
    });
  }

  void _bindUser(User? user, {bool force = false}) {
    if (!force && _owner == user?.uid && _home != null) return;
    final binding = ++_binding;
    _homeSubscription?.cancel();
    _refresh(() {
      _owner = user?.uid;
      _home = user == null
          ? null
          : FirebaseDatabase.instance.ref('wizHomes/${user.uid}');
      _homeData = {};
      _dataReady = false;
      _dataError = false;
      _sending.clear();
      _writeStarted.clear();
      _autoRetries.clear();
      _selectedRoom = null;
      _selectedFixture = null;
      _bindings = {};
      _planReady = user == null;
      _savingPlan = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && binding == _binding)
        const RoomDetailNotification(false).dispatch(context);
    });
    if (user != null) _loadPlan(user.uid, binding);
    _homeSubscription = _home?.onValue.listen(
      (event) {
        if (!mounted || binding != _binding) return;
        _refresh(() {
          _homeData = _map(event.snapshot.value);
          _dataReady = true;
          _dataError = false;
        });
        _runAutoRetries();
      },
      onError: (Object error, StackTrace stack) {
        if (!mounted || binding != _binding) return;
        _refresh(() {
          _dataReady = true;
          _dataError = true;
        });
      },
    );
  }

  Future<void> _loadPlan(String owner, int generation) async {
    try {
      final loaded = await _planPreferences.load(owner);
      if (!mounted || generation != _binding || _owner != owner) return;
      _refresh(() {
        _bindings = loaded;
        _planReady = true;
      });
    } catch (_) {
      if (!mounted || generation != _binding) return;
      _refresh(() => _planReady = true);
      _message('Ev eşleştirmeleri okunamadı.');
    }
  }

  Future<void> _assignFixture(String fixture, String? lightId) async {
    final owner = _owner;
    if (owner == null || !_planReady || _savingPlan) return;
    final generation = _binding;
    final lights = _map(_map(_homeData['config'])['lights']);
    _refresh(() => _savingPlan = true);
    try {
      final next = HomePlanPreferences.assign(_bindings, fixture, lightId, lights);
      await _planPreferences.save(owner, next);
      if (!mounted || generation != _binding) return;
      _refresh(() => _bindings = next);
    } catch (_) {
    } finally {
      if (mounted && generation == _binding) _refresh(() => _savingPlan = false);
    }
  }

  void _enterRoom(String roomId) {
    _refresh(() {
      _selectedRoom = roomId;
      final lights = _map(_map(_homeData['config'])['lights']);
      _selectedFixture = HomePlan.fixturesFor(roomId)
          .where((f) => HomePlanPreferences.resolve(f.id, _bindings, lights) != null)
          .firstOrNull
          ?.id;
    });
    const RoomDetailNotification(true).dispatch(context);
  }

  void _leaveRoom() {
    _refresh(() {
      _selectedRoom = null;
      _selectedFixture = null;
    });
    const RoomDetailNotification(false).dispatch(context);
  }

  @override
  void dispose() {
    _binding++;
    _homeSubscription?.cancel();
    _auth?.cancel();
    _offset?.cancel();
    _connection?.cancel();
    _clock?.cancel();
    _revision.dispose();
    super.dispose();
  }

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
  
  int get _now => DateTime.now().millisecondsSinceEpoch + _serverOffset;
  
  // DÜZELTME: Zaman aşımı toleransı esnetildi (5 dakika geriye kadar geçerli kabul eder)
  bool _fresh(dynamic stamp, int limitMs) {
    if (stamp is! num) return false;
    final nowMs = DateTime.now().millisecondsSinceEpoch + (_timeReady ? _serverOffset : 0);
    final age = nowMs - stamp.toInt();
    return age >= -10000 && age <= 300000;
  }

  void _message(String text) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _send(String id, Map<String, dynamic> params) async {
    final home = _home;
    final uid = _owner;
    if (home == null || uid == null || _sending.contains(id)) return;
    final generation = _binding;
    _refresh(() {
      _sending.add(id);
      _writeStarted[id] = _now;
    });
    try {
      final ref = home.child('commands/$id');
      final commandId = ref.push().key!;
      final ip = _map(_map(_map(_homeData['config'])['lights'])[id])['ip'];
      if (ip is String && ip.isNotEmpty) {
        _autoRetries[id] = WizAutoRetry(commandId: commandId, params: params, ip: ip);
      }
      await ref.set({
        'id': commandId,
        'issuedAt': ServerValue.timestamp,
        'requestedAt': _now,
        'ttlMs': 60000,
        'params': params,
      });
    } catch (_) {
      if (mounted && generation == _binding) _autoRetries.remove(id);
    } finally {
      if (mounted && generation == _binding) {
        _refresh(() {
          _sending.remove(id);
          _writeStarted.remove(id);
        });
      }
    }
  }

  Future<void> _addLight(Map<String, dynamic> currentLights) async {
    final home = _home;
    if (home == null) return;
    final name = TextEditingController();
    final ip = TextEditingController();
    Map<String, String>? result;
    try {
      result = await showDialog<Map<String, String>>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('WiZ ampul ekle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Ad')),
              TextField(controller: ip, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'IP adresi')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
            FilledButton(
              onPressed: () => Navigator.pop(context, {'name': name.text.trim(), 'ip': ip.text.trim()}),
              child: const Text('Ekle'),
            ),
          ],
        ),
      );
    } finally {
      name.dispose();
      ip.dispose();
    }
    if (result == null || !mounted) return;
    final slot = List<String>.generate(8, (i) => 'lamp${i + 1}').firstWhere((id) => !currentLights.containsKey(id));
    await home.child('config/lights/$slot').set(result);
  }

  Future<void> _remove(String id, String name) async {
    final home = _home;
    if (home == null) return;
    await home.update({'config/lights/$id': null, 'commands/$id': null});
  }

  void openRooms() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          children: [
            for (final room in HomePlan.rooms)
              ListTile(
                title: Text(room.name),
                subtitle: Text(room.dimensions),
                onTap: () {
                  Navigator.pop(sheet);
                  _enterRoom(room.id);
                },
              ),
          ],
        ),
      ),
    );
  }

  void openSettings() => _openPanel('Ev ve ampul ayarları', _settingsBody);

  void _openControls(String id) => _openPanel(
        'Işık kontrolleri',
        () => _liveData((lights, reported, commands, bridgeOnline) {
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _lightCard(id, _map(lights[id]), _map(reported[id]), _map(commands[id]), bridgeOnline, allowRemove: false),
            ],
          );
        }),
      );

  void _openPanel(String title, Widget Function() content) {
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => RoomPanel(
        title: title,
        child: ValueListenableBuilder<int>(
          valueListenable: _revision,
          builder: (_, __, ___) => content(),
        ),
      ),
    );
  }

  Widget _liveData(Widget Function(Map<String, dynamic> lights, Map<String, dynamic> reported, Map<String, dynamic> commands, bool bridgeOnline) content) {
    if (_home == null) return const Center(child: Text('Giriş yapılmadı.'));
    if (_dataError) return const Center(child: Text('Veriler okunamadı.'));
    if (!_dataReady) return const Center(child: CircularProgressIndicator());
    final lights = _map(_map(_homeData['config'])['lights']);
    final status = _map(_homeData['status']);
    final bridgeOnline = _connected && _fresh(_map(status['bridge'])['lastSeen'], 300000);
    return content(lights, _map(status['lights']), _map(_homeData['commands']), bridgeOnline);
  }

  @override
  Widget build(BuildContext context) {
    final body = _liveData((l, r, c, b) => _roomOverview(l, r, c, b));
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: openRooms, icon: const Text('🏠', style: TextStyle(fontSize: 23))),
        title: const Text('Evim'),
        actions: [IconButton(onPressed: openSettings, icon: const Icon(Icons.tune))],
      ),
      body: SafeArea(child: body),
    );
  }

  Widget _settingsBody() => _liveData((lights, reported, commands, bridgeOnline) {
        final ids = lights.keys.toList()..sort();
        return RoomSettingsContent(
          connected: _connected,
          timeReady: _timeReady,
          bridgeOnline: bridgeOnline,
          owner: _owner ?? '',
          lights: {for (final id in ids) id: _map(lights[id])['name'] as String? ?? id},
          selectedLight: null,
          onSelected: (_) {},
          planAssignments: _assignmentControls(lights),
          onAdd: () => _addLight(lights),
          onCopy: () async {
            await Clipboard.setData(ClipboardData(text: _owner ?? ''));
            _message('Kullanıcı kimliği kopyalandı.');
          },
          controls: [
            // Sabah bildirimini test etme butonu eklendi
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Sabah Hava Durumu Bildirimi', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    const Text('Ankara hava durumuna göre hazırlanan sabah bildirmini anında test edin.'),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: () async {
                        // Kendi OpenWeatherMap API anahtarınızı buraya yazabilirsiniz veya boş bırakabilirsiniz
                        await MorningWeatherNotificationService.instance.sendTestNotificationNow(
                          owmApiKey: 'YOUR_OWM_API_KEY',
                        );
                        _message('Test bildirimi gönderildi!');
                      },
                      icon: const Icon(Icons.notifications_active, size: 18),
                      label: const Text('Sabah Bildirimini Şimdi Test Et'),
                    ),
                  ],
                ),
              ),
            ),
            for (final item in lights.entries)
              _lightCard(item.key, _map(item.value), _map(reported[item.key]), _map(commands[item.key]), bridgeOnline),
          ],
        );
      });

  Widget _assignmentControls(Map<String, dynamic> lights) {
    final ids = lights.keys.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Plandaki lambaları bağla', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final f in HomePlan.fixtures)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: DropdownButtonFormField<String>(
              value: HomePlanPreferences.resolve(f.id, _bindings, lights) ?? '',
              isExpanded: true,
              decoration: InputDecoration(labelText: f.name),
              items: [
                const DropdownMenuItem(value: '', child: Text('Eşleştirilmedi')),
                for (final id in ids)
                  DropdownMenuItem(value: id, child: Text('${_map(lights[id])['name'] ?? id}')),
              ],
              onChanged: (id) => _assignFixture(f.id, id == '' ? null : id),
            ),
          ),
      ],
    );
  }

  bool get _retrySessionReady => mounted && _owner != null && _connected && _timeReady && _dataReady;

  bool _retryDeviceReady(String id, WizAutoRetry attempt) {
    final config = _map(_map(_map(_homeData['config'])['lights'])[id]);
    final status = _map(_homeData['status']);
    final report = _map(_map(status['lights'])[id]);
    return _retrySessionReady && config['ip'] == attempt.ip;
  }

  void _runAutoRetries() {
    if (!_retrySessionReady) return;
    final commands = _map(_homeData['commands']);
    final reports = _map(_map(_homeData['status'])['lights']);
    for (final entry in _autoRetries.entries.toList()) {
      final id = entry.key, attempt = entry.value;
      if (_sending.contains(id) || !_retryDeviceReady(id, attempt)) continue;
      final report = _map(reports[id]);
      final current = report['online'] == true && _fresh(report['reportedAt'], 300000);
      if (!attempt.eligible(command: _map(commands[id]), report: report, now: _now, reportIsCurrent: current)) continue;
      attempt.consumed = true;
      _refresh(() {
        _sending.add(id);
        _writeStarted[id] = _now;
      });
      unawaited(_retryAutomatically(id, attempt));
    }
  }

  Future<void> _retryAutomatically(String id, WizAutoRetry attempt) async {
    final home = _home;
    if (home == null) return;
    final ref = home.child('commands/$id');
    try {
      await ref.runTransaction((raw) {
        final replacement = attempt.replacement(_map(raw), newId: ref.push().key!, now: _now);
        return replacement == null ? Transaction.abort() : Transaction.success(replacement);
      });
    } finally {
      if (mounted) {
        _refresh(() {
          _sending.remove(id);
          _writeStarted.remove(id);
        });
      }
    }
  }

  WizCommandFeedback _commandFeedback(String id, Map<String, dynamic> command, Map<String, dynamic> report, bool current) {
    final attempt = _autoRetries[id];
    return WizCommandFeedback.evaluate(
      command: command,
      report: report,
      now: _now,
      reportIsCurrent: current,
      writing: _sending.contains(id),
      writeStartedAt: _writeStarted[id],
    );
  }

  void _retryCommand(String id) {
    final command = _map(_map(_homeData['commands'])[id]);
    final report = _map(_map(_map(_homeData['status'])['lights'])[id]);
    final feedback = _commandFeedback(id, command, report, true);
    if (feedback.retryable && !_sending.contains(id)) _send(id, feedback.params);
  }

  FixtureState _fixtureState(String fixture, Map<String, dynamic> lights, Map<String, dynamic> reported, Map<String, dynamic> commands, bool bridgeOnline) {
    final id = HomePlanPreferences.resolve(fixture, _bindings, lights);
    if (id == null) return const FixtureState();
    final report = _map(reported[id]);
    final fresh = bridgeOnline && report['online'] == true && _fresh(report['reportedAt'], 300000);
    final bool? on = fresh && report['state'] is bool ? report['state'] as bool : null;
    return FixtureState(
      assigned: true,
      on: on,
      pending: false,
      retryable: false,
      feedback: null,
      controllable: true,
    );
  }

  void _togglePlanFixture(String fixture) {
    final lights = _map(_map(_homeData['config'])['lights']);
    final status = _map(_homeData['status']);
    final bridge = _connected && _fresh(_map(status['bridge'])['lastSeen'], 300000);
    final state = _fixtureState(fixture, lights, _map(status['lights']), _map(_homeData['commands']), bridge);
    final id = HomePlanPreferences.resolve(fixture, _bindings, lights);
    if (id != null) {
      if (state.on != null) {
        _send(id, {'state': !state.on!});
      } else {
        _send(id, {'state': true});
      }
    }
  }

  void _controlsForFixture(String fixture) {
    final lights = _map(_map(_homeData['config'])['lights']);
    final id = HomePlanPreferences.resolve(fixture, _bindings, lights);
    if (id != null) _openControls(id);
  }

  bool _isBedroomRoom(String rIdStr, String rNameStr) {
    final rId = rIdStr.toLowerCase();
    final rName = rNameStr.toLowerCase();
    return rId.contains('bed') || rId.contains('yatak') || rName.contains('yatak');
  }

  Widget _buildBedroom3DOverview({
    required String roomName,
    required String dimensions,
    required String area,
    required bool hasSensor,
    required String? selectedType,
    required String? fixture,
    required String? id,
    required FixtureState state,
    required bool enabled,
    required Map<String, dynamic> lights,
    required bool hasReading,
    required double? temperature,
    required double? humidity,
    required bool isHeating,
  }) {
    final sortedIds = lights.keys.toList()..sort();
    final selectableBulbs = <SelectableBedroomBulb>[
      for (final lightId in sortedIds)
        SelectableBedroomBulb(
          id: lightId,
          name: '${_map(lights[lightId])['name'] ?? lightId} ($lightId)',
          ip: _map(lights[lightId])['ip']?.toString(),
        ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text('$dimensions${area.isNotEmpty ? ' · $area' : ''} · 3B Etkileşimli Oda', style: Theme.of(context).textTheme.bodyMedium),
        if (hasSensor) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.thermostat_outlined, size: 22),
              const SizedBox(width: 6),
              Text(hasReading && temperature != null ? '${temperature.toStringAsFixed(1)} °C' : '-- °C', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
        ],
        const SizedBox(height: 14),
        Bedroom3DCard(
          height: 340,
          isHeating: isHeating,
          initialCeilingOn: state.on ?? true,
          availableBulbs: selectableBulbs,
          onTriggerBulb: (bulbId, isOn, fixtureType) async {
            await _send(bulbId, {'state': isOn});
          },
        ),
      ],
    );
  }

  Widget _roomOverview(Map<String, dynamic> lights, Map<String, dynamic> reported, Map<String, dynamic> commands, bool bridgeOnline) {
    final roomId = _selectedRoom;
    final reduced = MediaQuery.of(context).disableAnimations;
    final states = {
      for (final f in HomePlan.fixtures)
        f.id: _fixtureState(f.id, lights, reported, commands, bridgeOnline),
    };
    final thermostat = context.watch<ThermostatProvider>();
    Widget child;
    if (roomId == null) {
      child = HomeFloorPlan(
        key: const ValueKey('home-floor-plan'),
        states: states,
        onRoom: _enterRoom,
        onLampTap: _togglePlanFixture,
        onLampControls: _controlsForFixture,
        onSetup: openSettings,
      );
    } else {
      final room = HomePlan.room(roomId),
          fixtures = HomePlan.fixturesFor(roomId)
              .where((f) => HomePlanPreferences.resolve(f.id, _bindings, lights) != null)
              .toList();
      final fixture = fixtures.any((f) => f.id == _selectedFixture) ? _selectedFixture : fixtures.firstOrNull?.id;
      final selected = fixtures.where((f) => f.id == fixture).firstOrNull;
      final id = fixture == null ? null : HomePlanPreferences.resolve(fixture, _bindings, lights);
      final state = states[fixture] ?? const FixtureState();
      final sensor = thermostat.thermostat;
      final hasReading = room.sensor && sensor != null && !thermostat.isLoading && thermostat.error == null;
      final isBedroom = _isBedroomRoom(room.id, room.name);
      final isHeating = thermostat.heatingFeedback.relay == RelayState.on;

      child = Column(
        key: ValueKey('detail-$roomId'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 16, 0),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              children: [
                TextButton.icon(
                  onPressed: _leaveRoom,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Ev planı'),
                ),
                Text(room.name, style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          ),
          Expanded(
            child: isBedroom
                ? _buildBedroom3DOverview(
                    roomName: room.name,
                    dimensions: room.dimensions,
                    area: room.area,
                    hasSensor: room.sensor,
                    selectedType: selected?.type,
                    fixture: fixture,
                    id: id,
                    state: state,
                    enabled: true,
                    lights: lights,
                    hasReading: hasReading,
                    temperature: hasReading ? sensor.currentTemperature : null,
                    humidity: hasReading ? sensor.humidity.toDouble() : null,
                    isHeating: isHeating,
                  )
                : RoomOverview(
                    roomName: room.name,
                    dimensions: room.dimensions,
                    area: room.area,
                    roomWidth: room.width,
                    roomDepth: room.depth,
                    showSensor: room.sensor,
                    showLamp: id != null,
                    floorLamp: selected?.floor ?? false,
                    isLightOn: state.on,
                    ambientOn: state.on,
                    onToggle: fixture != null ? () => _togglePlanFixture(fixture) : null,
                    onControls: id != null ? () => _openControls(id) : null,
                    onSetup: openSettings,
                    temperature: hasReading ? sensor.currentTemperature : null,
                    humidity: hasReading ? sensor.humidity.toDouble() : null,
                  ),
          ),
        ],
      );
    }
    return AnimatedSwitcher(
      duration: Duration(milliseconds: reduced ? 0 : 240),
      child: child,
    );
  }

  Widget _lightCard(String id, Map<String, dynamic> config, Map<String, dynamic> report, Map<String, dynamic> command, bool bridgeOnline, {bool allowRemove = true}) {
    final name = config['name'] as String? ?? 'Ampul';
    final fresh = bridgeOnline && report['online'] == true && _fresh(report['reportedAt'], 300000);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(fresh && report['state'] == true ? Icons.lightbulb : Icons.lightbulb_outline),
                const SizedBox(width: 8),
                Expanded(child: Text(name, style: Theme.of(context).textTheme.titleMedium)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: FilledButton(onPressed: () => _send(id, {'state': true}), child: const Text('Aç'))),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton(onPressed: () => _send(id, {'state': false}), child: const Text('Kapat'))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
