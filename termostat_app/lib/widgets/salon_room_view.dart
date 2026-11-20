import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SelectableSalonBulb {
  const SelectableSalonBulb({
    required this.id,
    required this.name,
    this.ip,
  });

  final String id;
  final String name;
  final String? ip;
}

class _ColorPreset {
  const _ColorPreset({
    required this.label,
    required this.previewColor,
    required this.params,
  });

  final String label;
  final Color previewColor;
  final Map<String, dynamic> params;
}

class SalonRoomView extends StatefulWidget {
  const SalonRoomView({
    super.key,
    required this.floorLampOn,
    required this.floorLampPending,
    required this.floorLampRetryable,
    required this.floorLampControllable,
    this.floorLampFeedback,
    this.floorLampName,
    this.floorLampDimming = 85,
    this.floorLampColor,
    this.ceilingLampOn,
    this.ceilingLampName,
    this.ceilingLampControllable = false,
    this.availableBulbs = const [],
    this.selectedFloorBulbId,
    this.onToggleFloorLamp,
    this.onToggleCeilingLamp,
    this.onChangeBrightness,
    this.onChangeColor,
    this.onAssignFloorBulb,
    this.onOpenFullControls,
  });

  final bool? floorLampOn;
  final bool floorLampPending;
  final bool floorLampRetryable;
  final bool floorLampControllable;
  final String? floorLampFeedback;
  final String? floorLampName;
  final int floorLampDimming;
  final Color? floorLampColor;

  final bool? ceilingLampOn;
  final String? ceilingLampName;
  final bool ceilingLampControllable;

  final List<SelectableSalonBulb> availableBulbs;
  final String? selectedFloorBulbId;

  final VoidCallback? onToggleFloorLamp;
  final VoidCallback? onToggleCeilingLamp;
  final ValueChanged<int>? onChangeBrightness;
  final ValueChanged<Map<String, dynamic>>? onChangeColor;
  final Future<void> Function(String? bulbId)? onAssignFloorBulb;
  final VoidCallback? onOpenFullControls;

  @override
  State<SalonRoomView> createState() => _SalonRoomViewState();
}

class _SalonRoomViewState extends State<SalonRoomView> {
  static const Size _imageNativeSize = Size(1200, 896);

  static const List<_ColorPreset> _presets = [
    _ColorPreset(
      label: 'Sıcak Beyaz',
      previewColor: Color(0xFFFFB866),
      params: {'temp': 2700},
    ),
    _ColorPreset(
      label: 'Gün Işığı',
      previewColor: Color(0xFFFFF0D4),
      params: {'temp': 4200},
    ),
    _ColorPreset(
      label: 'Soğuk Beyaz',
      previewColor: Color(0xFFD6E8FF),
      params: {'temp': 6500},
    ),
    _ColorPreset(
      label: 'Kırmızı',
      previewColor: Color(0xFFFF2E2E),
      params: {'r': 255, 'g': 0, 'b': 0},
    ),
    _ColorPreset(
      label: 'Turuncu',
      previewColor: Color(0xFFFF7A00),
      params: {'r': 255, 'g': 110, 'b': 0},
    ),
    _ColorPreset(
      label: 'Sarı',
      previewColor: Color(0xFFFFD600),
      params: {'r': 255, 'g': 210, 'b': 0},
    ),
    _ColorPreset(
      label: 'Yeşil',
      previewColor: Color(0xFF00E664),
      params: {'r': 0, 'g': 230, 'b': 90},
    ),
    _ColorPreset(
      label: 'Turkuaz',
      previewColor: Color(0xFF00DCF5),
      params: {'r': 0, 'g': 220, 'b': 255},
    ),
    _ColorPreset(
      label: 'Mavi',
      previewColor: Color(0xFF2962FF),
      params: {'r': 30, 'g': 100, 'b': 255},
    ),
    _ColorPreset(
      label: 'Mor',
      previewColor: Color(0xFFAA28FF),
      params: {'r': 170, 'g': 40, 'b': 255},
    ),
    _ColorPreset(
      label: 'Pembe',
      previewColor: Color(0xFFFF2896),
      params: {'r': 255, 'g': 40, 'b': 150},
    ),
  ];

  late double _localDimming;
  bool _draggingDimming = false;
  Color? _optimisticColor;

  @override
  void initState() {
    super.initState();
    _localDimming = widget.floorLampDimming.clamp(10, 100).toDouble();
  }

