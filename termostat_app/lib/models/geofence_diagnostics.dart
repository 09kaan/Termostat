/// Read-only iOS diagnostics. Reading this never requests a new GPS fix.
class GeofenceDiagnostics {
  const GeofenceDiagnostics({
    this.enabled = false,
    this.servicesEnabled = false,
    this.authorization = 'unknown',
    this.regionCount = 0,
    this.registeredRegions = const <String>{},
    this.inside,
    this.distance,
    this.accuracy,
    this.sampledAt,
    this.lastEventAt,
    this.lastEvent,
    this.lastResultAt,
  });
  final bool enabled, servicesEnabled;
  final String authorization;
  final int regionCount;
  final Set<String> registeredRegions;
  final bool? inside;
  final double? distance, accuracy;
  final DateTime? sampledAt, lastEventAt, lastResultAt;
  final String? lastEvent;
  static const expectedRegions = {
    'heatEntry',
    'heatExit',
    'lightEntry',
    'lightExit'
  };
  bool get monitoring =>
      enabled &&
      servicesEnabled &&
      authorization == 'always' &&
      registeredRegions.containsAll(expectedRegions);
  String get status {
    if (!servicesEnabled) return 'Telefonun konum servisi kapalı';
    if (authorization == 'denied' || authorization == 'restricted')
      return 'Konum izni kapalı';
    if (authorization != 'always')
      return 'Arka plan için “Her zaman” konum izni gerekli';
    if (!enabled) return 'Bölge izlemesi kapalı';
    if (!registeredRegions.containsAll(expectedRegions))
      return 'iOS bölge kaydı bekleniyor (${registeredRegions.length}/4)';
    return 'iOS bölge izlemesi açık';
  }

  static int? _millis(dynamic value) =>
      value is num && value.isFinite ? value.toInt() : null;
  static DateTime? _date(dynamic value) {
    final millis = _millis(value);
    return millis == null || millis <= 0
        ? null
        : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  factory GeofenceDiagnostics.fromMap(
    Map<dynamic, dynamic> map, {
    required int now,
  }) {
    final stamp = _millis(map['sampledAt']);
    final rawDistance = map['distance'];
    final rawAccuracy = map['accuracy'];
    final rawRegions = map['registeredRegions'];
    final regions = rawRegions is Iterable
        ? rawRegions.whereType<String>().toSet()
        : <String>{};
    final fresh = stamp != null &&
        now - stamp >= -5000 &&
        now - stamp <= 300000 &&
        rawAccuracy is num &&
        rawAccuracy.isFinite &&
        rawAccuracy >= 0;
    return GeofenceDiagnostics(
      enabled: map['enabled'] == true,
      servicesEnabled: map['servicesEnabled'] == true,
      authorization: map['authorization'] is String
          ? map['authorization'] as String
          : 'unknown',
      regionCount: _millis(map['regionCount']) ?? 0,
      registeredRegions: regions,
      inside: map['inside'] is bool ? map['inside'] as bool : null,
      distance: fresh &&
              rawDistance is num &&
              rawDistance.isFinite &&
              rawDistance >= 0
          ? rawDistance.toDouble()
          : null,
      accuracy: fresh ? rawAccuracy.toDouble() : null,
      sampledAt: _date(map['sampledAt']),
      lastEventAt: _date(map['lastEventAt']),
      lastEvent: map['lastEvent'] is String ? map['lastEvent'] as String : null,
      lastResultAt: _date(map['lastResultAt']),
    );
  }
}
