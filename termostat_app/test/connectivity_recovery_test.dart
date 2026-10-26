import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termostat_app/models/connectivity_recovery.dart';
import 'package:termostat_app/widgets/heating_status.dart';
import 'heating_feedback_test.dart' as base;

Map<String, dynamic> plan({int used = 0}) => {
      'protocol': 1,
      'phase': used == 8
          ? 'stopped'
          : used < 3
              ? 'fast'
              : 'slow',
      'fastUsed': used < 3 ? used : 3,
      'slowUsed': used > 3 ? used - 3 : 0,
      'fastLimit': 3,
      'slowLimit': 5,
      'waitMs': used == 8
          ? 0
          : used < 3
              ? 300000
              : 1800000,
      'remainingMs': used == 8
          ? 0
          : used < 3
              ? 300000
              : 1800000,
    };
Map<String, dynamic> data({int used = 0}) {
  final d = base.fixture();
  base.part(d, 'controller')['recovery'] = plan(used: used);
  return d;
}

void main() {
  for (var used = 0; used <= 8; used++) {
    test('Validate each real reported stage $used', () {
      final r = ConnectivityRecovery.parse(plan(used: used), base.now)!;
      expect(r.fastUsed + r.slowUsed, used);
      final text = r.describe(phoneConnected: true, now: base.now + 80000);
      expect(text, contains(used == 8 ? 'durduruldu' : 'sonra reset'));
    });
  }
  test('Countdown expires without fabricating a reset or new attempt', () {
    final r = ConnectivityRecovery.parse(plan(), base.now)!;
    expect(r.describe(phoneConnected: true, now: base.now + 80000),
        contains('3 dk 40 sn'));
    expect(r.describe(phoneConnected: true, now: base.now + 300000),
        contains('gerçekleştiği doğrulanamadı'));
    expect(r.describe(phoneConnected: true, now: base.now + 99999999),
        contains('Hızlı deneme 1/3'));
    expect(r.fastUsed, 0);
  });
  test('Offline phone and unknown clock cannot assert a countdown', () {
    final r = ConnectivityRecovery.parse(plan(), base.now)!;
    expect(r.describe(phoneConnected: false, now: base.now),
        contains('Uygulama bağlantısı yok'));
    expect(
        r.describe(phoneConnected: true, now: null), contains('Sunucu saati'));
    expect(r.describe(phoneConnected: true, now: base.now - 5001),
        contains('Sunucu saati'));
  });
  test('Reject unsupported protocols, bounds and inconsistent stages', () {
    for (final entry in <String, dynamic>{
      'protocol': 2,
      'fastUsed': -1,
      'slowUsed': 6,
      'remainingMs': 300001,
      'waitMs': 0,
      'fastLimit': 4,
      'slowLimit': 6,
      'phase': 'slow'
    }.entries) {
      final raw = plan()..[entry.key] = entry.value;
      expect(ConnectivityRecovery.parse(raw, base.now), isNull,
          reason: entry.key);
    }
    for (final bad in [double.nan, double.infinity, 1.5, '2', true, null]) {
      expect(ConnectivityRecovery.parse(plan()..['fastUsed'] = bad, base.now),
          isNull);
    }
    expect(ConnectivityRecovery.parse(plan(), null), isNull);
    expect(ConnectivityRecovery.parse({}, base.now), isNull);
  });
  test('Only genuine controller report anchors the recovery estimate', () {
    final d = data();
    expect(base.read(d, at: base.now + 80000).recovery!.reportedAt, base.now);
    base.part(d, 'controller')['sessionId'] = '';
    expect(base.read(d).recovery, isNull);
  });
  testWidgets(
      'Offline details update from 5-second feedback without simulating resets',
      (t) async {
    var at = base.now + 80000;
    late StateSetter update;
    await t
        .pumpWidget(MaterialApp(home: StatefulBuilder(builder: (context, set) {
      update = set;
      return Scaffold(body: HeatingStatus(feedback: base.read(data(), at: at)));
    })));
    await t.tap(find.byKey(const ValueKey('heating-status')));
    await t.pumpAndSettle();
    expect(find.textContaining('3 dk 40 sn'), findsOneWidget);
    update(() => at += 5000);
    await t.pumpAndSettle();
    expect(find.textContaining('3 dk 35 sn'), findsOneWidget);
    update(() => at = base.now + 300000);
    await t.pumpAndSettle();
    expect(find.textContaining('gerçekleştiği doğrulanamadı'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'Old firmware does not invent a plan; narrow large text stays usable',
      (t) async {
    t.view.resetPhysicalSize();
    t.view.physicalSize = const Size(320, 700);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.7)),
            child: child!),
        home: Scaffold(
            body: HeatingStatus(
                feedback: base.read(base.fixture(), at: base.now + 80000)))));
    await t.tap(find.byKey(const ValueKey('heating-status')));
    await t.pumpAndSettle();
    expect(find.textContaining('Reset planı bilgisi yok'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
