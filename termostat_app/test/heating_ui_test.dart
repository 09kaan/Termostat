// Test-only simulated devices: never contacts Firebase or sends a device command.
// ignore_for_file: depend_on_referenced_packages, implementation_imports
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_database_platform_interface/firebase_database_platform_interface.dart';
import 'package:firebase_database_platform_interface/src/method_channel/method_channel_database_reference.dart';
import 'package:firebase_database_platform_interface/src/method_channel/method_channel_database_event.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termostat_app/theme/app_theme.dart';
import 'package:termostat_app/models/heating_feedback.dart';
import 'package:termostat_app/providers/settings_provider.dart';
import 'package:termostat_app/widgets/compact_dashboard.dart';
import 'package:termostat_app/widgets/compact_weather_card.dart';
import 'package:termostat_app/widgets/thermostat_summary.dart';
import 'package:termostat_app/widgets/geofence_exit_options.dart';

class FakeMulti extends MultiFactorPlatform {
  FakeMulti(super.auth);
}

class FakeAuth extends FirebaseAuthPlatform {
  late final UserPlatform user = FakeUser(this, FakeMulti(this));
  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) => this;
  @override
  FirebaseAuthPlatform setInitialValues(
          {PigeonUserDetails? currentUser, String? languageCode}) =>
      this;
  @override
  UserPlatform? get currentUser => user;
  @override
  Stream<UserPlatform?> authStateChanges() => Stream.value(user);
}

class FakeUser extends UserPlatform {
  FakeUser(FirebaseAuthPlatform auth, MultiFactorPlatform multiFactor)
      : super(
            auth,
            multiFactor,
            PigeonUserDetails(
                userInfo: PigeonUserInfo(
                    uid: 'test_owner',
                    isAnonymous: false,
                    isEmailVerified: true),
                providerData: []));
}

class FakeDatabase extends DatabasePlatform {
  @override
  DatabasePlatform delegateFor(
          {required FirebaseApp app, String? databaseURL}) =>
      this;
  @override
  DatabaseReferencePlatform ref([String? path]) =>
      FakeRef(this, (path ?? '').split('/'));
}

class FakeRef extends MethodChannelDatabaseReference {
  FakeRef(DatabasePlatform database, List<String> path)
      : super(database: database, pathComponents: path);
  @override
  Stream<DatabaseEventPlatform> observe(
          QueryModifiers modifiers, DatabaseEventType type) =>
      Stream.value(MethodChannelDatabaseEvent(this, {
        'eventType': 'value',
        'snapshot': {
          'key': 'lights',
          'value': {
            'lamp1': {'name': 'Salon', 'ip': '192.168.1.20'},
            'lamp2': {'name': 'Antre', 'ip': '192.168.1.21'}
          },
          'priority': null,
          'childKeys': ['lamp1', 'lamp2']
        }
      }));
}

const _captureKey = ValueKey('screen-capture');
Widget shell(Widget body,
        {String appearance = 'warm_minimal',
        Brightness brightness = Brightness.light,
        double scale = 1}) =>
    RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
            theme: AppTheme.forAppearance(appearance, brightness),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: Scaffold(
                appBar: AppBar(title: const Text('Termostat · Test')),
                body: SafeArea(child: body))));
Widget dashboard(HeatingFeedback feedback) => CompactDashboard(
    summary: ThermostatSummary(
        temperature: 22.3, humidity: 48, target: 23.5, onTargetChanged: (_) {}),
    mode: 'on',
    onModeChanged: (_) {},
    feedback: feedback,
    waking: false,
    onWake: () {},
    weather: CompactWeatherSummary(
        city: 'Ankara',
        temperature: 18,
        humidity: 54,
        condition: 'Açık',
        loading: false,
        onRefresh: () {}));
Future<void> size(WidgetTester t, double width, double height) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

