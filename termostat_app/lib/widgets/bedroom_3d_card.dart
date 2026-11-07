import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Yatak odasındaki seçilebilir ampul modeli.
/// Kendi WiZ ampul listeni buraya aktarabilir veya varsayılan listeyi düzenleyebilirsin.
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

/// Haritadaki "Yatak odası" ekranında yer alan boş izometrik kutunun yerine
/// doğrudan koyabileceğin 3B Etkileşimli Yatak Odası Kartı.
class Bedroom3DCard extends StatefulWidget {
  const Bedroom3DCard({
    super.key,
    this.availableBulbs = const [
      SelectableBedroomBulb(id: 'yatak_tavan', name: 'Yatak Odası · Tavan Lambası'),
      SelectableBedroomBulb(id: 'yatak_abajur', name: 'Yatak Odası · Abajur / Lambader'),
      SelectableBedroomBulb(id: 'yatak_tumu', name: 'Yatak Odası · Tüm Ampuller'),
    ],
    this.onTriggerBulb,
    this.isHeating = false,
    this.initialCeilingOn = false,
    this.initialFloorLampOn = false,
    this.height = 330,
  });

  /// Seçim penceresinde listelenecek yatak odası ampulleri
  final List<SelectableBedroomBulb> availableBulbs;

  /// 3B odada Tavan Lambası veya Abajur tıklandığında tetiklenen geri çağırım:
  /// (bulbId, isOn, fixtureType) -> Kendi WiZ ampul aç/kapat fonksiyonunu buraya bağlayabilirsin.
  final Future<void> Function(String bulbId, bool isOn, String fixtureType)? onTriggerBulb;

  /// Kombi çalışıyorsa 3B odadaki petek hafif sıcak parlar
  final bool isHeating;

  final bool initialCeilingOn;
  final bool initialFloorLampOn;
  final double height;

  @override
  State<Bedroom3DCard> createState() => _Bedroom3DCardState();
}

class _Bedroom3DCardState extends State<Bedroom3DCard> {
  static const String _prefLayoutKey = 'bedroom_3d_saved_layout_v4';
  static const String _prefCeilingBulbKey = 'bedroom_3d_ceiling_bulb_id';
  static const String _prefFloorLampBulbKey = 'bedroom_3d_floor_lamp_bulb_id';

  late final WebViewController _controller;
  bool _isLoaded = false;

  String? _selectedCeilingBulbId;
  String? _selectedFloorLampBulbId;
  Map<String, dynamic>? _savedLayoutJson;

