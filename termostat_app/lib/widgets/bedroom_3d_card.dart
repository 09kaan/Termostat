import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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
  final bool initialFloorLampOn;
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
    this.initialCeilingOn = false,
    this.initialFloorLampOn = false,
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
  static const String _prefSavedLayoutJsonKey = 'bedroom_3d_saved_layout_v4';

  late final WebViewController _controller;
  bool _pageLoaded = false;
  bool _ceilingOn = false;
  bool _nightstandOn = false;
  String? _ceilingBulbId;
  String? _nightstandBulbId;
  String? _savedLayoutJson;

  @override
  void initState() {
    super.initState();
    _ceilingOn = widget.initialCeilingOn;
    _nightstandOn = widget.initialFloorLampOn;
    _initController();
    _loadSavedBindings();
  }

  Future<void> _loadSavedBindings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCeiling = prefs.getString(_prefCeilingBulbKey);
      final savedNight = prefs.getString(_prefNightstandBulbKey);
      final savedLayout = prefs.getString(_prefSavedLayoutJsonKey);
      if (!mounted) return;
      setState(() {
        _ceilingBulbId = savedCeiling;
        _nightstandBulbId = savedNight;
        _savedLayoutJson = savedLayout;
      });
      _resolveDefaultBulbsIfNeeded();
      await _syncSceneState(includeLayout: true);
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
      ..setBackgroundColor(const Color(0xFF18191D))
      ..addJavaScriptChannel(
        'FlutterRoomChannel',
        onMessageReceived: (JavaScriptMessage message) {
          _handleJsMessage(message.message);
        },
      )
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
            await _syncSceneState(includeLayout: true);
            Future<void>.delayed(const Duration(milliseconds: 350), () {
              if (mounted) _syncSceneState(includeLayout: true);
            });
            Future<void>.delayed(const Duration(milliseconds: 900), () {
              if (mounted) _syncSceneState(includeLayout: false);
            });
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
    if (oldWidget.initialCeilingOn != widget.initialCeilingOn) {
      _ceilingOn = widget.initialCeilingOn;
      needsSync = true;
    }
    if (oldWidget.initialFloorLampOn != widget.initialFloorLampOn) {
      _nightstandOn = widget.initialFloorLampOn;
      needsSync = true;
    }
    if (needsSync) {
      unawaited(_syncSceneState(includeLayout: false));
    }
  }

  Future<void> _syncSceneState({bool includeLayout = false}) async {
    if (!_pageLoaded) return;
    final payload = <String, dynamic>{
      'ceilingOn': _ceilingOn,
      'floorLampOn': _nightstandOn,
      'isHeating': widget.isHeating,
    };
    if (includeLayout &&
        _savedLayoutJson != null &&
        _savedLayoutJson!.isNotEmpty) {
      try {
        payload['savedLayout'] = jsonDecode(_savedLayoutJson!);
      } catch (_) {}
    }
    final encoded = jsonEncode(payload);
    final js = '''
      try {
        if (typeof window.syncFromFlutter === 'function') {
          window.syncFromFlutter($encoded);
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
        unawaited(_syncSceneState(includeLayout: true));
        return;
      }

      if (type == 'layout_saved' && data['data'] is Map) {
        final layoutStr = jsonEncode(data['data']);
        _savedLayoutJson = layoutStr;
        SharedPreferences.getInstance().then((prefs) {
          prefs.setString(_prefSavedLayoutJsonKey, layoutStr);
        });
        return;
      }

      if (type == 'light_toggle' ||
          type == 'lightToggled' ||
          type == 'toggleLight') {
        final fixture = (data['fixture'] ?? data['target'] ?? 'ceiling_light')
            .toString()
            .toLowerCase();
        final isOn = data['isOn'] == true || data['state'] == true;
        _resolveDefaultBulbsIfNeeded();
        String? targetBulbId;
        if (fixture.contains('floor') ||
            fixture.contains('night') ||
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
                          labelText: '💡 Tavan Lambası (3B Sahne)',
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
                          labelText: '🛋️ Üç Ayaklı Abajur (3B Sahne)',
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
          color: const Color(0xFF18191D),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: widget.isHeating
                ? const Color(0xFFFF5722).withValues(alpha: 0.75)
                : Colors.white12,
            width: widget.isHeating ? 1.8 : 1.0,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: WebViewWidget(
                controller: _controller,
                gestureRecognizers: {
                  Factory<OneSequenceGestureRecognizer>(
                    () => EagerGestureRecognizer(),
                  ),
                },
              ),
            ),
            if (!_pageLoaded)
              const Positioned.fill(
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            if (widget.isHeating)
              Positioned(
                bottom: 10,
                left: 10,
                child: IgnorePointer(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD84315).withValues(alpha: 0.90),
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
              ),
            Positioned(
              bottom: 10,
              right: 10,
              child: Material(
                color: const Color(0xDD121216),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: _openBulbPickerSheet,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 10,
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
                          'Ampul Eşleştir',
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}
