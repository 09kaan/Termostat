import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termostat_app/providers/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'V9 radius migrates independently and arrival light selection starts empty',
      () async {
    SharedPreferences.setMockInitialValues({'homeRadiusMeters': 350.0});
    final s = SettingsProvider(ownerUid: () => 'owner');
    await s.ready;
    expect([
      s.heatEntryRadius,
      s.heatExitRadius,
      s.lightEntryRadius,
      s.lightExitRadius
    ], everyElement(350.0));
    expect(s.entryLightIds, isEmpty);
    expect(s.entryHeating, isTrue);
    s.dispose();
  });
  test('Heating and light entry/exit radii persist independently', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsProvider(ownerUid: () => 'owner');
    await s.ready;
    await s.setAutomationRadius('heatExit', 500);
    await s.setAutomationRadius('heatEntry', 250);
    await s.setAutomationRadius('lightEntry', 50);
    await s.setAutomationRadius('lightExit', 100);
    final restored = SettingsProvider(ownerUid: () => 'owner');
    await restored.ready;
    expect([
      restored.heatEntryRadius,
      restored.heatExitRadius,
      restored.lightEntryRadius,
      restored.lightExitRadius
    ], [
      250.0,
      500.0,
      50.0,
      100.0
    ]);
    s.dispose();
    restored.dispose();
  });
  test('Invalid and inverted radii are rejected without mutation', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsProvider(ownerUid: () => 'owner');
    await s.ready;
    for (final v in [0.0, 5.0, 2001.0, double.nan, double.infinity]) {
      await expectLater(
          s.setAutomationRadius('heatEntry', v), throwsArgumentError);
    }
    await expectLater(s.setAutomationRadius('heatExit', 50), throwsStateError);
    await expectLater(
        s.setAutomationRadius('unknown', 200), throwsArgumentError);
    expect(s.heatExitRadius, 200);
    s.dispose();
  });
  test('Malformed persisted radii are clamped and exit is not below entry',
      () async {
    SharedPreferences.setMockInitialValues({
      'geo_v10_heatEntry': 400.0,
      'geo_v10_heatExit': 50.0,
      'geo_v10_lightEntry': 5.0,
      'geo_v10_lightExit': 3000.0
    });
    final s = SettingsProvider(ownerUid: () => 'owner');
    await s.ready;
    expect([
      s.heatEntryRadius,
      s.heatExitRadius,
      s.lightEntryRadius,
      s.lightExitRadius
    ], [
      400.0,
      400.0,
      50.0,
      2000.0
    ]);
    s.dispose();
  });
  test('Arrival/departure lamps and IPs are isolated by owner', () async {
    SharedPreferences.setMockInitialValues({});
    String? owner = 'a';
    final s = SettingsProvider(ownerUid: () => owner);
    await s.ready;
    await s.setEntryLightSelected('a', 'lamp1', true, ip: '192.168.1.10');
    await s.setExitLightSelected('a', 'lamp2', true, ip: '192.168.1.20');
    expect(s.entryLightIds, {'lamp1'});
    expect(s.exitLightIds, {'lamp2'});
    owner = 'b';
    expect(s.entryLightIds, isEmpty);
    expect(s.exitLightIds, isEmpty);
    await s.setEntryLightSelected('a', 'lamp3', true, ip: '192.168.1.30');
    owner = 'a';
    expect(s.entryLightIds, {'lamp1'});
    expect(s.entryLightIPs['lamp1'], '192.168.1.10');
    s.dispose();
  });
  test('Entry/exit heating toggles persist independently', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsProvider(ownerUid: () => 'a');
    await s.ready;
    await s.setEntryHeating(false);
    await s.setExitHeating(true);
    final r = SettingsProvider(ownerUid: () => 'a');
    await r.ready;
    expect(r.entryHeating, isFalse);
    expect(r.exitHeating, isTrue);
    s.dispose();
    r.dispose();
  });
}
