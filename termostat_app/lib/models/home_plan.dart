import 'package:flutter/material.dart';

/// Schematic traced from Kaan's sketch, not a scaled architectural survey.
class PlanRoom {
  const PlanRoom(this.id, this.name, this.label, this.bounds,
      {this.measureNote,
      this.width,
      this.depth,
      this.sensor = false,
      this.labelOffset = Offset.zero});
  final String id, name, label;
  final Rect bounds;
  final double? width, depth;
  final String? measureNote;
  final bool sensor;
  final Offset labelOffset;
  String get dimensions =>
      measureNote ??
      (width == null || depth == null
          ? 'Ölçü belirtilmedi'
          : '${number(width!)} × ${number(depth!)} m');
  String get area => width == null || depth == null
      ? 'Şematik görünüm'
      : '≈ ${number(width! * depth!)} m²';
  static String number(double n) => (n == n.roundToDouble()
          ? n.toStringAsFixed(0)
          : n.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), ''))
      .replaceAll('.', ',');
}

class PlanFixture {
  const PlanFixture(this.id, this.roomId, this.name, this.position,
      {this.floor = false});
  final String id, roomId, name;
  final Offset position;
  final bool floor;
  String get type => floor ? 'Ayaklı lamba' : 'Tavan lambası';
}

class PlanOpening {
  const PlanOpening(this.from, this.to, {this.window = false, this.swing = -1});
  final Offset from, to;
  final bool window;
  final int swing;
}

class HomePlan {
  // Layout is traced from the approved CAD concept, not a measured survey.
  static const size = Size(600, 755);
  static const bathroomWidth = 160.0;
  static const wcWidth = bathroomWidth * 2 / 3;
  static const rooms = <PlanRoom>[
    PlanRoom('bedroom', 'Yatak odası', 'Yatak odası',
        Rect.fromLTWH(24, 452, 261, 238),
        width: 3.5, depth: 3.5, sensor: true, labelOffset: Offset(0, 66)),
    PlanRoom('living', 'Salon', 'Salon', Rect.fromLTWH(285, 24, 275, 260),
        width: 4, depth: 4, labelOffset: Offset(0, 55)),
    PlanRoom('kitchen', 'Mutfak', 'Mutfak', Rect.fromLTWH(24, 284, 186, 168),
        width: 3, depth: 2, labelOffset: Offset(0, 35)),
    PlanRoom('bathroom', 'Banyo', 'Banyo',
        Rect.fromLTWH(400, 284, bathroomWidth, 176),
        labelOffset: Offset(0, 45)),
    PlanRoom('wc', 'WC', 'WC', Rect.fromLTWH(400, 460, wcWidth, 150),
        depth: 2,
        measureNote: 'Şematik genişlik: banyonun yaklaşık ⅔’ü',
        labelOffset: Offset(0, 50)),
    PlanRoom(
        'small_hall', 'Küçük koridor', 'Hol', Rect.fromLTWH(210, 357, 75, 95),
        width: 2, depth: 1, labelOffset: Offset(0, 30)),
    PlanRoom(
        'hall', 'Ana koridor', 'Koridor', Rect.fromLTWH(285, 284, 115, 406),
        width: 2, depth: 5, labelOffset: Offset(0, 40)),
  ];
  // IDs already stored in V5 preferences stay unchanged. New slots are optional.
  static const fixtures = <PlanFixture>[
    PlanFixture('bedroom_ceiling', 'bedroom', 'Yatak odası · Tavan',
        Offset(154.5, 558)),
    PlanFixture('bedroom_floor', 'bedroom', 'Yatak odası · Ayaklı lamba',
        Offset(64, 492),
        floor: true),
    PlanFixture(
        'living_ceiling', 'living', 'Salon · Tavan', Offset(422.5, 140)),
    PlanFixture(
        'kitchen_ceiling', 'kitchen', 'Mutfak · Tavan', Offset(117, 340)),
    PlanFixture(
        'bathroom_ceiling', 'bathroom', 'Banyo · Tavan', Offset(480, 353)),
    PlanFixture(
        'hall_ceiling', 'hall', 'Ana koridor · Tavan', Offset(342.5, 460)),
    PlanFixture(
        'wc_ceiling', 'wc', 'WC · Tavan', Offset(400 + wcWidth / 2, 535)),
    PlanFixture('small_hall_ceiling', 'small_hall', 'Küçük koridor · Tavan',
        Offset(247.5, 391)),
  ];
  static const openings = <PlanOpening>[
    PlanOpening(Offset(325, 24), Offset(520, 24), window: true),
    PlanOpening(Offset(24, 324), Offset(24, 372), window: true),
    PlanOpening(Offset(24, 520), Offset(24, 576), window: true),
    PlanOpening(Offset(302, 284), Offset(354, 284)),
    PlanOpening(Offset(400, 390), Offset(400, 434)),
    PlanOpening(Offset(400, 474), Offset(400, 518)),
    PlanOpening(Offset(210, 385), Offset(210, 427), swing: 1),
    PlanOpening(Offset(238, 452), Offset(278, 452), swing: 1),
    PlanOpening(Offset(315, 690), Offset(365, 690)),
  ];
  static const passages = <PlanOpening>[
    PlanOpening(Offset(285, 364), Offset(285, 446)),
  ];

