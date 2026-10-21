import 'package:flutter_test/flutter_test.dart';
import 'package:termostat_app/models/heating_feedback.dart';
import 'package:termostat_app/models/thermostat.dart';

const now = 1792526400000;
Map<String, dynamic> fixture({bool on = true, String mode = 'on'}) => {
      'control': <String, dynamic>{
        'id': 'cfg1',
        'mode': mode,
        'targetTemperature': 22.5
      },
      'isHeating': on,
      'feedback': <String, dynamic>{
        'controller': <String, dynamic>{
          'protocol': 1,
          'sessionId': 'c32',
          'lastSeen': now,
          'measurementAt': now - 10000,
          'sensorValid': true,
          'controlReady': true,
          'mode': mode,
          'controlId': 'cfg1',
          'decisionId': 'd1',
          'requestedOn': on
        },
        'relayRequest': <String, dynamic>{
          'id': 'd1',
          'controllerSession': 'c32',
          'controlId': 'cfg1',
          'on': on,
          'mode': mode
        },
        'relay': <String, dynamic>{
          'protocol': 1,
          'sessionId': 'r1',
          'lastSeen': now,
          'controllerSession': 'c32',
          'controlId': 'cfg1',
          'decisionId': 'd1',
          'outputOn': on,
          'reason': 'applied',
          'appliedAt': now - 2000
        }
      }
    };
HeatingFeedback read(Map<String, dynamic> data,
        {int at = now,
        bool connected = true,
        bool timeReady = true,
        String? pending}) =>
    HeatingFeedback.fromDevice(data,
        now: at,
        connected: connected,
        timeReady: timeReady,
        pendingControlId: pending);
Map<String, dynamic> part(Map<String, dynamic> f, String key) =>
    (f['feedback'] as Map)[key] as Map<String, dynamic>;
void main() {
  test('Only a correlated two-device ACK enables the fire', () {
    final v = read(fixture());
    expect(v.relay, RelayState.on);
    expect(v.link, LinkState.online);
  });
  test('Verified relay off is distinct from unknown', () {
    expect(read(fixture(on: false, mode: 'off')).relay, RelayState.off);
  });
  test('Manual with verified off is valid', () {
    expect(read(fixture(on: false, mode: 'manual')).relay, RelayState.off);
  });
  test('Manual can never verify an ON output', () {
    expect(read(fixture(mode: 'manual')).relay, RelayState.mismatch);
  });
  test('Legacy isHeating alone is not feedback', () {
    expect(read({'isHeating': true}).relay, RelayState.unknown);
  });
  test('No phone connection never shows cached success', () {
    final v = read(fixture(), connected: false);
    expect(v.link, LinkState.unknown);
    expect(v.relay, RelayState.unknown);
  });
  test('Unverified server clock never shows cached success', () {
    expect(read(fixture(), timeReady: false).relay, RelayState.unknown);
  });
  test('Controller stale while relay still online turns link red', () {
    final f = fixture();
    part(f, 'controller')['lastSeen'] = now - 75001;
    final v = read(f);
    expect(v.link, LinkState.offline);
    expect(v.esp8266, LinkState.online);
    expect(v.relay, RelayState.unknown);
  });
  test('Relay stale while ESP32 online turns link red', () {
    final f = fixture();
    part(f, 'relay')['lastSeen'] = now - 75001;
    expect(read(f).link, LinkState.offline);
  });
  test('Exactly 75 seconds is accepted, later ages out', () {
    final f = fixture();
    part(f, 'controller')['measurementAt'] = now;
    expect(read(f, at: now + 75000).relay, RelayState.on);
    expect(read(f, at: now + 75001).relay, RelayState.unknown);
  });
  test('A future or malformed heartbeat is never online', () {
    for (final bad in [now + 5001, 0, 'today', double.nan]) {
      final f = fixture();
      part(f, 'controller')['lastSeen'] = bad;
      expect(read(f).esp32, isNot(LinkState.online));
    }
  });
  test('A current heartbeat cannot bless an old sensor sample', () {
    final f = fixture();
    part(f, 'controller')['measurementAt'] = now - 90001;
    expect(read(f).relay, RelayState.unknown);
  });
  test('Invalid sensor and invalid config readiness remain unknown', () {
    for (final key in ['sensorValid', 'controlReady']) {
      final f = fixture();
      part(f, 'controller')[key] = false;
      expect(read(f).relay, RelayState.unknown);
    }
  });
  test('New application revision must be processed by ESP32', () {
    final f = fixture();
    (f['control'] as Map)['id'] = 'cfg2';
    expect(read(f).relay, RelayState.pending);
  });
  test('Local queued revision cannot reuse a previous ACK', () {
    expect(read(fixture(), pending: 'queued2').relay, RelayState.pending);
  });
  test('A different controller boot invalidates old relay ACK', () {
    final f = fixture();
    part(f, 'controller')['sessionId'] = 'new_boot';
    part(f, 'relayRequest')['controllerSession'] = 'new_boot';
    expect(read(f).relay, RelayState.pending);
  });
  test('Each request correlation component must match', () {
    for (final key in ['id', 'controlId', 'controllerSession', 'on', 'mode']) {
      final f = fixture();
      part(f, 'relayRequest')[key] = 'wrong';
      expect(read(f).relay, RelayState.pending, reason: key);
    }
  });
  test('Each acknowledgement correlation component must match', () {
    for (final key in ['decisionId', 'controlId', 'controllerSession']) {
      final f = fixture();
      part(f, 'relay')[key] = 'wrong';
      expect(read(f).relay, RelayState.pending, reason: key);
    }
  });
  test('A heartbeat without actual application reason/time is not success', () {
    for (final key in ['reason', 'appliedAt']) {
      final f = fixture();
      part(f, 'relay')[key] = null;
      expect(read(f).relay, RelayState.unknown);
    }
  });
  test('Output mismatch is visible, not called success', () {
    final f = fixture();
    part(f, 'relay')['outputOn'] = false;
    expect(read(f).relay, RelayState.mismatch);
  });
  test('An unverified ON output is explicitly described', () {
    final f = fixture();
    part(f, 'controller')['controlReady'] = false;
    expect(read(f).detail, contains('röle açık'));
  });
  test('Malformed modes and booleans do not verify', () {
    for (final value in ['on', 1, null]) {
      final f = fixture();
      part(f, 'controller')['requestedOn'] = value;
      expect(read(f).relay, RelayState.unknown);
    }
  });
  test('Thermostat model prefers canonical config over legacy mirror', () {
    final t = Thermostat.fromJson({
      'id': 'device1',
      'mode': 'on',
      'targetTemperature': 25,
      'control': {'mode': 'manual', 'targetTemperature': 22.5}
    });
    expect(t.mode, 'manual');
    expect(t.targetTemperature, 22.5);
  });
}
