import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

class SelectableBedroomBulb {
  final String id;
  final String name;
  final String? ip;

  const SelectableBedroomBulb({
    required this.id,
    required this.name,
    this.ip,
  });
}

class Bedroom3DCard extends StatefulWidget {
  final double height;
  final bool isHeating;
  final bool initialCeilingOn;
  final List<SelectableBedroomBulb> availableBulbs;
  final Future<void> Function(
    String bulbId,
    bool isOn,
    String fixtureType,
  )? onTriggerBulb;

  const Bedroom3DCard({
    super.key,
    this.height = 340,
    this.isHeating = false,
    this.initialCeilingOn = true,
    this.availableBulbs = const [],
    this.onTriggerBulb,
  });

  @override
  State<Bedroom3DCard> createState() => _Bedroom3DCardState();
}

class _Bedroom3DCardState extends State<Bedroom3DCard> {
  static const String _prefCeilingBulbKey = 'bedroom_3d_ceiling_bulb_id_v2';
  static const String _prefNightstandBulbKey =
      'bedroom_3d_nightstand_bulb_id_v2';
  static const String _prefLayoutLockKey = 'bedroom_3d_layout_locked_v2';

  late final WebViewController _controller;
  bool _pageLoaded = false;
  bool _layoutLocked = true;
  bool _ceilingOn = true;
  bool _nightstandOn = false;
  String? _ceilingBulbId;
  String? _nightstandBulbId;

  @override
  void initState() {
    super.initState();
    _ceilingOn = widget.initialCeilingOn;
    _initController();
    _loadSavedBindings();
  }