  /// Union collinear rectangle boundaries, then subtract genuine apertures.
  /// Doors are real holes, never lines drawn on top of closed walls.
  static List<(Offset, Offset)> wallSegments() {
    final groups = <String, List<(double, double)>>{};
    final axes = <String, (bool, double)>{};
    void add(Offset a, Offset b) {
      final h = (a.dy - b.dy).abs() < .001;
      final fixed = h ? a.dy : a.dx;
      final key = '${h ? 'h' : 'v'}:$fixed';
      final low = h ? a.dx : a.dy, high = h ? b.dx : b.dy;
      (groups[key] ??= []).add(low < high ? (low, high) : (high, low));
      axes[key] = (h, fixed);
    }

    for (final room in rooms) {
      final r = room.bounds;
      add(r.topLeft, r.topRight);
      add(r.topRight, r.bottomRight);
      add(r.bottomLeft, r.bottomRight);
      add(r.topLeft, r.bottomLeft);
    }
    final result = <(Offset, Offset)>[];
    for (final entry in groups.entries) {
      final (horizontal, fixed) = axes[entry.key]!;
      final sorted = entry.value..sort((a, b) => a.$1.compareTo(b.$1));
      var merged = <(double, double)>[];
      for (final span in sorted) {
        if (merged.isEmpty || span.$1 > merged.last.$2 + .001) {
          merged.add(span);
        } else {
          final last = merged.removeLast();
          merged.add((last.$1, span.$2 > last.$2 ? span.$2 : last.$2));
        }
      }
      for (final opening in [...openings, ...passages]) {
        final sameAxis = horizontal
            ? (opening.from.dy - opening.to.dy).abs() < .001
            : (opening.from.dx - opening.to.dx).abs() < .001;
        final value = horizontal ? opening.from.dy : opening.from.dx;
        if (!sameAxis || (value - fixed).abs() > .001) continue;
        final low = horizontal ? opening.from.dx : opening.from.dy,
            high = horizontal ? opening.to.dx : opening.to.dy;
        final next = <(double, double)>[];
        for (final span in merged) {
          if (high <= span.$1 || low >= span.$2) {
            next.add(span);
          } else {
            if (low > span.$1) next.add((span.$1, low));
            if (high < span.$2) next.add((high, span.$2));
          }
        }
        merged = next;
      }
      for (final span in merged) {
        result.add(horizontal
            ? (Offset(span.$1, fixed), Offset(span.$2, fixed))
            : (Offset(fixed, span.$1), Offset(fixed, span.$2)));
      }
    }
    return result;
  }

  static PlanRoom room(String id) => rooms.firstWhere((r) => r.id == id);
  static List<PlanFixture> fixturesFor(String id) =>
      fixtures.where((f) => f.roomId == id).toList();
}

class FixtureBinding {
  const FixtureBinding(this.lightId, this.ip);
  final String lightId, ip;
  Map<String, String> toJson() => {'lightId': lightId, 'ip': ip};
}

class FixtureState {
  const FixtureState(
      {this.on,
      this.pending = false,
      this.assigned = false,
      this.controllable = false,
      this.retryable = false,
      this.feedback});
  final bool? on;
  final bool pending, assigned;
  final bool controllable, retryable;
  final String? feedback;
  String get label => !assigned
      ? 'Eşleştirilmedi'
      : feedback != null
          ? feedback!
          : pending
              ? 'Yanıt bekleniyor'
              : on == true
                  ? 'Açık'
                  : on == false
                      ? 'Kapalı'
                      : 'Güncel yanıt yok';
}
