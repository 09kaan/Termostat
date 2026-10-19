import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Full-page, interactive and editable room scene. Device reports, not commands,
/// determine its lighting. Installation belongs in the separate settings sheet.
class RoomOverview extends StatelessWidget {
  const RoomOverview({
    super.key,
    required this.isLightOn,
    required this.pending,
    required this.lightName,
    required this.onToggle,
    this.onControls,
    this.onSetup,
    this.temperature,
    this.humidity,
    this.roomName = 'Odam',
    this.dimensions = '3,5 × 3,5 m',
    this.area = '12,25 m²',
    this.roomWidth = 3.5,
    this.roomDepth = 3.5,
    this.showSensor = true,
    this.showLamp = true,
    this.floorLamp = false,
    this.ambientOn,
    this.planAspect,
  });

  final bool? isLightOn;
  final bool? ambientOn;
  final double? planAspect;
  final bool pending;
  final String? lightName;
  final VoidCallback? onToggle;
  final VoidCallback? onControls;
  final VoidCallback? onSetup;
  final double? temperature;
  final double? humidity;
  final String roomName, dimensions, area;
  final double? roomWidth, roomDepth;
  final bool showSensor, showLamp, floorLamp;

  String get _status => !showLamp
      ? 'Bu odaya atanmış kayıtlı lamba yok'
      : lightName == null
          ? 'Odaya bir ampul bağla'
          : pending
              ? 'Ampul yanıtı bekleniyor'
              : isLightOn == null
                  ? 'Güncel ampul durumu yok'
                  : isLightOn!
                      ? 'Işık açık'
                      : 'Işık kapalı';

  @override
  Widget build(BuildContext context) {
    // Keep the scene full-height on phones, with a safe scroll fallback for
    // landscape, accessibility text sizes, and split-screen windows.
    return LayoutBuilder(builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
      final scrolling = !constraints.hasBoundedHeight ||
          constraints.maxHeight < (showSensor ? 720 : 580) ||
          constraints.maxWidth < 360 ||
          scale > 1.2;
      final content = _content(context, scrolling: scrolling);
      if (scrolling) return SingleChildScrollView(child: content);
      return content;
    });
  }

  Widget _scene(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 650),
        child: AspectRatio(
          aspectRatio: 1.12,
          child: Semantics(
            label: '$roomName, $dimensions. $_status',
            child: Stack(fit: StackFit.expand, children: [
              CustomPaint(
                  painter: _RoomPainter(
                dark: dark,
                warm: AppAppearance.isWarm(context),
                isLightOn: ambientOn ?? isLightOn,
                roomWidth: roomWidth,
                roomDepth: roomDepth,
                planAspect: planAspect,
                fontFamily: theme.textTheme.bodyMedium?.fontFamily,
              )),
              if (showLamp)
                Align(
                  alignment: const Alignment(0, -.10),
                  child: GestureDetector(
                    onLongPress: onControls,
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: IconButton.filledTonal(
                        key: const ValueKey('room-lamp'),
                        onPressed: onToggle,
                        iconSize: 32,
                        style: IconButton.styleFrom(
                          backgroundColor: isLightOn == true
                              ? const Color(0xFFFFDF9C)
                              : colors.secondaryContainer,
                          foregroundColor: isLightOn == true
                              ? const Color(0xFF513A0A)
                              : colors.onSecondaryContainer,
                        ),
                        icon: floorLamp
                            ? Semantics(
                                label: _status,
                                child: const FloorLampIcon(size: 32))
                            : Icon(
                                isLightOn == true
                                    ? Icons.lightbulb
                                    : isLightOn == false
                                        ? Icons.lightbulb_outline
                                        : Icons.question_mark,
                                semanticLabel: onToggle == null
                                    ? _status
                                    : isLightOn == true
                                        ? 'Işığı kapat'
                                        : 'Işığı aç'),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, {required bool scrolling}) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 12, runSpacing: 4, children: [
            Text(dimensions, style: theme.textTheme.titleMedium),
            Text('$area · Eşyasız alan', style: theme.textTheme.bodyMedium),
          ]),
          if (showSensor) ...[
            const SizedBox(height: 20),
            Wrap(spacing: 32, runSpacing: 12, children: [
              _Reading(
                  icon: Icons.thermostat,
                  label: 'Sıcaklık',
                  value: temperature == null
                      ? '—'
                      : '${temperature!.toStringAsFixed(1).replaceAll('.', ',')} °C'),
              _Reading(
                  icon: Icons.water_drop_outlined,
                  label: 'Nem',
                  value: humidity == null ? '—' : '%${humidity!.round()}'),
            ]),
            const SizedBox(height: 4),
            Text('Termostat sensörünün son ölçümü',
                style: theme.textTheme.bodyMedium),
          ],
        ]),
      ),
      if (scrolling)
        SizedBox(
            height:
                (MediaQuery.sizeOf(context).width / 1.12).clamp(220.0, 500.0),
            child: _scene(context))
      else
        Expanded(child: _scene(context)),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(lightName ?? roomName, style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(
                pending
                    ? Icons.hourglass_top
                    : isLightOn == null
                        ? Icons.cloud_off_outlined
                        : Icons.circle_outlined,
                size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(_status, style: theme.textTheme.bodyLarge)),
          ]),
          const SizedBox(height: 8),
          Text(
              !showLamp
                  ? 'Ev ayarlarından bu odaya ampul bağlayabilirsin.'
                  : pending
                      ? 'Görünüm son bildirilen durumu korur.'
                      : onToggle != null
                          ? 'Ampule dokun: aç / kapat. Basılı tut: kontroller.'
                          : lightName == null
                              ? 'Ev ayarlarından bu lamba konumuna bir ampul bağlayabilirsin.'
                              : 'Güncel yanıt gelince oda kontrolü etkinleşir.',
              style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const ValueKey('room-controls'),
            onPressed: lightName == null ? onSetup : onControls,
            icon: Icon(lightName == null ? Icons.add : Icons.tune),
            label: Text(
                lightName == null ? 'Ev ayarlarını aç' : 'Işık kontrolleri'),
          ),
        ]),
      ),
    ]);
  }
}