  @override
  void initState() {
    super.initState();
    _loadPreferences();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF18191D))
      ..addJavaScriptChannel(
        'FlutterRoomChannel',
        onMessageReceived: (JavaScriptMessage msg) {
          _onMessageFrom3D(msg.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() => _isLoaded = true);
            _syncStateTo3D();
          },
        ),
      )
      ..loadFlutterAsset('assets/room3d/tam_oda_planlayici_360-v4.html');
  }

  @override
  void didUpdateWidget(covariant Bedroom3DCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isHeating != widget.isHeating && _isLoaded) {
      _syncStateTo3D();
    }
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final defaultFirst =
        widget.availableBulbs.isNotEmpty ? widget.availableBulbs.first.id : null;
    final defaultSecond = widget.availableBulbs.length > 1
        ? widget.availableBulbs[1].id
        : defaultFirst;

    final savedLayoutStr = prefs.getString(_prefLayoutKey);
    Map<String, dynamic>? parsedLayout;
    if (savedLayoutStr != null && savedLayoutStr.isNotEmpty) {
      try {
        parsedLayout = jsonDecode(savedLayoutStr) as Map<String, dynamic>;
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _selectedCeilingBulbId =
          prefs.getString(_prefCeilingBulbKey) ?? defaultFirst;
      _selectedFloorLampBulbId =
          prefs.getString(_prefFloorLampBulbKey) ?? defaultSecond;
      _savedLayoutJson = parsedLayout;
    });

    if (_isLoaded) {
      _syncStateTo3D();
    }
  }

  void _syncStateTo3D() {
    if (!_isLoaded) return;
    final payload = <String, dynamic>{
      'isHeating': widget.isHeating,
      if (_savedLayoutJson != null) 'savedLayout': _savedLayoutJson,
    };
    _controller.runJavaScript(
      'if (window.syncFromFlutter) { window.syncFromFlutter(${jsonEncode(payload)}); }',
    );
  }

  Future<void> _onMessageFrom3D(String rawJson) async {
    try {
      final map = jsonDecode(rawJson) as Map<String, dynamic>;
      final type = map['type']?.toString();

      // 1. Eşya yeri veya kilidi değiştiğinde kalıcı olarak kaydet
      if (type == 'layout_saved') {
        final layoutData = map['data'];
        if (layoutData is Map<String, dynamic>) {
          _savedLayoutJson = layoutData;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_prefLayoutKey, jsonEncode(layoutData));
        }
        return;
      }

      // 2. 3B odada Tavan Lambası veya Abajura tıklandığında seçili yatak odası ampulünü tetikle
      if (type == 'light_toggle') {
        final fixture = map['fixture']?.toString() ?? 'ceiling_light';
        final isOn = map['isOn'] as bool? ?? false;

        final targetBulbId = fixture == 'ceiling_light'
            ? _selectedCeilingBulbId
            : _selectedFloorLampBulbId;

        if (targetBulbId == null || targetBulbId == 'none') {
          if (mounted) {
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${fixture == 'ceiling_light' ? 'Tavan lambası' : 'Abajur'} için henüz ampul seçilmedi.',
                ),
                action: SnackBarAction(
                  label: 'Seç',
                  onPressed: _showBulbMappingSheet,
                ),
                duration: const Duration(seconds: 2),
              ),
            );
          }
          return;
        }

        await _triggerSelectedBedroomBulb(
          bulbId: targetBulbId,
          isOn: isOn,
          fixtureType: fixture,
        );
      }
    } catch (_) {}
  }

  /// =========================================================================
  /// YATAK ODASI AMPUL TETİKLEME NOKTASI
  /// İstersen widget'a `onTriggerBulb` parametresi geçebilir, istersen
  /// doğrudan aşağıdaki TODO kısmına kendi WiZ ampul kodunu yazabilirsin.
  /// =========================================================================
  Future<void> _triggerSelectedBedroomBulb({
    required String bulbId,
    required bool isOn,
    required String fixtureType,
  }) async {
    if (widget.onTriggerBulb != null) {
      await widget.onTriggerBulb!(bulbId, isOn, fixtureType);
    } else {
      // TODO: Kendi yatak odası WiZ ampul kontrol kodunu buraya ekleyebilirsin.
      // Örnek:
      // await context.read<WizProvider>().setBulbState(bulbId, isOn);
      debugPrint('3B Oda Işık Tetiklendi -> Ampul: $bulbId | Durum: ${isOn ? "AÇIK" : "KAPALI"} ($fixtureType)');
    }

    if (!mounted) return;
    final bulbName = widget.availableBulbs
        .where((b) => b.id == bulbId)
        .map((b) => b.name)
        .firstOrNull ?? bulbId;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$bulbName: ${isOn ? "Açıldı" : "Kapatıldı"}'),
        duration: const Duration(milliseconds: 1300),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Kullanıcının 3B odadaki Tavan Lambası ve Abajur için hangi yatak odası
  /// ampulünün tetikleneceğini seçtiği alt pencere (Bottom Sheet).
  Future<void> _showBulbMappingSheet() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final options = [
              const DropdownMenuItem<String>(
                value: 'none',
                child: Text('Tetikleme Yok (Sadece 3B Işık)'),
              ),
              ...widget.availableBulbs.map(
                (b) => DropdownMenuItem<String>(
                  value: b.id,
                  child: Text(b.name, overflow: TextOverflow.ellipsis),
                ),
              ),
            ];

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '3B Oda · Yatak Odası Ampul Eşleştirme',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '3B odadaki lambalara dokunduğunda hangi yatak odası ampulünün açılıp kapanacağını seçin:',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    value: options.any((o) => o.value == _selectedCeilingBulbId)
                        ? _selectedCeilingBulbId
                        : 'none',
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: '💡 3B Tavan Lambası Tıklandığında',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                    items: options,
                    onChanged: (val) async {
                      if (val == null) return;
                      setModalState(() => _selectedCeilingBulbId = val);
                      setState(() => _selectedCeilingBulbId = val);
                      await prefs.setString(_prefCeilingBulbKey, val);
                    },
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: options.any((o) => o.value == _selectedFloorLampBulbId)
                        ? _selectedFloorLampBulbId
                        : 'none',
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: '🛋️ 3B Üç Ayaklı Abajur Tıklandığında',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                    items: options,
                    onChanged: (val) async {
                      if (val == null) return;
                      setModalState(() => _selectedFloorLampBulbId = val);
                      setState(() => _selectedFloorLampBulbId = val);
                      await prefs.setString(_prefFloorLampBulbKey, val);
                    },
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Kaydet ve Kapat'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ceilingName = widget.availableBulbs
            .where((b) => b.id == _selectedCeilingBulbId)
            .map((b) => b.name)
            .firstOrNull ??
        'Ampul seçilmedi';
    final floorName = widget.availableBulbs
            .where((b) => b.id == _selectedFloorLampBulbId)
            .map((b) => b.name)
            .firstOrNull ??
        'Ampul seçilmedi';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 3B Etkileşimli Oda Kutusu (Boş izometrik kutunun yerini alır)
        Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: const Color(0xFF18191D),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Theme.of(context).dividerColor.withOpacity(0.25),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              WebViewWidget(
                controller: _controller,
                // Sayfa kaydırması ile 3B oda döndürmenin çakışmaması için:
                gestureRecognizers: {
                  Factory<OneSequenceGestureRecognizer>(
                    () => EagerGestureRecognizer(),
                  ),
                },
              ),
              if (!_isLoaded)
                const Center(
                  child: CircularProgressIndicator(),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Alt Bilgi & Yatak Odası Ampul Eşleştirme Satırı
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                '💡 $ceilingName  ·  🛋️ $floorName',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.75),
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _showBulbMappingSheet,
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
              icon: const Icon(Icons.lightbulb_outline, size: 16),
              label: const Text(
                'Ampul Seçimi',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
