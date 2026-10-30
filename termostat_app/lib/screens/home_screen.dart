import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/thermostat_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/schedule_provider.dart';
import '../models/schedule.dart';
import '../models/heating_feedback.dart';
import '../widgets/compact_dashboard.dart';
import '../widgets/compact_weather_card.dart';
import '../widgets/thermostat_summary.dart';
import '../widgets/home_pager.dart';
import '../widgets/offline_banner.dart';
import './schedule_list_screen.dart';
import './wiz_lights_screen.dart';
import './thermostat_log_screen.dart';
import '../services/geofence_service.dart';
import '../services/deep_link_service.dart';
import '../services/widget_service.dart';
import '../utils/haptics_helper.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _roomKey = GlobalKey<WizLightsScreenState>();
  String? _lastGeofenceConfiguration;
  final ThermostatGeofenceService _geofenceService =
      ThermostatGeofenceService();
  final DeepLinkService _deepLinkService = DeepLinkService();

  @override
  void initState() {
    super.initState();
    _initializeData();
    _startGeofence();

    // Listen to settings changes to update geofence
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final settings = Provider.of<SettingsProvider>(context, listen: false);
      _lastGeofenceConfiguration = _geofenceConfiguration(settings);
      settings.addListener(_onSettingsChanged);
    });
  }

  Future<void> _initializeData() async {
    final thermostat = Provider.of<ThermostatProvider>(context, listen: false);
    final schedule = Provider.of<ScheduleProvider>(context, listen: false);
    await thermostat.initializeThermostat('device1');
    await thermostat.startListening();
    await WidgetService.initialize();
    await schedule.loadSchedules();
    if (!mounted) return;
    schedule.startScheduleChecker(thermostat);
  }

  void _startGeofence() async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    await _geofenceService.initialize(context);
    if (settings.geofenceEnabled) {
      await _geofenceService.start(context);
    }
    await _deepLinkService.initialize(context);
  }

  String _geofenceConfiguration(SettingsProvider settings) => jsonEncode([
        settings.geofenceEnabled,
        settings.homeLatitude,
        settings.homeLongitude,
        settings.heatEntryRadius,
        settings.heatExitRadius,
        settings.lightEntryRadius,
        settings.lightExitRadius,
        settings.entryHeating,
        settings.entryLightIPs,
        settings.exitHeating,
        settings.exitLightIPs,
      ]);

  void _onSettingsChanged() {
    if (!mounted) return;
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final configuration = _geofenceConfiguration(settings);
    if (configuration == _lastGeofenceConfiguration) return;
    _lastGeofenceConfiguration = configuration;
    if (settings.geofenceEnabled && !_geofenceService.isRunning) {
      _geofenceService.start(context);
    } else if (!settings.geofenceEnabled && _geofenceService.isRunning) {
      _geofenceService.stop();
    } else {
      _geofenceService.updateGeofence(context);
    }
  }

  LinearGradient _buildStatusGradient(
    BuildContext context, {
    required bool enabled,
    required RelayState relayState,
    required String mode,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = Theme.of(context).scaffoldBackgroundColor;

    if (!enabled) {
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [baseColor, baseColor],
      );
    }

    if (mode == 'on' && relayState == RelayState.on) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [const Color(0xFF2C1608), const Color(0xFF1A0F0A), baseColor]
            : [const Color(0xFFFFF3E0), const Color(0xFFFFE0B2), baseColor],
      );
    }

    if (mode == 'on' && relayState != RelayState.on) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [const Color(0xFF0A1E29), const Color(0xFF0D151A), baseColor]
            : [const Color(0xFFE1F5FE), const Color(0xFFF0F9FF), baseColor],
      );
    }

    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [baseColor, baseColor],
    );
  }

  @override
  void dispose() {
    Provider.of<ThermostatProvider>(context, listen: false).stopListening();
    Provider.of<ScheduleProvider>(context, listen: false).stopScheduleChecker();
    Provider.of<SettingsProvider>(
      context,
      listen: false,
    ).removeListener(_onSettingsChanged);
    _geofenceService.stop();
    _deepLinkService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: HomePager(
              onRooms: () => _roomKey.currentState?.openRooms(),
              onRoomSettings: () => _roomKey.currentState?.openSettings(),
              onAppSettings: () => Navigator.pushNamed(context, '/settings'),
              pages: [
                const ThermostatLogScreen(),
                WizLightsScreen(key: _roomKey, embedded: true),
                Consumer2<ThermostatProvider, SettingsProvider>(
                  builder: (context, thermostat, settings, _) {
                    if (thermostat.isLoading || settings.isLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (thermostat.error != null || settings.error != null) {
                      return Center(
                        child: Text('Hata: ${thermostat.error ?? settings.error}'),
                      );
                    }
                    final data = thermostat.thermostat;
                    if (data == null) {
                      return const Center(child: Text('Bağlı termostat yok'));
                    }
                    final feedback = thermostat.heatingFeedback;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeInOutCubic,
                      decoration: BoxDecoration(
                        gradient: _buildStatusGradient(
                          context,
                          enabled: settings.enableDynamicBackground,
                          relayState: feedback.relay,
                          mode: data.mode,
                        ),
                      ),
                      child: CompactDashboard(
                        summary: ThermostatSummary(
                          temperature: data.currentTemperature,
                          humidity: data.humidity,
                          target: data.targetTemperature,
                          onTargetChanged: (newTarget) {
                            HapticsHelper.temperatureStep(
                              enabled: settings.enableHaptics,
                            );
                            thermostat.updateTemperature(newTarget);
                          },
                        ),
                        mode: data.mode,
                        feedback: feedback,
                        onModeChanged: (newMode) {
                          HapticsHelper.modeToggle(
                            enabled: settings.enableHaptics,
                          );
                          thermostat.updateMode(newMode);
                        },
                        waking: thermostat.wakeRequestInProgress,
                        onWake: () {
                          HapticsHelper.heavyAction(
                            enabled: settings.enableHaptics,
                          );
                          _requestPcWake(thermostat);
                        },
                        weather: const CompactWeatherCard(),
                      ),
                    );
                  },
                ),
                const ScheduleListScreen(embedded: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _requestPcWake(ThermostatProvider thermostat) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Bilgisayar açılsın mı?'),
        content: const Text(
          'ESP32, bilgisayara Wake-on-LAN sinyali gönderecek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.power_settings_new),
            label: const Text('Aç'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final sent = await thermostat.wakePc();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          sent
              ? 'PC açma komutu gönderildi. ESP32 en geç 30 saniye içinde işleyecek.'
              : (thermostat.wakeError ?? 'Komut gönderilemedi.'),
        ),
        backgroundColor: sent ? null : Theme.of(context).colorScheme.error,
      ),
    );
  }
}