class _Reading extends StatelessWidget {
  const _Reading(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 22),
        const SizedBox(width: 8),
        Flexible(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
              Text(value, style: Theme.of(context).textTheme.titleLarge),
            ])),
      ]);
}

class _RoomPainter extends CustomPainter {
  const _RoomPainter(
      {required this.dark,
      this.warm = false,
      required this.isLightOn,
      this.roomWidth = 3.5,
      this.roomDepth = 3.5,
      this.planAspect,
      this.fontFamily});
  final bool dark;
  final bool warm;
  final bool? isLightOn;
  final String? fontFamily;
  final double? roomWidth, roomDepth;
  final double? planAspect;

  Path _polygon(List<Offset> points) => Path()..addPolygon(points, true);

  @override
  void paint(Canvas canvas, Size size) {
    Offset p(double x, double y) => Offset(x * size.width, y * size.height);
    final w = planAspect ?? roomWidth ?? 2.0,
        d = planAspect != null ? 1.0 : roomDepth ?? 2.0;
    final maxSide = w > d ? w : d;
    final u = p(.42 * w / maxSide, .23 * w / maxSide);
    final v = p(-.42 * d / maxSide, .23 * d / maxSide);
    final back = p(.50, .62) - (u + v) / 2;
    final left = back + v;
    final right = back + u;
    final front = back + u + v;
    final backTop = back - p(0, .29);
    final leftTop = left - p(0, .29);
    final rightTop = right - p(0, .29);
    final floor = _polygon([back, right, front, left]);
    final lit = isLightOn == true;
    final off = isLightOn == false;
    final floorColor = warm
        ? (dark
            ? const Color(0xFF625142)
            : lit
                ? const Color(0xFFE8D4AC)
                : const Color(0xFFE1D6C2))
        : dark
            ? (lit ? const Color(0xFF897855) : const Color(0xFF494D54))
            : (lit
                ? const Color(0xFFE8D4AC)
                : off
                    ? const Color(0xFFB9BEC7)
                    : const Color(0xFFD7D6D2));
    final wallLeft = warm
        ? (dark ? const Color(0xFF6F5D4C) : const Color(0xFFE9DFCC))
        : dark
            ? (lit ? const Color(0xFF77715F) : const Color(0xFF444A53))
            : (lit ? const Color(0xFFF2E6CC) : const Color(0xFFD9DEE4));
    final wallRight = warm
        ? (dark ? const Color(0xFF57483D) : const Color(0xFFDAD0BB))
        : dark
            ? (lit ? const Color(0xFF655F50) : const Color(0xFF353C47))
            : (lit ? const Color(0xFFE3D6B9) : const Color(0xFFC9D0DA));
    final outline = Paint()
      ..color = dark ? const Color(0xFF9DA5AF) : const Color(0xFF788390)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeJoin = StrokeJoin.round;

    canvas.drawShadow(floor, Colors.black, 8, false);
    for (final wall in <(Path, Color)>[
      (_polygon([left, back, backTop, leftTop]), wallLeft),
      (_polygon([back, right, rightTop, backTop]), wallRight),
    ]) {
      canvas.drawPath(wall.$1, Paint()..color = wall.$2);
      canvas.drawPath(wall.$1, outline);
    }
    canvas.drawPath(floor, Paint()..color = floorColor);
    canvas.save();
    canvas.clipPath(floor);
    final seam = Paint()
      ..color = (dark ? Colors.white : Colors.black).withAlpha(18)
      ..strokeWidth = 1;
    for (var i = 1; i < 7; i++) {
      final t = i / 7;
      canvas.drawLine(
          Offset.lerp(back, right, t)!, Offset.lerp(left, front, t)!, seam);
      canvas.drawLine(
          Offset.lerp(back, left, t)!, Offset.lerp(right, front, t)!, seam);
    }
    if (lit) {
      final glow = Rect.fromCenter(
        center: p(.5, .60),
        width: size.width * .85,
        height: size.height * .55,
      );
      canvas.drawRect(
          glow,
          Paint()
            ..shader = const RadialGradient(
              colors: [Color(0x65FFE1A0), Color(0x00FFE1A0)],
            ).createShader(glow));
    }
    canvas.restore();
    canvas.drawPath(floor, outline);
    final fascia = _polygon([
      left,
      front,
      right,
      right + p(0, .03),
      front + p(0, .03),
      left + p(0, .03)
    ]);
    canvas.drawPath(
        fascia,
        Paint()
          ..color = dark ? const Color(0xFF59616B) : const Color(0xFFA9B0B9));
    canvas.drawPath(fascia, outline);
    // Dimension labels are painted, not gesture targets; controls stay native.
    void dimension(String text, Offset position) {
      final tp = TextPainter(
        text: TextSpan(
            text: text,
            style: TextStyle(
              color: dark ? const Color(0xFFDFE2E6) : const Color(0xFF4B5563),
              fontSize: 14,
              fontFamily: fontFamily,
            )),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, position - Offset(tp.width / 2, 0));
    }

    if (roomWidth != null && roomDepth != null) {
      dimension('${roomWidth!.toString().replaceAll('.', ',')} m',
          Offset.lerp(left, front, .5)! + p(-.03, .04));
      dimension('${roomDepth!.toString().replaceAll('.', ',')} m',
          Offset.lerp(right, front, .5)! + p(.03, .04));
    }
  }