Future<void> golden(WidgetTester t, String name) async {
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
  await expectLater(
      find.byKey(_captureKey), matchesGoldenFile('goldens/$name.png'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    FirebaseAuthPlatform.instance = FakeAuth();
    DatabasePlatform.instance = FakeDatabase();
    final root = Directory(Platform.environment['FLUTTER_ROOT'] ??
        File(Platform.resolvedExecutable)
            .parent
            .parent
            .parent
            .parent
            .parent
            .parent
            .path);
    final font = File(
        '${root.path}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf');
    if (await font.exists()) {
      final loader = FontLoader('Roboto');
      loader.addFont(
          Future.value(ByteData.sublistView(await font.readAsBytes())));
      await loader.load();
    }
  });
  for (final brightness in Brightness.values) {
    for (final state in [
      RelayState.on,
      RelayState.off,
      RelayState.pending,
      RelayState.unknown
    ]) {
      testWidgets('Dashboard ${brightness.name} ${state.name} at 390',
          (t) async {
        await size(t, 390, 844);
        final f = HeatingFeedback(
            esp32: state == RelayState.unknown
                ? LinkState.offline
                : LinkState.online,
            esp8266: LinkState.online,
            relay: state,
            phoneConnected: true,
            detail: 'Simülasyon · uçtan uca durum testi');
        await t.pumpWidget(shell(dashboard(f), brightness: brightness));
        await golden(t, 'dashboard_${brightness.name}_${state.name}_390');
        if (state == RelayState.on) {
          await t.tap(find.byKey(const ValueKey('heating-status')));
          await t.pumpAndSettle();
          expect(find.textContaining('mekanik kontak'), findsOneWidget);
          await golden(t, 'detail_${brightness.name}_390');
        }
      });
    }
  }
  for (final width in [375.0, 428.0]) {
    testWidgets('Original theme fits width $width', (t) async {
      await size(t, width, width == 375 ? 812 : 926);
      await t.pumpWidget(
          shell(dashboard(const HeatingFeedback()), appearance: 'original'));
      await golden(t, 'dashboard_original_${width.round()}');
    });
  }
  testWidgets('Large text remains scrollable and reachable', (t) async {
    await size(t, 375, 812);
    await t.pumpWidget(shell(dashboard(const HeatingFeedback()), scale: 1.6));
    await golden(t, 'dashboard_large_text_375');
    expect(find.byKey(const ValueKey('dashboard-accessible-scroll')),
        findsOneWidget);
    await t.ensureVisible(find.byKey(const ValueKey('compact-weather-card')));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
  for (final brightness in Brightness.values) {
    testWidgets('Four geofence radii and independent lamps ${brightness.name}',
        (t) async {
      SharedPreferences.setMockInitialValues({
        'geo_v10_heatExit': 400.0,
        'geo_v10_heatEntry': 200.0,
        'geo_v10_lightEntry': 50.0,
        'geo_v10_lightExit': 100.0,
        'geo_v10_entry_lights_test_owner': '{"lamp2":"192.168.1.21"}',
        'geofence_exit_lights_test_owner': '{"lamp1":"192.168.1.20"}'
      });
      final s = SettingsProvider(ownerUid: () => 'test_owner');
      await s.ready;
      addTearDown(s.dispose);
      await size(t, 390, 844);
      await t.pumpWidget(shell(
          ChangeNotifierProvider.value(
              value: s,
              child: const SingleChildScrollView(child: GeofenceExitOptions())),
          brightness: brightness));
      await golden(t, 'geofence_heating_${brightness.name}_390');
      await t.ensureVisible(find.text('Işıklar'));
      await t.tap(find.text('Işıklar'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Salon'));
      await t.tap(find.text('Salon'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Çıkışta kapat').first);
      await golden(t, 'geofence_lights_${brightness.name}_390');
      await t.ensureVisible(find.text('Işık giriş mesafesi'));
      await t.tap(find.text('Işık giriş mesafesi'));
      await t.pumpAndSettle();
      expect(find.text('50 m'), findsWidgets);
      await golden(t, 'geofence_radius_${brightness.name}_390');
    });
  }
}
