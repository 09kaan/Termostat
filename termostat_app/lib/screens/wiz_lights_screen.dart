import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';

import '../providers/thermostat_provider.dart';
import '../widgets/room_overview.dart';
import '../widgets/home_floor_plan.dart';
import '../widgets/home_pager.dart';
import '../models/home_plan.dart';
import '../models/wiz_command_feedback.dart';
import '../models/wiz_auto_retry.dart';
import '../services/home_plan_preferences.dart';

/// WiZ commands go through an authenticated ESP bridge. No local-network
/// permission, bulb credentials or administrative database secret in this UI.
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
    // Native Firebase onValue is a single-subscription stream. Subscribe ONCE
    // and share the last snapshot with the room and any number of panels.
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
      _message(
        'Ev eşleştirmeleri okunamadı. Ayarlardan tekrar bağlayabilirsin.',
      );
    }
  }

  Future<void> _assignFixture(String fixture, String? lightId) async {
    final owner = _owner;
    if (owner == null ||
        !_planReady ||
        _savingPlan ||
        FirebaseAuth.instance.currentUser?.uid != owner) return;
    final generation = _binding;
    final lights = _map(_map(_homeData['config'])['lights']);
    _refresh(() => _savingPlan = true);
    try {
      final next = HomePlanPreferences.assign(
        _bindings,
        fixture,
        lightId,
        lights,
      );
      await _planPreferences.save(owner, next);
      if (!mounted || generation != _binding || _owner != owner) return;
      _refresh(() => _bindings = next);
    } catch (_) {
      if (mounted && generation == _binding)
        _message('Eşleştirme kaydedilemedi. Tekrar dene.');
    } finally {
      if (mounted && generation == _binding)
        _refresh(() => _savingPlan = false);
    }
  }

  void _enterRoom(String roomId) {
    _refresh(() {
      _selectedRoom = roomId;
      final lights = _map(_map(_homeData['config'])['lights']);
      _selectedFixture = HomePlan.fixturesFor(roomId)
          .where(
            (f) => HomePlanPreferences.resolve(f.id, _bindings, lights) != null,
          )
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
  bool _fresh(dynamic stamp, int limitMs) {
    if (!_timeReady || stamp is! num) return false;
    final age = _now - stamp.toInt();
    return age >= -5000 && age <= limitMs;
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
    if (FirebaseAuth.instance.currentUser?.uid != uid) return;
    if (!_connected || !_timeReady) {
      _message('Firebase bağlantısı hazır değil.');
      return;
    }
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
        _autoRetries[id] = WizAutoRetry(
          commandId: commandId,
          params: params,
          ip: ip,
        );
      }
      // These are absolute, idempotent values, never toggle commands.
      await ref.set({
        'id': commandId,
        'issuedAt': ServerValue.timestamp,
        'requestedAt': _now,
        'ttlMs': 60000,
        'params': params,
      });
      // The inline state gives immediate feedback; no queued success snackbar.
    } catch (_) {
      if (mounted && generation == _binding) _autoRetries.remove(id);
      if (mounted && generation == _binding)
        _message(
          'Komut gönderilemedi. İnterneti ve Firebase izinlerini kontrol et.',
        );
    } finally {
      if (mounted && generation == _binding)
        _refresh(() {
          _sending.remove(id);
          _writeStarted.remove(id);
        });
    }
  }

  Future<void> _addLight(Map<String, dynamic> currentLights) async {
    final home = _home;
    final owner = _owner;
    if (home == null || owner == null) return;
    final currentCount = currentLights.length;
    if (currentCount >= 8) {
      _message('Bu sürüm en fazla 8 ampul destekliyor.');
      return;
    }
    final name = TextEditingController();
    final ip = TextEditingController();
    String? error;
    Map<String, String>? result;
    try {
      result = await showDialog<Map<String, String>>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('WiZ ampul ekle'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    maxLength: 40,
                    decoration: const InputDecoration(
                      labelText: 'Ad',
                      hintText: 'Salon',
                    ),
                  ),
                  TextField(
                    controller: ip,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Ampulün yerel IP adresi',
                      hintText: '192.168.1.50',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'IP adresini WiZ cihaz bilgilerinden veya modemden bul. Modemde bu IP için DHCP rezervasyonu önerilir.',
                  ),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () {
                  final parts = ip.text.trim().split('.');
                  final valid = parts.length == 4 &&
                      parts.every(
                        (p) =>
                            RegExp(r'^\d{1,3}$').hasMatch(p) &&
                            (int.tryParse(p) ?? 999) <= 255,
                      );
                  if (name.text.trim().isEmpty || !valid) {
                    update(() => error = 'Bir ad ve geçerli IPv4 adresi gir.');
                    return;
                  }
                  Navigator.pop(context, {
                    'name': name.text.trim(),
                    'ip': parts.map((p) => int.parse(p)).join('.'),
                  });
                },
                child: const Text('Ekle'),
              ),
            ],
          ),
        ),
      );
    } finally {
      // Let the dialog route finish its dismissal animation before disposal.
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        name.dispose();
        ip.dispose();
      });
    }
    if (result == null || !mounted || owner != _owner) return;
    try {
      final slot = List<String>.generate(
        8,
        (i) => 'lamp${i + 1}',
      ).firstWhere((id) => !currentLights.containsKey(id));
      final saved = await home.child('config/lights/$slot').runTransaction((
        current,
      ) {
        if (current != null) return Transaction.abort();
        return Transaction.success(result);
      }, applyLocally: false);
      if (!saved.committed)
        _message('Bu alan başka cihazdan dolduruldu. Tekrar dene.');
    } catch (_) {
      _message('Ampul eklenemedi. Firebase izinlerini kontrol et.');
    }
  }

  Future<void> _remove(String id, String name) async {
    final home = _home;
    final owner = _owner;
    if (home == null || owner == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Ampul kaldırılsın mı?'),
        content: Text(name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Kaldır'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || owner != _owner) return;
    try {
      await home.update({'config/lights/$id': null, 'commands/$id': null});
    } catch (_) {
      _message('Ampul kaldırılamadı.');
    }
  }

  /// The shared main header calls this; no setup clutter stays on the room.
  void openRooms() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: .65,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  'Odalar',
                  style: Theme.of(sheet).textTheme.titleLarge,
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final room in HomePlan.rooms)
                      ListTile(
                        key: ValueKey('room-link-${room.id}'),
                        leading: const Icon(Icons.meeting_room_outlined),
                        title: Text(room.name),
                        subtitle: Text(room.dimensions),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.pop(sheet);
                          _enterRoom(room.id);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void openSettings() => _openPanel('Ev ve ampul ayarları', _settingsBody);

  void _openControls(String id) => _openPanel(
        'Işık kontrolleri',
        () => _liveData((lights, reported, commands, bridgeOnline) {
          if (!lights.containsKey(id)) {
            return const Center(child: Text('Bu ampul artık kayıtlı değil.'));
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              BridgeConnectionCard(
                connected: _connected,
                timeReady: _timeReady,
                bridgeOnline: bridgeOnline,
              ),
              const SizedBox(height: 16),
              _lightCard(
                id,
                _map(lights[id]),
                _map(reported[id]),
                _map(commands[id]),
                bridgeOnline,
                allowRemove: false,
              ),
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
          builder: (_, revision, child) => content(),
        ),
      ),
    );
  }

  Widget _liveData(
    Widget Function(
      Map<String, dynamic> lights,
      Map<String, dynamic> reported,
      Map<String, dynamic> commands,
      bool bridgeOnline,
    ) content,
  ) {
    if (_home == null)
      return const Center(child: Text('Önce uygulamada giriş yap.'));
    if (_dataError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Işık verileri okunamadı. Firebase izinlerini ve internet bağlantısını kontrol et.',
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () =>
                    _bindUser(FirebaseAuth.instance.currentUser, force: true),
                child: const Text('Yeniden dene'),
              ),
            ],
          ),
        ),
      );
    }
    if (!_dataReady) return const Center(child: CircularProgressIndicator());
    final lights = _map(_map(_homeData['config'])['lights']);
    final status = _map(_homeData['status']);
    final bridgeOnline =
        _connected && _fresh(_map(status['bridge'])['lastSeen'], 90000);
    return content(
      lights,
      _map(status['lights']),
      _map(_homeData['commands']),
      bridgeOnline,
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _liveData(
      (lights, reported, commands, bridgeOnline) =>
          _roomOverview(lights, reported, commands, bridgeOnline),
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Odalar',
          onPressed: openRooms,
          icon: const Text('🏠', style: TextStyle(fontSize: 23)),
        ),
        title: const Text('Evim'),
        actions: [
          IconButton(
            onPressed: openSettings,
            tooltip: 'Ev ve ampul ayarları',
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      body: SafeArea(child: body),
    );
  }

  Widget _settingsBody() =>
      _liveData((lights, reported, commands, bridgeOnline) {
        final ids = lights.keys.toList()..sort();
        return RoomSettingsContent(
          connected: _connected,
          timeReady: _timeReady,
          bridgeOnline: bridgeOnline,
          owner: _owner ?? '',
          lights: {
            for (final id in ids) id: _map(lights[id])['name'] as String? ?? id,
          },
          selectedLight: null,
          onSelected: (_) {},
          planAssignments: _assignmentControls(lights),
          onAdd: () => _addLight(lights),
          onCopy: () async {
            await Clipboard.setData(ClipboardData(text: _owner ?? ''));
            _message('Kullanıcı kimliği kopyalandı.');
          },
          controls: [
            for (final item in lights.entries)
              _lightCard(
                item.key,
                _map(item.value),
                _map(reported[item.key]),
                _map(commands[item.key]),
                bridgeOnline,
              ),
          ],
        );
      });

  Widget _assignmentControls(Map<String, dynamic> lights) {
    final ids = lights.keys.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Plandaki lambaları bağla',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Her konumu kendi ampulüne bağla. Eşleştirme bu cihazda, hesabına özel saklanır; komut göndermez. Aynı ampul yalnız bir konumda olabilir.',
        ),
        if (!_planReady || _savingPlan)
          const Padding(
            padding: EdgeInsets.all(8),
            child: LinearProgressIndicator(),
          ),
        for (final f in HomePlan.fixtures)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: DropdownButtonFormField<String>(
              key: ValueKey(
                'assign-${f.id}-${HomePlanPreferences.resolve(f.id, _bindings, lights) ?? ''}',
              ),
              value: HomePlanPreferences.resolve(f.id, _bindings, lights) ?? '',
              isExpanded: true,
              decoration: InputDecoration(
                labelText: f.name,
                helperText: _bindings.containsKey(f.id) &&
                        HomePlanPreferences.resolve(f.id, _bindings, lights) ==
                            null
                    ? 'Ampul/IP değişti. Yeniden eşleştir.'
                    : null,
              ),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('Eşleştirilmedi'),
                ),
                for (final id in ids)
                  DropdownMenuItem(
                    value: id,
                    child: Text(
                      '${_map(lights[id])['name'] ?? id} · $id',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: !_planReady || _savingPlan
                  ? null
                  : (id) => _assignFixture(f.id, id == '' ? null : id),
            ),
          ),
        const SizedBox(height: 12),
        const Text(
          'Başka konuma bağlı bir ampul seçersen önceki konumdan taşınır. WC ve küçük koridor dahil, yalnız eşleştirdiğin lambalar planda görünür.',
        ),
      ],
    );
  }

  bool get _retrySessionReady =>
      mounted &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
      _owner != null &&
      FirebaseAuth.instance.currentUser?.uid == _owner &&
      _connected &&
      _timeReady &&
      _dataReady &&
      !_dataError;

  bool _retryDeviceReady(String id, WizAutoRetry attempt) {
    final config = _map(_map(_map(_homeData['config'])['lights'])[id]);
    final status = _map(_homeData['status']);
    final report = _map(_map(status['lights'])[id]);
    return _retrySessionReady &&
        config['ip'] == attempt.ip &&
        (report['ip'] == null || report['ip'] == attempt.ip) &&
        _fresh(_map(status['bridge'])['lastSeen'], 90000);
  }

  void _runAutoRetries() {
    if (!_retrySessionReady) return;
    final commands = _map(_homeData['commands']);
    final reports = _map(_map(_homeData['status'])['lights']);
    for (final entry in _autoRetries.entries.toList()) {
      final id = entry.key, attempt = entry.value;
      if (_sending.contains(id) || !_retryDeviceReady(id, attempt)) continue;
      final report = _map(reports[id]);
      final current = report['online'] == true &&
          report['ip'] == attempt.ip &&
          _fresh(report['reportedAt'], 90000);
      if (!attempt.eligible(
        command: _map(commands[id]),
        report: report,
        now: _now,
        reportIsCurrent: current,
      )) continue;
      // Spend the budget BEFORE asynchronous work, including failures/aborts.
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
    final generation = _binding;
    if (home == null) return;
    final ref = home.child('commands/$id');
    final newId = ref.push().key!;
    try {
      final result = await ref.runTransaction((raw) {
        if (generation != _binding ||
            !identical(_autoRetries[id], attempt) ||
            !_retryDeviceReady(id, attempt)) return Transaction.abort();
        final report = _map(_map(_map(_homeData['status'])['lights'])[id]);
        final current = report['online'] == true &&
            report['ip'] == attempt.ip &&
            _fresh(report['reportedAt'], 90000);
        if (!attempt.stillNeedsRetry(
            command: _map(raw),
            report: report,
            now: _now,
            reportIsCurrent: current)) {
          return Transaction.abort();
        }
        final replacement = attempt.replacement(
          _map(raw),
          newId: newId,
          now: _now,
        );
        return replacement == null
            ? Transaction.abort()
            : Transaction.success(replacement);
      }, applyLocally: false);
      if (mounted &&
          generation == _binding &&
          identical(_autoRetries[id], attempt) &&
          result.committed) {
        attempt.commandId = newId;
        attempt.responseStartedAt = _now;
      }
    } catch (_) {
      if (mounted && generation == _binding) {
        _message(
          'Otomatik tekrar gönderilemedi. Durumu kontrol edip elle tekrar deneyebilirsin.',
        );
      }
    } finally {
      if (mounted && generation == _binding) {
        _refresh(() {
          _sending.remove(id);
          _writeStarted.remove(id);
        });
      }
    }
  }

  WizCommandFeedback _commandFeedback(
    String id,
    Map<String, dynamic> command,
    Map<String, dynamic> report,
    bool current,
  ) {
    final attempt = _autoRetries[id];
    final second = attempt != null &&
        attempt.commandId == command['id'] &&
        attempt.responseStartedAt != null;
    final feedback = WizCommandFeedback.evaluate(
      command: command,
      report: report,
      now: _now,
      reportIsCurrent: current,
      writing: _sending.contains(id),
      writeStartedAt: _writeStarted[id],
      responseStartedAt: second ? attempt.responseStartedAt : null,
    );
    if (!second || feedback.message == null) return feedback;
    return WizCommandFeedback(
      pending: feedback.pending,
      retryable: feedback.retryable,
      params: feedback.params,
      message: feedback.pending
          ? 'İkinci deneme · ${feedback.message}'
          : feedback.retryable
              ? 'İkinci deneme de doğrulanamadı · Tekrar deneyebilirsin'
              : feedback.message,
    );
  }

  void _retryCommand(String id) {
    final lights = _map(_map(_homeData['config'])['lights']);
    final status = _map(_homeData['status']);
    final config = _map(lights[id]);
    final report = _map(_map(status['lights'])[id]);
    final command = _map(_map(_homeData['commands'])[id]);
    final current = _connected &&
        report['online'] == true &&
        report['ip'] == config['ip'] &&
        _fresh(report['reportedAt'], 90000);
    final feedback = _commandFeedback(id, command, report, current);
    if (config.isEmpty ||
        !_connected ||
        !_timeReady ||
        _dataError ||
        !_fresh(_map(status['bridge'])['lastSeen'], 90000) ||
        !feedback.retryable ||
        _sending.contains(id)) return;
    // Repeat the same absolute values. NEVER invert an unconfirmed old state.
    _send(id, feedback.params);
  }

  FixtureState _fixtureState(
    String fixture,
    Map<String, dynamic> lights,
    Map<String, dynamic> reported,
    Map<String, dynamic> commands,
    bool bridgeOnline,
  ) {
    final id = HomePlanPreferences.resolve(fixture, _bindings, lights);
    if (id == null) return const FixtureState();
    final config = _map(lights[id]),
        report = _map(reported[id]),
        command = _map(commands[id]);
    final fresh = _connected &&
        bridgeOnline &&
        report['online'] == true &&
        report['ip'] == config['ip'] &&
        _fresh(report['reportedAt'], 90000);
    final feedback = _commandFeedback(id, command, report, fresh);
    final pending = feedback.pending;
    final bool? on =
        fresh && report['state'] is bool ? report['state'] as bool : null;
    return FixtureState(
      assigned: true,
      on: on,
      pending: pending,
      retryable: feedback.retryable,
      feedback: feedback.message,
      controllable: (on != null || feedback.retryable) &&
          !_dataError &&
          _connected &&
          _timeReady &&
          bridgeOnline &&
          !pending,
    );
  }

  void _togglePlanFixture(String fixture) {
    // Re-read the current report/time at tap, not a possibly stale paint frame.
    final lights = _map(_map(_homeData['config'])['lights']);
    final status = _map(_homeData['status']);
    final bridge =
        _connected && _fresh(_map(status['bridge'])['lastSeen'], 90000);
    final state = _fixtureState(
      fixture,
      lights,
      _map(status['lights']),
      _map(_homeData['commands']),
      bridge,
    );
    final id = HomePlanPreferences.resolve(fixture, _bindings, lights);
    if (id != null && state.controllable) {
      if (state.retryable) {
        _retryCommand(id);
      } else if (state.on != null) {
        _send(id, {'state': !state.on!});
      }
    }
  }

  void _controlsForFixture(String fixture) {
    final lights = _map(_map(_homeData['config'])['lights']);
    final id = HomePlanPreferences.resolve(fixture, _bindings, lights);
    if (id != null) _openControls(id);
  }

  Widget _roomOverview(
    Map<String, dynamic> lights,
    Map<String, dynamic> reported,
    Map<String, dynamic> commands,
    bool bridgeOnline,
  ) {
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
              .where(
                (f) =>
                    HomePlanPreferences.resolve(f.id, _bindings, lights) !=
                    null,
              )
              .toList();
      final fixture = fixtures.any((f) => f.id == _selectedFixture)
          ? _selectedFixture
          : fixtures.firstOrNull?.id;
      final selected = fixtures.where((f) => f.id == fixture).firstOrNull;
      final id = fixture == null
          ? null
          : HomePlanPreferences.resolve(fixture, _bindings, lights);
      final state = states[fixture] ?? const FixtureState();
      final enabled = id != null &&
          state.controllable &&
          _connected &&
          _timeReady &&
          bridgeOnline &&
          !state.pending;
      final sensor = thermostat.thermostat;
      final hasReading = room.sensor &&
          sensor != null &&
          !thermostat.isLoading &&
          thermostat.error == null;
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
                  key: const ValueKey('back-home-plan'),
                  onPressed: _leaveRoom,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Ev planı'),
                ),
                Text(room.name, style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          ),
          if (fixtures.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final f in fixtures)
                    ChoiceChip(
                      key: ValueKey('fixture-${f.id}'),
                      avatar: f.floor
                          ? const FloorLampIcon(size: 18)
                          : const Icon(Icons.lightbulb_outline, size: 18),
                      label: Text(f.type),
                      selected: fixture == f.id,
                      onSelected: (_) =>
                          _refresh(() => _selectedFixture = f.id),
                    ),
                ],
              ),
            ),
          Expanded(
            child: RoomOverview(
              roomName: room.name,
              dimensions: room.dimensions,
              area: room.area,
              roomWidth: room.width,
              roomDepth: room.depth,
              showSensor: room.sensor,
              showLamp: id != null,
              planAspect: room.width == null || room.depth == null
                  ? room.bounds.width / room.bounds.height
                  : null,
              floorLamp: selected?.floor ?? false,
              isLightOn: state.on,
              ambientOn: fixtures.any((f) => states[f.id]?.on == true)
                  ? true
                  : state.on,
              pending: state.pending,
              commandFeedback: state.feedback,
              retryCommand: state.retryable,
              lightName: id == null
                  ? null
                  : '${_map(lights[id])['name'] ?? 'Ampul'} · ${selected?.type ?? ''}',
              onToggle: enabled ? () => _togglePlanFixture(fixture!) : null,
              onControls: id == null ? null : () => _openControls(id),
              onSetup: openSettings,
              temperature: hasReading && sensor.currentTemperature.isFinite
                  ? sensor.currentTemperature
                  : null,
              humidity: hasReading && sensor.humidity.isFinite
                  ? sensor.humidity
                  : null,
            ),
          ),
        ],
      );
    }
    final active = MainSectionActive.of(context);
    return PopScope(
      canPop: roomId == null || !active,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && active && _selectedRoom != null) _leaveRoom();
      },
      child: GestureDetector(
        key: const ValueKey('room-swipe-back'),
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart:
            roomId != null && active ? (_) => _roomDrag = 0 : null,
        onHorizontalDragUpdate:
            roomId != null && active ? (d) => _roomDrag += d.delta.dx : null,
        onHorizontalDragCancel:
            roomId != null && active ? () => _roomDrag = 0 : null,
        onHorizontalDragEnd: roomId != null && active
            ? (d) {
                if (_roomDrag > 48 || (d.primaryVelocity ?? 0) > 250)
                  _leaveRoom();
                _roomDrag = 0;
              }
            : null,
        child: AnimatedSwitcher(
          key: const ValueKey('room-transition'),
          duration: Duration(milliseconds: reduced ? 0 : 240),
          reverseDuration: Duration(milliseconds: reduced ? 0 : 160),
          // Do not keep a second interactive old room alive during the transition.
          layoutBuilder: (current, previous) => current ?? const SizedBox(),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: .97, end: 1).animate(animation),
              child: child,
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _lightCard(
    String id,
    Map<String, dynamic> config,
    Map<String, dynamic> report,
    Map<String, dynamic> command,
    bool bridgeOnline, {
    bool allowRemove = true,
  }) {
    final name = config['name'] as String? ?? 'Ampul';
    final fresh = bridgeOnline &&
        report['online'] == true &&
        report['ip'] == config['ip'] &&
        _fresh(report['reportedAt'], 90000);
    final knownState = fresh && report['state'] is bool;
    final feedback = _commandFeedback(id, command, report, fresh);
    final pending = feedback.pending;
    final text = feedback.message ??
        (!fresh
            ? 'Güncel ampul yanıtı yok'
            : knownState
                ? (report['state'] == true
                    ? 'Ampul bildirimi: Açık'
                    : 'Ampul bildirimi: Kapalı')
                : 'Durum bilinmiyor');
    final enabled = !_dataError &&
        _connected &&
        _timeReady &&
        bridgeOnline &&
        !_sending.contains(id) &&
        !pending;
    final brightness = report['dimming'] is num
        ? (report['dimming'] as num).toDouble().clamp(10.0, 100.0).toDouble()
        : 50.0;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  knownState && report['state'] == true
                      ? Icons.lightbulb
                      : Icons.lightbulb_outline,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (allowRemove)
                  IconButton(
                    onPressed: () => _remove(id, name),
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Ampulü kaldır',
                  ),
              ],
            ),
            Text(text),
            if (feedback.retryable && !pending)
              TextButton.icon(
                key: ValueKey('retry-command-$id'),
                onPressed: enabled ? () => _retryCommand(id) : null,
                icon: const Icon(Icons.refresh),
                label: const Text('Aynı komutu tekrar dene'),
              ),
            Text(
              config['ip'] as String? ?? '',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (report['commandStatus'] == 'rejected')
              const Text('ESP komutu reddetti; cihaz ayarını kontrol et.'),
            if (fresh && report['dimming'] is num)
              Text(
                'Bildirilen parlaklık: %${(report['dimming'] as num).round()}',
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed:
                        enabled ? () => _send(id, {'state': true}) : null,
                    child: const Text('Aç'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        enabled ? () => _send(id, {'state': false}) : null,
                    child: const Text('Kapat'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _BrightnessControl(
              key: ValueKey('brightness-$id'),
              value: brightness,
              enabled: enabled,
              onCommit: (v) => _send(id, {'state': true, 'dimming': v.round()}),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in <String, Map<String, dynamic>>{
                  'Sıcak beyaz': {'state': true, 'temp': 2700},
                  'Soğuk beyaz': {'state': true, 'temp': 6500},
                  'Kırmızı': {'state': true, 'r': 255, 'g': 0, 'b': 0},
                  'Yeşil': {'state': true, 'r': 0, 'g': 255, 'b': 0},
                  'Mavi': {'state': true, 'r': 0, 'g': 0, 'b': 255},
                }.entries)
                  OutlinedButton(
                    onPressed: enabled ? () => _send(id, preset.value) : null,
                    child: Text(preset.key),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BrightnessControl extends StatefulWidget {
  const _BrightnessControl({
    super.key,
    required this.value,
    required this.enabled,
    required this.onCommit,
  });
  final double value;
  final bool enabled;
  final ValueChanged<double> onCommit;
  @override
  State<_BrightnessControl> createState() => _BrightnessControlState();
}

class _BrightnessControlState extends State<_BrightnessControl> {
  late double _value;
  bool _dragging = false;
  @override
  void initState() {
    super.initState();
    _value = widget.value;
  }

  @override
  void didUpdateWidget(covariant _BrightnessControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging && oldWidget.value != widget.value) _value = widget.value;
    if (!widget.enabled) _dragging = false;
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Parlaklık: %${_value.round()}'),
          Slider(
            value: _value,
            min: 10,
            max: 100,
            divisions: 90,
            onChanged: widget.enabled
                ? (v) => setState(() {
                      _dragging = true;
                      _value = v;
                    })
                : null,
            onChangeEnd: widget.enabled
                ? (v) {
                    _dragging = false;
                    widget.onCommit(v);
                  }
                : null,
          ),
        ],
      );
}
