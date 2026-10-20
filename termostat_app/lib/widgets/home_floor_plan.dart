import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/home_plan.dart';
import '../theme/app_theme.dart';
import 'room_overview.dart' show FloorLampIcon;

/// Editable CAD geometry; no raster floorplan or pretend device values.
class HomeFloorPlan extends StatefulWidget {
  const HomeFloorPlan({
    super.key,
    required this.states,
    required this.onRoom,
    required this.onLampTap,
    required this.onLampControls,
    required this.onSetup,
  });
  final Map<String, FixtureState> states;
  final ValueChanged<String> onRoom, onLampTap, onLampControls;
  final VoidCallback onSetup;
  @override
  State<HomeFloorPlan> createState() => _HomeFloorPlanState();
}

class _HomeFloorPlanState extends State<HomeFloorPlan> {
  final _transform = TransformationController();
  bool _zoomed = false;
  @override
  void initState() {
    super.initState();
    _transform.addListener(_trackZoom);
  }

  void _trackZoom() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.02;
    if (zoomed != _zoomed && mounted) setState(() => _zoomed = zoomed);
  }

  @override
  void dispose() {
    _transform.removeListener(_trackZoom);
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = _CadPalette(
      Theme.of(context).brightness == Brightness.dark,
      AppAppearance.isWarm(context),
    );
    final visible = HomePlan.fixtures
        .where((f) => widget.states[f.id]?.assigned == true)
        .toList();
    final large = MediaQuery.textScalerOf(context).scale(16) > 20;
    final drawingTextScale = TextScaler.linear(
      (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1.0, 1.15),
    );
    final failed =
        visible.where((f) => widget.states[f.id]?.retryable == true).toList();
    Widget plan() => LayoutBuilder(
          builder: (context, box) {
            final width = math.min(
              box.maxWidth,
              box.maxHeight * HomePlan.size.aspectRatio,
            );
            return Center(
              child: SizedBox(
                width: width,
                height: width / HomePlan.size.aspectRatio,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ColoredBox(
                        color: palette.paper,
                        child: AspectRatio(
                          aspectRatio: HomePlan.size.aspectRatio,
                          child: InteractiveViewer(
                            key: const ValueKey('plan-zoom'),
                            transformationController: _transform,
                            minScale: 1,
                            maxScale: 2.5,
                            panEnabled: _zoomed,
                            child: LayoutBuilder(
                              builder: (context, box) {
                                final sx = box.maxWidth / HomePlan.size.width,
                                    sy = box.maxHeight / HomePlan.size.height;
                                return Stack(
                                  children: [
                                    Positioned.fill(
                                      child: CustomPaint(
                                        painter: _CadPlanPainter(
                                          palette,
                                          widget.states,
                                        ),
                                      ),
                                    ),
                                    for (final r in HomePlan.rooms)
                                      Positioned(
                                        left: r.bounds.left * sx,
                                        top: r.bounds.top * sy,
                                        width: r.bounds.width * sx,
                                        height: r.bounds.height * sy,
                                        child: Semantics(
                                          button: true,
                                          label: '${r.name}, ${r.dimensions}',
                                          child: Material(
                                            color: Colors.transparent,
                                            child: InkWell(
                                              key:
                                                  ValueKey('plan-room-${r.id}'),
                                              onTap: () => widget.onRoom(r.id),
                                              child: Center(
                                                child: Transform.translate(
                                                  offset: HomePlan.fixturesFor(
                                                              r.id)
                                                          .any(
                                                    (f) =>
                                                        widget.states[f.id]
                                                            ?.assigned ==
                                                        true,
                                                  )
                                                      ? Offset(
                                                          r.labelOffset.dx * sx,
                                                          r.labelOffset.dy * sy,
                                                        )
                                                      : Offset.zero,
                                                  child:
                                                      // Very small Hol retains its accessible name in the room links.
                                                      r.id == 'small_hall' &&
                                                              visible.any(
                                                                (f) =>
                                                                    f.roomId ==
                                                                    r.id,
                                                              )
                                                          ? const SizedBox()
                                                          : RotatedBox(
                                                              quarterTurns:
                                                                  r.id == 'hall' &&
                                                                          large
                                                                      ? 1
                                                                      : 0,
                                                              child: Text(
                                                                r.label,
                                                                textScaler:
                                                                    drawingTextScale,
                                                                textAlign:
                                                                    TextAlign
                                                                        .center,
                                                                style:
                                                                    TextStyle(
                                                                  fontSize: 14,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w500,
                                                                  color: palette
                                                                      .text,
                                                                ),
                                                              ),
                                                            ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    // Native 44px buttons, independent of room taps and zoom level.
                                    for (final f in visible)
                                      Positioned(
                                        left: f.position.dx * sx - 22,
                                        top: f.position.dy * sy - 22,
                                        width: 44,
                                        height: 44,
                                        child: CadLampButton(
                                          fixture: f,
                                          state: widget.states[f.id]!,
                                          onTap: () => widget.onLampTap(f.id),
                                          onControls: () =>
                                              widget.onLampControls(f.id),
                                        ),
                                      ),
                                    Positioned(
                                      left: 304 * sx,
                                      top: 708 * sy,
                                      width: 76 * sx,
                                      child: Text(
                                        'Giriş',
                                        textScaler: drawingTextScale,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: palette.text,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Material(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        child: IconButton(
                          key: const ValueKey('reset-plan'),
                          tooltip: 'Planı ekrana sığdır',
                          onPressed: () =>
                              _transform.value = Matrix4.identity(),
                          icon: const Icon(Icons.center_focus_strong),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
    Widget? notice;
    if (failed.isNotEmpty) {
      final dark = Theme.of(context).brightness == Brightness.dark;
      final noticeSurface =
          dark ? const Color(0xFF493514) : const Color(0xFFFFF0D6);
      final noticeText =
          dark ? const Color(0xFFFFDD9A) : const Color(0xFF5A3B00);
      notice = Semantics(
        liveRegion: true,
        child: Card(
          key: const ValueKey('plan-retry-notice'),
          color: noticeSurface,
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: noticeText,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${failed.length} lamba yanıt vermiyor.',
                    style: TextStyle(color: noticeText),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    if (failed.length == 1) {
                      if (widget.states[failed.single.id]?.controllable ==
                          true) {
                        widget.onLampTap(failed.single.id);
                      } else {
                        widget.onLampControls(failed.single.id);
                      }
                    } else {
                      // No bulk command: the user chooses exactly one fixture.
                      showModalBottomSheet<void>(
                        context: context,
                        showDragHandle: true,
                        builder: (sheet) => SafeArea(
                          child: ListView(
                            shrinkWrap: true,
                            children: [
                              const ListTile(
                                title: Text('Tekrar denenecek lambayı seç'),
                              ),
                              for (final f in failed)
                                ListTile(
                                  title: Text(
                                    '${HomePlan.room(f.roomId).name} · ${f.type}',
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () {
                                    Navigator.pop(sheet);
                                    if (widget.states[f.id]?.controllable ==
                                        true) {
                                      widget.onLampTap(f.id);
                                    } else {
                                      widget.onLampControls(f.id);
                                    }
                                  },
                                ),
                            ],
                          ),
                        ),
                      );
                    }
                  },
                  child: const Text('Tekrar dene'),
                ),
              ],
            ),
          ),
        ),
      );
    } else if (visible.isEmpty) {
      notice = Padding(
        padding: const EdgeInsets.only(top: 8),
        child: OutlinedButton.icon(
          onPressed: widget.onSetup,
          icon: const Icon(Icons.add),
          label: const Text('Lambaları bağla'),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        final accessible = box.maxHeight < 360 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.3;
        if (accessible) {
          return SingleChildScrollView(
            key: const ValueKey('plan-accessible-scroll'),
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                SizedBox(
                  height: math.max(320, box.maxHeight - 100),
                  child: plan(),
                ),
                if (notice != null) notice,
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: plan()),
              if (notice != null) ...[const SizedBox(height: 8), notice],
            ],
          ),
        );
      },
    );
  }
}

class CadLampButton extends StatelessWidget {
  const CadLampButton({
    super.key,
    required this.fixture,
    required this.state,
    required this.onTap,
    required this.onControls,
  });
  final PlanFixture fixture;
  final FixtureState state;
  final VoidCallback onTap, onControls;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = state.on == true
        ? (dark ? const Color(0xFFFFD375) : const Color(0xFF976300))
        : (dark ? const Color(0xFFCCC3B4) : const Color(0xFF6B6256));
    return GestureDetector(
      key: ValueKey('plan-lamp-gesture-${fixture.id}'),
      onLongPress: onControls,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: state.on == true
              ? [
                  BoxShadow(
                    color: const Color(0x55FFD36B),
                    blurRadius: 16,
                    spreadRadius: 0,
                  ),
                ]
              : const [],
        ),
        child: TooltipTheme(
          data: TooltipTheme.of(context)
              .copyWith(triggerMode: TooltipTriggerMode.manual),
          child: IconButton(
            key: ValueKey('plan-lamp-${fixture.id}'),
            tooltip:
                '${fixture.name}: ${state.label}${state.retryable ? ' · Aynı komutu tekrar dene' : ''}',
            padding: const EdgeInsets.all(8),
            onPressed: state.controllable ? onTap : null,
            disabledColor: color,
            color: color,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                if (fixture.floor)
                  FloorLampIcon(
                    size: 26,
                    color: state.on == true
                        ? (dark
                            ? const Color(0xFFFFBC7F)
                            : const Color(0xFFA44F13))
                        : color,
                  )
                else
                  Icon(
                    state.on == true
                        ? Icons.lightbulb
                        : Icons.lightbulb_outline,
                    size: 26,
                    color: color,
                  ),
                if (state.pending || state.retryable || state.on == null)
                  Positioned(
                    right: -5,
                    top: -5,
                    child: Icon(
                      state.pending
                          ? Icons.hourglass_top
                          : state.retryable
                              ? Icons.error_outline
                              : Icons.question_mark,
                      size: 12,
                      color: color,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CadPalette {
  const _CadPalette(this.dark, this.warm);
  final bool dark, warm;
  Color get paper => dark
      ? const Color(0xFF1B1C1E)
      : warm
          ? const Color(0xFFFAF6ED)
          : const Color(0xFFFAF9F4);
  Color get floor => dark
      ? const Color(0xFF303031)
      : warm
          ? const Color(0xFFF0E7D7)
          : const Color(0xFFEFECE4);
  Color get ink => dark ? const Color(0xFFD1CBC2) : const Color(0xFF393632);
  Color get core => dark ? const Color(0xFF67625A) : const Color(0xFFBDB6AA);
  Color get text => dark ? const Color(0xFFF2EBDF) : const Color(0xFF39352F);
  Color get glass => dark ? const Color(0xFFA6CCEE) : const Color(0xFF476E90);
}

class _CadPlanPainter extends CustomPainter {
  const _CadPlanPainter(this.palette, this.states);
  final _CadPalette palette;
  final Map<String, FixtureState> states;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(
      size.width / HomePlan.size.width,
      size.height / HomePlan.size.height,
    );
    for (final room in HomePlan.rooms) {
      final lit =
          HomePlan.fixturesFor(room.id).any((f) => states[f.id]?.on == true);
      final fill = lit
          ? Color.alphaBlend(const Color(0x16FFD16F), palette.floor)
          : palette.floor;
      canvas.drawRect(room.bounds, Paint()..color = fill);
    }
    final segments = HomePlan.wallSegments();
    for (final (width, color) in [
      (8.0, palette.ink),
      (5.5, palette.core),
      (1.0, palette.ink),
    ]) {
      final pen = Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.square;
      for (final (a, b) in segments) {
        canvas.drawLine(a, b, pen);
      }
    }
    for (final opening in HomePlan.openings) {
      final a = opening.from, b = opening.to, delta = b - a;
      final horizontal = delta.dy.abs() < .001;
      if (opening.window) {
        final side = horizontal ? const Offset(0, 2.5) : const Offset(2.5, 0);
        canvas.drawLine(
          a,
          b,
          Paint()
            ..color = palette.glass.withAlpha(70)
            ..strokeWidth = 5,
        );
        final pen = Paint()
          ..color = palette.glass
          ..strokeWidth = 1;
        canvas.drawLine(a + side, b + side, pen);
        canvas.drawLine(a - side, b - side, pen);
        for (final t in [.0, 1 / 3, 2 / 3, 1.0]) {
          final p = Offset.lerp(a, b, t)!;
          canvas.drawLine(p - side, p + side, pen);
        }
      } else {
        final angle = math.atan2(delta.dy, delta.dx), radius = delta.distance;
        final end = angle + opening.swing * math.pi / 2;
        final pen = Paint()
          ..color = palette.ink
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke;
        canvas.drawLine(
          a,
          a + Offset(math.cos(end) * radius, math.sin(end) * radius),
          pen,
        );
        canvas.drawArc(
          Rect.fromCircle(center: a, radius: radius),
          angle,
          opening.swing * math.pi / 2,
          false,
          pen,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CadPlanPainter old) =>
      old.palette.dark != palette.dark ||
      old.palette.warm != palette.warm ||
      old.states != states;
}
