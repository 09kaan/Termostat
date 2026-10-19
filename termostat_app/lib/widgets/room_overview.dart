import 'package:flutter/material.dart';

/// Editable, lightweight isometric scene. No 3D engine or image asset needed.
/// [isLightOn] must come from a fresh device report, never a requested command.
class RoomOverview extends StatelessWidget {
  const RoomOverview({
    super.key,
    required this.isLightOn,
    required this.pending,
    required this.lightName,
    required this.onToggle,
    this.temperature,
    this.humidity,
  });

  final bool? isLightOn;
  final bool pending;
  final String? lightName;
  final VoidCallback? onToggle;
  final double? temperature;
  final double? humidity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final status = lightName == null
        ? 'Henüz ampul eklenmedi'
        : pending
            ? 'Komut bekleniyor · görünüm son bildirilen durum'
            : isLightOn == null
                ? 'Güncel ampul durumu yok'
                : isLightOn!
                    ? 'Ampul bildirimi: Açık'
                    : 'Ampul bildirimi: Kapalı';
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Odam', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text('3,5 × 3,5 m · 12,25 m²', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Semantics(
              label: 'Çapraz açıdan görünen, kare ve eşyasız oda. $status',
              child: AspectRatio(
                aspectRatio: 1.18,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomPaint(
                      painter: _RoomPainter(
                          dark: dark,
                          isLightOn: isLightOn,
                          fontFamily: theme.textTheme.bodyMedium?.fontFamily),
                    ),
                    Align(
                      alignment: const Alignment(0, -0.10),
                      child: Semantics(
                        button: true,
                        label: pending
                            ? 'Ampul yanıtı bekleniyor'
                            : isLightOn == true
                                ? 'Oda ışığını kapat'
                                : 'Oda ışığını aç',
                        child: SizedBox(
                          width: 64,
                          height: 64,
                          child: IconButton.filledTonal(
                            onPressed: onToggle,
                            tooltip: onToggle == null
                                ? status
                                : isLightOn == true
                                    ? 'Işığı kapat'
                                    : 'Işığı aç',
                            iconSize: 30,
                            icon: Icon(isLightOn == true
                                ? Icons.lightbulb
                                : isLightOn == false
                                    ? Icons.lightbulb_outline
                                    : Icons.question_mark),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (lightName != null) ...[
              Text(lightName!, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
            ],
            Text(status, style: theme.textTheme.bodyMedium),
            if (pending) ...[
              const SizedBox(height: 8),
              const Text('Yeni durum, ampul yanıt verdiğinde gösterilir.'),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _Reading(
                  icon: Icons.thermostat,
                  text: temperature == null
                      ? 'Sıcaklık: —'
                      : '${temperature!.toStringAsFixed(1).replaceAll('.', ',')} °C',
                ),
                _Reading(
                  icon: Icons.water_drop_outlined,
                  text:
                      humidity == null ? 'Nem: —' : 'Nem %${humidity!.round()}',
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Son sensör ölçümü · ayrıntılı kontroller aşağıda.'),
          ],
        ),
      ),
    );
  }
}

class _Reading extends StatelessWidget {
  const _Reading({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 4),
          Text(text, style: Theme.of(context).textTheme.titleMedium),
        ],
      );
}

class _RoomPainter extends CustomPainter {
  const _RoomPainter(
      {required this.dark, required this.isLightOn, this.fontFamily});
  final bool dark;
  final bool? isLightOn;
  final String? fontFamily;

  Path _polygon(List<Offset> points) => Path()..addPolygon(points, true);

  @override
  void paint(Canvas canvas, Size size) {
    Offset p(double x, double y) => Offset(x * size.width, y * size.height);
    final back = p(.50, .39);
    final left = p(.08, .62);
    final front = p(.50, .85);
    final right = p(.92, .62);
    final backTop = p(.50, .10);
    final leftTop = p(.08, .33);
    final rightTop = p(.92, .33);
    final floor = _polygon([back, right, front, left]);
    final lit = isLightOn == true;
    final off = isLightOn == false;
    final floorColor = dark
        ? (lit ? const Color(0xFF897855) : const Color(0xFF494D54))
        : (lit
            ? const Color(0xFFE8D4AC)
            : off
                ? const Color(0xFFB9BEC7)
                : const Color(0xFFD7D6D2));
    final wallLeft = dark
        ? (lit ? const Color(0xFF77715F) : const Color(0xFF444A53))
        : (lit ? const Color(0xFFF2E6CC) : const Color(0xFFD9DEE4));
    final wallRight = dark
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
    final fascia =
        _polygon([left, front, right, p(.92, .65), p(.50, .88), p(.08, .65)]);
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

    dimension('3,5 m', p(.24, .83));
    dimension('3,5 m', p(.76, .83));
  }

  @override
  bool shouldRepaint(covariant _RoomPainter oldDelegate) =>
      oldDelegate.dark != dark ||
      oldDelegate.isLightOn != isLightOn ||
      oldDelegate.fontFamily != fontFamily;
}