  @override
  bool shouldRepaint(covariant _RoomPainter oldDelegate) =>
      oldDelegate.dark != dark ||
      oldDelegate.warm != warm ||
      oldDelegate.isLightOn != isLightOn ||
      oldDelegate.fontFamily != fontFamily ||
      oldDelegate.roomWidth != roomWidth ||
      oldDelegate.roomDepth != roomDepth ||
      oldDelegate.planAspect != planAspect;
}

/// Both setup and light controls open above the room, without creating a
/// second horizontal page or covering the scene with permanent setup widgets.
class RoomPanel extends StatelessWidget {
  const RoomPanel({super.key, required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .88,
        child: Material(
            color: Theme.of(context).colorScheme.surface,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 12, 12),
                child: Row(children: [
                  Expanded(
                      child: Text(title,
                          style: Theme.of(context).textTheme.titleLarge)),
                  IconButton(
                      tooltip: 'Kapat',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close)),
                ]),
              ),
              const Divider(height: 1),
              Expanded(child: child),
            ])),
      );
}

/// Presentation-only setup panel; Firebase logic stays in WizLightsScreen.
class RoomSettingsContent extends StatelessWidget {
  const RoomSettingsContent({
    super.key,
    required this.connected,
    this.timeReady = true,
    required this.bridgeOnline,
    required this.owner,
    required this.lights,
    required this.selectedLight,
    required this.onSelected,
    required this.onAdd,
    required this.onCopy,
    required this.controls,
    this.planAssignments,
  });
  final bool connected;
  final bool timeReady;
  final bool bridgeOnline;
  final String owner;
  final Map<String, String> lights;
  final String? selectedLight;
  final ValueChanged<String?> onSelected;
  final VoidCallback onAdd;
  final VoidCallback onCopy;
  final List<Widget> controls;
  final Widget? planAssignments;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          BridgeConnectionCard(
              connected: connected,
              timeReady: timeReady,
              bridgeOnline: bridgeOnline),
          const SizedBox(height: 16),
          if (planAssignments != null)
            planAssignments!
          else if (lights.isNotEmpty)
            DropdownButtonFormField<String>(
              key: ValueKey(selectedLight),
              value: selectedLight,
              isExpanded: true,
              decoration:
                  const InputDecoration(labelText: 'Odada gösterilen ampul'),
              items: [
                for (final light in lights.entries)
                  DropdownMenuItem(
                      value: light.key,
                      child: Text(light.value,
                          maxLines: 1, overflow: TextOverflow.ellipsis))
              ],
              onChanged: onSelected,
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Ampul ekle')),
          const SizedBox(height: 12),
          if (lights.isEmpty)
            const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                    'WiZ uygulamasında yerel iletişime izin ver. Sonra ampulü adı ve yerel IP adresiyle ekle.')),
          ExpansionTile(title: const Text('ESP kurulumu'), children: [
            const Padding(
                padding: EdgeInsets.all(12),
                child: Text('ESP kurulumu için kullanıcı kimliği')),
            Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(owner)),
            TextButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy),
                label: const Text('Kimliği kopyala')),
          ]),
          const SizedBox(height: 16),
          Text('Ampuller ve ayrıntılı kontroller',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ...controls,
        ],
      );
}