  @override
  void didUpdateWidget(covariant SalonRoomView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_draggingDimming &&
        oldWidget.floorLampDimming != widget.floorLampDimming) {
      _localDimming = widget.floorLampDimming.clamp(10, 100).toDouble();
    }
    if (widget.floorLampColor != null &&
        oldWidget.floorLampColor != widget.floorLampColor) {
      _optimisticColor = widget.floorLampColor;
    }
  }

  Color get _effectiveLightColor =>
      _optimisticColor ??
      widget.floorLampColor ??
      const Color(0xFFFFB866);

  bool get _isFloorOn => widget.floorLampOn == true;

  void _handleFloorTap() {
    if (widget.floorLampName == null) {
      _openQuickPairSheet();
      return;
    }
    if (!widget.floorLampControllable || widget.onToggleFloorLamp == null) {
      return;
    }
    HapticFeedback.lightImpact();
    widget.onToggleFloorLamp!();
  }

  void _selectPreset(_ColorPreset preset) {
    if (!widget.floorLampControllable || widget.onChangeColor == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _optimisticColor = preset.previewColor;
    });
    widget.onChangeColor!(preset.params);
  }

  Future<void> _openRgbPickerSheet() async {
    if (!widget.floorLampControllable || widget.onChangeColor == null) return;
    HSVColor hsv = HSVColor.fromColor(_effectiveLightColor);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final current = hsv.toColor();
            final r = (current.r * 255).round().clamp(0, 255);
            final g = (current.g * 255).round().clamp(0, 255);
            final b = (current.b * 255).round().clamp(0, 255);
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: current,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: current.withValues(alpha: 0.55),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Çubuk LED Özel Renk Seçimi',
                            style: Theme.of(ctx)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Text(
                          'RGB($r, $g, $b)',
                          style: Theme.of(ctx).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('Renk Tonu',
                        style: Theme.of(ctx).textTheme.labelMedium),
                    SliderTheme(
                      data: SliderTheme.of(ctx).copyWith(
                        trackHeight: 10,
                        thumbColor: current,
                        activeTrackColor: current,
                      ),
                      child: Slider(
                        value: hsv.hue,
                        min: 0,
                        max: 360,
                        onChanged: (h) {
                          setSheetState(() => hsv = hsv.withHue(h));
                          setState(() => _optimisticColor = hsv.toColor());
                        },
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('Doygunluk',
                        style: Theme.of(ctx).textTheme.labelMedium),
                    Slider(
                      value: hsv.saturation,
                      min: 0.05,
                      max: 1.0,
                      onChanged: (s) {
                        setSheetState(() => hsv = hsv.withSaturation(s));
                        setState(() => _optimisticColor = hsv.toColor());
                      },
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        widget.onChangeColor!({'r': r, 'g': g, 'b': b});
                      },
                      icon: const Icon(Icons.check),
                      label: const Text('Rengi Uygula'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openQuickPairSheet() async {
    if (widget.onAssignFloorBulb == null) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final bulbs = widget.availableBulbs;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Salon Çubuk LED Eşleştir',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'TV yanındaki dikey çubuk LED lambader için eklediğin ampulü (ör. 0.0.0.1) seç:',
                ),
                const SizedBox(height: 12),
                if (bulbs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Henüz kayıtlı ampul yok. Sağ üstteki ayarlar (🎛️) menüsünden 0.0.0.1 IP adresiyle ekleyebilirsin.',
                    ),
                  )
                else
                  for (final b in bulbs)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        b.id == widget.selectedFloorBulbId
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                      ),
                      title: Text(b.name),
                      subtitle: b.ip != null ? Text('IP: ${b.ip}') : null,
                      onTap: () async {
                        Navigator.pop(ctx);
                        await widget.onAssignFloorBulb!(b.id);
                      },
                    ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasBulb = widget.floorLampName != null;
    final statusText = !hasBulb
        ? 'Çubuk LED eşleştirilmedi'
        : widget.floorLampFeedback ??
            (widget.floorLampPending
                ? 'Yanıt bekleniyor…'
                : _isFloorOn
                    ? 'Açık · %${_localDimming.round()}'
                    : 'Kapalı');

    return LayoutBuilder(
      builder: (context, constraints) {
        final smallHeight = constraints.maxHeight < 520;
        final stage = _buildRoomStage(context);
        final dock = _buildControlDock(
          context,
          theme: theme,
          colors: colors,
          hasBulb: hasBulb,
          statusText: statusText,
        );

        if (smallHeight) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: 320, child: stage),
                dock,
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 64, child: stage),
            dock,
          ],
        );
      },
    );
  }

  Widget _buildRoomStage(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final stageSize = Size(box.maxWidth, box.maxHeight);
        final fitted = applyBoxFit(
          BoxFit.contain,
          _imageNativeSize,
          stageSize,
        );
        final dstSize = fitted.destination;
        final dx = (stageSize.width - dstSize.width) / 2;
        final dy = (stageSize.height - dstSize.height) / 2;
        final imageRect = Rect.fromLTWH(dx, dy, dstSize.width, dstSize.height);

        // Exact normalized center of the vertical LED bar in salon_3d.png:
        // top=(0.2775, 0.414), bottom=(0.2825, 0.656) -> center=(0.280, 0.535)
        final barCenterX = imageRect.left + imageRect.width * 0.280;
        final barTopY = imageRect.top + imageRect.height * 0.400;
        final barHeight = imageRect.height * 0.275;

        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFDDDDDB), Color(0xFFCACAC8)],
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 1. High-resolution photo-realistic Salon render filling the stage
              Positioned.fromRect(
                rect: imageRect,
                child: Image.asset(
                  'assets/images/salon_3d.png',
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.high,
                ),
              ),

              // 2. Real-time dynamic LED light beam & room dimming overlay
              Positioned.fromRect(
                rect: imageRect,
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _SalonLightPainter(
                      isOn: _isFloorOn,
                      color: _effectiveLightColor,
                      brightness: (_localDimming / 100.0).clamp(0.10, 1.0),
                    ),
                  ),
                ),
              ),

              // 3. Direct touch target right over the vertical LED floor bar
              Positioned(
                left: barCenterX - 38,
                top: barTopY - 8,
                width: 76,
                height: barHeight + 20,
                child: Semantics(
                  button: true,
                  label: 'Salon Çubuk LED Lambader',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _handleFloorTap,
                    onLongPress: widget.onOpenFullControls,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _isFloorOn
                              ? Colors.black.withValues(alpha: 0.72)
                              : Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _isFloorOn
                                ? _effectiveLightColor.withValues(alpha: 0.9)
                                : Colors.white24,
                            width: 1.2,
                          ),
                          boxShadow: _isFloorOn
                              ? [
                                  BoxShadow(
                                    color: _effectiveLightColor.withValues(
                                        alpha: 0.55),
                                    blurRadius: 10,
                                  ),
                                ]
                              : const [],
                        ),
                        child: Icon(
                          _isFloorOn
                              ? Icons.bolt_rounded
                              : Icons.power_settings_new_rounded,
                          size: 14,
                          color: _isFloorOn
                              ? _effectiveLightColor
                              : Colors.white70,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // 4. Optional top-left pill if Salon ceiling bulb is also mapped
              if (widget.ceilingLampName != null)
                Positioned(
                  top: 10,
                  left: 12,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.68),
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: widget.ceilingLampControllable
                          ? widget.onToggleCeilingLamp
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              widget.ceilingLampOn == true
                                  ? Icons.lightbulb
                                  : Icons.lightbulb_outline,
                              size: 15,
                              color: widget.ceilingLampOn == true
                                  ? const Color(0xFFFFD54F)
                                  : Colors.white70,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              widget.ceilingLampOn == true
                                  ? 'Tavan · Açık'
                                  : 'Tavan · Kapalı',
                              style: const TextStyle(
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

              // 5. Subtle hint badge in bottom-right of the room image
              Positioned(
                bottom: 8,
                right: 12,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.52),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Çubuğa dokun: Aç / Kapat',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildControlDock(
    BuildContext context, {
    required ThemeData theme,
    required ColorScheme colors,
    required bool hasBulb,
    required String statusText,
  }) {
    final activeColor = _effectiveLightColor;
    final enabled = hasBulb && widget.floorLampControllable;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top row: Lamp title + status + 1-tap power / pair button
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _isFloorOn
                      ? activeColor.withValues(alpha: 0.22)
                      : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isFloorOn
                        ? activeColor.withValues(alpha: 0.75)
                        : colors.outlineVariant,
                  ),
                ),
                child: Icon(
                  Icons.tungsten_rounded,
                  size: 20,
                  color: _isFloorOn ? activeColor : colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.floorLampName ?? 'Salon · Çubuk LED Lambader',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      statusText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: widget.floorLampRetryable
                            ? colors.error
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (!hasBulb)
                FilledButton.icon(
                  onPressed: _openQuickPairSheet,
                  icon: const Icon(Icons.link, size: 17),
                  label: const Text('Eşleştir'),
                )
              else
                FilledButton.tonalIcon(
                  onPressed: enabled ? _handleFloorTap : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: _isFloorOn
                        ? activeColor.withValues(alpha: 0.26)
                        : null,
                  ),
                  icon: Icon(
                    widget.floorLampRetryable
                        ? Icons.refresh
                        : Icons.power_settings_new_rounded,
                    size: 18,
                  ),
                  label: Text(
                    widget.floorLampRetryable
                        ? 'Tekrar'
                        : (_isFloorOn ? 'Kapat' : 'Aç'),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 8),

          // Brightness slider row
          Row(
            children: [
              Icon(
                Icons.brightness_low_rounded,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 5,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 8,
                    ),
                  ),
                  child: Slider(
                    value: _localDimming,
                    min: 10,
                    max: 100,
                    divisions: 90,
                    onChanged: enabled
                        ? (v) {
                            setState(() {
                              _draggingDimming = true;
                              _localDimming = v;
                            });
                          }
                        : null,
                    onChangeEnd: enabled
                        ? (v) {
                            setState(() {
                              _draggingDimming = false;
                            });
                            widget.onChangeBrightness?.call(v.round());
                          }
                        : null,
                  ),
                ),
              ),
              SizedBox(
                width: 42,
                child: Text(
                  '%${_localDimming.round()}',
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 4),

          // Color palette row + custom RGB wheel button
          SizedBox(
            height: 36,
            child: Row(
              children: [
                Expanded(
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _presets.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final preset = _presets[index];
                      final isSelected = _isFloorOn &&
                          (_effectiveLightColor.toARGB32() ==
                              preset.previewColor.toARGB32());
                      return GestureDetector(
                        onTap: enabled ? () => _selectPreset(preset) : null,
                        child: Tooltip(
                          message: preset.label,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: enabled
                                  ? preset.previewColor
                                  : preset.previewColor.withValues(alpha: 0.35),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? colors.primary
                                    : Colors.black26,
                                width: isSelected ? 2.6 : 1.0,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: preset.previewColor
                                            .withValues(alpha: 0.55),
                                        blurRadius: 8,
                                      ),
                                    ]
                                  : const [],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Özel RGB Renk Seç',
                  visualDensity: VisualDensity.compact,
                  onPressed: enabled ? _openRgbPickerSheet : null,
                  icon: const Icon(Icons.palette_outlined, size: 19),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SalonLightPainter extends CustomPainter {
  const _SalonLightPainter({
    required this.isOn,
    required this.color,
    required this.brightness,
  });

  final bool isOn;
  final Color color;
  final double brightness;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Exact normalized coordinates of the LED strip inside salon_3d.png
    final top = Offset(0.2775 * w, 0.414 * h);
    final bottom = Offset(0.2825 * w, 0.656 * h);

    if (!isOn) {
      // Subtle ambient night veil over the room when lamp is off
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0x340B0E14),
      );

      // Paint matte dark charcoal over the unlit diffuser strip so it looks off
      final offBarPaint = Paint()
        ..color = const Color(0xFF1E2025)
        ..strokeWidth = (0.0072 * w).clamp(2.2, 8.0)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(top, bottom, offBarPaint);
      return;
    }

    final intensity = brightness.clamp(0.10, 1.0);

    // 1. Wide soft wall & floor wash behind the vertical LED bar
    final wallWashCenter = Offset(0.242 * w, 0.520 * h);
    final wallWashRect = Rect.fromCenter(
      center: wallWashCenter,
      width: 0.30 * w,
      height: 0.44 * h,
    );
    final wallWashPaint = Paint()
      ..blendMode = BlendMode.screen
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: (0.22 + 0.44 * intensity).clamp(0.0, 0.72)),
          color.withValues(alpha: (0.08 + 0.18 * intensity).clamp(0.0, 0.35)),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(wallWashRect);
    canvas.drawOval(wallWashRect, wallWashPaint);

    // 2. Vertical aura along the bar
    final auraPaint = Paint()
      ..blendMode = BlendMode.screen
      ..color = color.withValues(alpha: (0.35 + 0.50 * intensity).clamp(0.0, 0.9))
      ..strokeWidth = (0.026 * w).clamp(8.0, 26.0)
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, (0.015 * w).clamp(4.0, 16.0));
    canvas.drawLine(top, bottom, auraPaint);

    // 3. Crisp glowing LED core on the bar itself
    final coreColor = Color.lerp(color, Colors.white, 0.38 + 0.25 * intensity)!;
    final corePaint = Paint()
      ..color = coreColor
      ..strokeWidth = (0.0074 * w).clamp(2.4, 8.5)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(top, bottom, corePaint);
  }

  @override
  bool shouldRepaint(covariant _SalonLightPainter old) =>
      old.isOn != isOn ||
      old.color != color ||
      old.brightness != brightness;
}