  Future<void> _loadSavedBindings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCeiling = prefs.getString(_prefCeilingBulbKey);
      final savedNight = prefs.getString(_prefNightstandBulbKey);
      final savedLock = prefs.getBool(_prefLayoutLockKey) ?? true;
      if (!mounted) return;
      setState(() {
        _ceilingBulbId = savedCeiling;
        _nightstandBulbId = savedNight;
        _layoutLocked = savedLock;
      });
      _resolveDefaultBulbsIfNeeded();
      await _syncSceneState();
    } catch (_) {
      _resolveDefaultBulbsIfNeeded();
    }
  }

  void _resolveDefaultBulbsIfNeeded() {
    if (widget.availableBulbs.isEmpty) return;
    final validIds = widget.availableBulbs.map((b) => b.id).toSet();
    if (_ceilingBulbId == null || !validIds.contains(_ceilingBulbId)) {
      _ceilingBulbId = widget.availableBulbs.first.id;
    }
    if (_nightstandBulbId == null || !validIds.contains(_nightstandBulbId)) {
      _nightstandBulbId = widget.availableBulbs.length > 1
          ? widget.availableBulbs[1].id
          : widget.availableBulbs.first.id;
    }
  }

  void _initController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0F1319))
      ..addJavaScriptChannel(
        'FlutterRoomBridge',
        onMessageReceived: (JavaScriptMessage message) {
          _handleJsMessage(message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) async {
            if (!mounted) return;
            setState(() => _pageLoaded = true);
            await _syncSceneState();
          },
        ),
      )
      ..loadFlutterAsset('assets/room3d/tam_oda_planlayici_360-v4.html');
  }

  @override
  void didUpdateWidget(covariant Bedroom3DCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resolveDefaultBulbsIfNeeded();
    bool needsSync = false;
    if (oldWidget.isHeating != widget.isHeating) {
      needsSync = true;
    }
    if (oldWidget.initialCeilingOn != widget.initialCeilingOn &&
        widget.initialCeilingOn != _ceilingOn) {
      _ceilingOn = widget.initialCeilingOn;
      needsSync = true;
    }
    if (needsSync) {
      unawaited(_syncSceneState());
    }
  }

  Future<void> _syncSceneState() async {
    if (!_pageLoaded) return;
    final heatingBool = widget.isHeating ? 'true' : 'false';
    final ceilingBool = _ceilingOn ? 'true' : 'false';
    final nightBool = _nightstandOn ? 'true' : 'false';
    final lockBool = _layoutLocked ? 'true' : 'false';
    final js = '''
      try {
        if (typeof window.setHeatingGlow === 'function') {
          window.setHeatingGlow($heatingBool);
        }
        if (typeof window.setRoomLightState === 'function') {
          window.setRoomLightState('ceiling', $ceilingBool);
          window.setRoomLightState('nightstand', $nightBool);
        }
        if (typeof window.setLayoutLocked === 'function') {
          window.setLayoutLocked($lockBool);
        }
      } catch (e) {}
    ''';
    try {
      await _controller.runJavaScript(js);
    } catch (_) {}
  }

  void _handleJsMessage(String raw) {
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return;
      final type = data['type']?.toString() ?? '';
      if (type == 'sceneReady') {
        unawaited(_syncSceneState());
        return;
      }
      if (type == 'lightToggled' || type == 'toggleLight') {
        final fixture = (data['fixture'] ?? data['target'] ?? 'ceiling')
            .toString()
            .toLowerCase();
        final isOn = data['state'] == true || data['isOn'] == true;
        _resolveDefaultBulbsIfNeeded();
        String? targetBulbId;
        if (fixture.contains('night') ||
            fixture.contains('floor') ||
            fixture.contains('abajur') ||
            fixture.contains('desk')) {
          _nightstandOn = isOn;
          targetBulbId = _nightstandBulbId ?? _ceilingBulbId;
        } else {
          _ceilingOn = isOn;
          targetBulbId = _ceilingBulbId ?? _nightstandBulbId;
        }
        if (targetBulbId == null && widget.availableBulbs.isNotEmpty) {
          targetBulbId = widget.availableBulbs.first.id;
        }
        if (widget.onTriggerBulb != null) {
          unawaited(
            widget.onTriggerBulb!(targetBulbId ?? '', isOn, fixture),
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _toggleLock() async {
    final next = !_layoutLocked;
    setState(() => _layoutLocked = next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefLayoutLockKey, next);
    } catch (_) {}
    await _syncSceneState();
  }

  Future<void> _openBulbPickerSheet() async {
    _resolveDefaultBulbsIfNeeded();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final bulbs = widget.availableBulbs;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '3B Yatak Odası Ampul Eşleştirmesi',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    if (bulbs.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Henüz kayıtlı WiZ ampul yok. Sağ üstteki Ev ve ampul ayarlarından ampul ekleyebilirsin.',
                        ),
                      )
                    else ...[
                      DropdownButtonFormField<String>(
                        value: bulbs.any((b) => b.id == _ceilingBulbId)
                            ? _ceilingBulbId
                            : bulbs.first.id,
                        decoration: const InputDecoration(
                          labelText: 'Tavan Lambası (3B Sahne)',
                          prefixIcon: Icon(Icons.light),
                        ),
                        items: [
                          for (final b in bulbs)
                            DropdownMenuItem(
                              value: b.id,
                              child: Text(b.name),
                            ),
                        ],
                        onChanged: (val) async {
                          setSheetState(() => _ceilingBulbId = val);
                          setState(() => _ceilingBulbId = val);
                          final prefs = await SharedPreferences.getInstance();
                          if (val != null) {
                            await prefs.setString(_prefCeilingBulbKey, val);
                          }
                        },
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        value: bulbs.any((b) => b.id == _nightstandBulbId)
                            ? _nightstandBulbId
                            : bulbs.first.id,
                        decoration: const InputDecoration(
                          labelText: 'Komodin Abajuru (3B Sahne)',
                          prefixIcon: Icon(Icons.wb_incandescent_outlined),
                        ),
                        items: [
                          for (final b in bulbs)
                            DropdownMenuItem(
                              value: b.id,
                              child: Text(b.name),
                            ),
                        ],
                        onChanged: (val) async {
                          setSheetState(() => _nightstandBulbId = val);
                          setState(() => _nightstandBulbId = val);
                          final prefs = await SharedPreferences.getInstance();
                          if (val != null) {
                            await prefs.setString(_prefNightstandBulbKey, val);
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: const Color(0xFF0F1319),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: widget.isHeating
                ? const Color(0xFFFF5722).withValues(alpha: 0.65)
                : Colors.white12,
            width: widget.isHeating ? 1.8 : 1.0,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: WebViewWidget(controller: _controller),
            ),
            if (!_pageLoaded)
              const Positioned.fill(
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            // Sol üst: Kalorifer ısıtma durumu rozeti
            if (widget.isHeating)
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD84315).withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x88FF3D00),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.local_fire_department,
                        color: Colors.white,
                        size: 15,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Kalorifer Isıtıyor',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // Sağ üst: Kilit ve Ampul Eşleştirme butonları
            Positioned(
              top: 10,
              right: 10,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Material(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: _toggleLock,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _layoutLocked ? Icons.lock : Icons.lock_open,
                              color: _layoutLocked
                                  ? Colors.amberAccent
                                  : Colors.white70,
                              size: 15,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _layoutLocked ? 'Kilitli' : 'Düzenle',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Material(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: _openBulbPickerSheet,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.lightbulb_outline,
                              color: Colors.amberAccent,
                              size: 15,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Ampuller',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