/// The badge means a recent ESP heartbeat, not proof that a lamp command ran.
class BridgeConnectionCard extends StatelessWidget {
  const BridgeConnectionCard(
      {super.key,
      required this.connected,
      required this.timeReady,
      required this.bridgeOnline});
  final bool connected;
  final bool timeReady;
  final bool bridgeOnline;

  @override
  Widget build(BuildContext context) {
    final verified = connected && timeReady && bridgeOnline;
    final colors = Theme.of(context).colorScheme;
    return Card(
      key: const ValueKey('bridge-connection'),
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                  verified
                      ? Icons.check_circle_outline
                      : Icons.cloud_off_outlined,
                  color: verified
                      ? (Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF8FD0B4)
                          : const Color(0xFF256548))
                      : colors.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(
                        !connected
                            ? 'Telefonun Firebase bağlantısı yok'
                            : !timeReady
                                ? 'Bağlantı doğrulanıyor'
                                : verified
                                    ? 'ESP köprüsü yanıt veriyor'
                                    : 'ESP köprüsünden güncel yanıt yok',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                        verified
                            ? 'Son 90 saniye içinde cihaz bildirimi alındı.'
                            : !connected
                                ? 'Telefonun internet bağlantısını kontrol et.'
                                : !timeReady
                                    ? 'Sunucu saati alındığında cihazın güncelliği doğrulanır.'
                                    : 'ESP’nin internet bağlantısını ve çalıştığını kontrol et.',
                        style: Theme.of(context).textTheme.bodyMedium),
                  ])),
            ],
          )),
    );
  }
}

/// Simple editable floor lamp silhouette; not a font-dependent emoji.
class FloorLampIcon extends StatelessWidget {
  const FloorLampIcon({super.key, this.size = 20, this.color});
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
          painter: _FloorLampPainter(color ??
              IconTheme.of(context).color ??
              Theme.of(context).colorScheme.onSurface)));
}

class _FloorLampPainter extends CustomPainter {
  const _FloorLampPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
        Path()
          ..moveTo(8, 3)
          ..lineTo(16, 3)
          ..lineTo(20, 11)
          ..lineTo(4, 11)
          ..close(),
        paint);
    canvas.drawLine(const Offset(12, 11), const Offset(12, 21), paint);
    canvas.drawLine(const Offset(7, 21), const Offset(17, 21), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FloorLampPainter old) => old.color != color;
}
