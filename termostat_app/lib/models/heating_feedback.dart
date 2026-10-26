import 'connectivity_recovery.dart';

enum LinkState { unknown, online, offline }

enum RelayState { unknown, pending, on, off, mismatch }

/// Device reports, never the phone's desired isHeating value.
class HeatingFeedback {
  const HeatingFeedback(
      {this.esp32 = LinkState.unknown,
      this.esp8266 = LinkState.unknown,
      this.relay = RelayState.unknown,
      this.detail = 'Cihaz raporu bekleniyor',
      this.reportedOutput,
      this.controllerLastSeenAt,
      this.relayLastSeenAt,
      this.measurementAt,
      this.evaluatedAt,
      this.phoneConnected = false,
      this.recovery});
  final LinkState esp32, esp8266;
  final RelayState relay;
  final String detail;
  final bool? reportedOutput;

  /// Device timestamps, not the time the app read Firebase.
  final int? controllerLastSeenAt, relayLastSeenAt, measurementAt, evaluatedAt;
  int? get heatingValidUntil {
    if ((relay != RelayState.on && relay != RelayState.off) ||
        controllerLastSeenAt == null ||
        relayLastSeenAt == null ||
        measurementAt == null) {
      return null;
    }
    return [
      controllerLastSeenAt! + 75000,
      relayLastSeenAt! + 75000,
      measurementAt! + 90000
    ].reduce((a, b) => a < b ? a : b);
  }

  final bool phoneConnected;
  final ConnectivityRecovery? recovery;
  LinkState get link => !phoneConnected
      ? LinkState.unknown
      : esp32 == LinkState.offline || esp8266 == LinkState.offline
          ? LinkState.offline
          : esp32 == LinkState.online && esp8266 == LinkState.online
              ? LinkState.online
              : LinkState.unknown;
  static Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : {};
  static bool _fresh(dynamic v, int now, int limit) =>
      v is num &&
      v.isFinite &&
      v >= 1704067200000 &&
      now - v >= -5000 &&
      now - v <= limit;
  static bool _id(dynamic v) => v is String && v.isNotEmpty;
  factory HeatingFeedback.fromDevice(Map<String, dynamic> data,
      {required int now,
      required bool connected,
      required bool timeReady,
      String? pendingControlId}) {
    final all = _map(data['feedback']);
    final c = _map(all['controller']), r = _map(all['relay']);
    int? timestamp(dynamic value) => value is num &&
            value.isFinite &&
            value >= 1704067200000 &&
            value <= now + 5000
        ? value.toInt()
        : null;
    int? reportTime(Map<String, dynamic> report) =>
        report['protocol'] == 1 && _id(report['sessionId'])
            ? timestamp(report['lastSeen'])
            : null;
    final controllerAt = reportTime(c), relayAt = reportTime(r);
    final measuredAt = timestamp(c['measurementAt']);
    final recovery = ConnectivityRecovery.parse(c['recovery'], controllerAt);
    if (!connected || !timeReady) {
      return HeatingFeedback(
          phoneConnected: connected,
          recovery: recovery,
          controllerLastSeenAt: controllerAt,
          relayLastSeenAt: relayAt,
          measurementAt: measuredAt,
          evaluatedAt: timeReady ? now : null,
          detail: connected
              ? 'Sunucu saati doğrulanıyor'
              : 'Uygulama bağlantısı doğrulanamıyor');
    }
    final request = _map(all['relayRequest']);
    final control = _map(data['control']);
    LinkState link(Map<String, dynamic> report) => report['protocol'] != 1 ||
            !_id(report['sessionId']) ||
            report['lastSeen'] is! num
        ? LinkState.unknown
        : _fresh(report['lastSeen'], now, 75000)
            ? LinkState.online
            : LinkState.offline;
    final cLink = link(c), rLink = link(r);
    final bool? output = rLink == LinkState.online && r['outputOn'] is bool
        ? r['outputOn'] as bool
        : null;
    HeatingFeedback result(RelayState state, String text) => HeatingFeedback(
        phoneConnected: true,
        recovery: recovery,
        esp32: cLink,
        esp8266: rLink,
        controllerLastSeenAt: controllerAt,
        relayLastSeenAt: relayAt,
        measurementAt: measuredAt,
        evaluatedAt: now,
        relay: state,
        detail: output == true && state != RelayState.on
            ? '$text · ESP8266 son raporu: röle açık'
            : text,
        reportedOutput: output);
    if (cLink != LinkState.online || rLink != LinkState.online) {
      return result(
          RelayState.unknown,
          cLink == LinkState.offline
              ? 'ESP32 yanıt vermiyor'
              : rLink == LinkState.offline
                  ? 'ESP8266 yanıt vermiyor'
                  : 'Yeni cihaz raporu bekleniyor');
    }
    if (c['sensorValid'] != true || !_fresh(c['measurementAt'], now, 90000)) {
      return result(RelayState.unknown, 'ESP32 ölçümü güncel değil');
    }
    if (c['controlReady'] != true) {
      return result(RelayState.unknown, 'ESP32 ayarları doğrulanamıyor');
    }
    final expected = pendingControlId ?? control['id'];
    if (_id(expected) && c['controlId'] != expected) {
      return result(RelayState.pending, 'ESP32 ayarı işlemesi bekleniyor');
    }
    if (!_id(c['controlId']) ||
        !_id(c['decisionId']) ||
        c['requestedOn'] is! bool ||
        c['mode'] is! String ||
        !const {'on', 'off', 'manual'}.contains(c['mode'])) {
      return result(RelayState.unknown, 'ESP32 raporu geçersiz');
    }
    // Request, controller session, configuration revision AND decision must agree.
    if (request['id'] != c['decisionId'] ||
        request['controlId'] != c['controlId'] ||
        request['controllerSession'] != c['sessionId'] ||
        request['on'] != c['requestedOn'] ||
        request['mode'] != c['mode']) {
      return result(RelayState.pending, 'ESP32 röle talebi bekleniyor');
    }
    if (r['controllerSession'] != c['sessionId'] ||
        r['controlId'] != c['controlId'] ||
        r['decisionId'] != c['decisionId']) {
      return result(RelayState.pending, 'ESP32 → ESP8266 onayı bekleniyor');
    }
    if (r['reason'] != 'applied' ||
        output == null ||
        !_fresh(r['appliedAt'], now, 366 * 24 * 3600000)) {
      return result(RelayState.unknown, 'ESP8266 uygulama onayı yok');
    }
    if (output != c['requestedOn'] || (c['mode'] != 'on' && output)) {
      return result(RelayState.mismatch, 'Röle raporu taleple uyuşmuyor');
    }
    return result(
        output ? RelayState.on : RelayState.off,
        output
            ? 'Röle açık · uçtan uca onaylandı'
            : 'Röle kapalı · uçtan uca onaylandı');
  }
}
