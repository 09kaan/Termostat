import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/thermostat_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/schedule_provider.dart';
import '../models/schedule.dart';
import '../widgets/compact_dashboard.dart';
import '../widgets/compact_weather_card.dart';
import '../widgets/thermostat_summary.dart';
import '../widgets/home_pager.dart';
import './schedule_list_screen.dart';
import './wiz_lights_screen.dart';
import './thermostat_log_screen.dart';
import '../services/geofence_service.dart';
import '../services/deep_link_service.dart';
import '../services/widget_service.dart';

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
    final settings = Provider.of<SettingsProvider>(context, listen: false);
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
    settings.homeRadiusMeters,
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
    return HomePager(
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
            return CompactDashboard(
              summary: ThermostatSummary(
                temperature: data.currentTemperature,
                humidity: data.humidity,
                target: data.targetTemperature,
                onTargetChanged: thermostat.updateTemperature,
              ),
              mode: data.mode,
              onModeChanged: thermostat.updateMode,
              waking: thermostat.wakeRequestInProgress,
              onWake: () => _requestPcWake(thermostat),
              weather: const CompactWeatherCard(),
            );
          },
        ),
        const ScheduleListScreen(embedded: true),
      ],
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

  Future<void> _showAddEntryDialog(
    BuildContext context,
    Schedule schedule,
  ) async {
    final formKey = GlobalKey<FormState>();
    int selectedDay = 1;
    TimeOfDay startTime = TimeOfDay.now();
    TimeOfDay endTime = TimeOfDay.now();
    double targetTemperature = 20.0;
    String selectedMode = 'auto';

    return showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add Schedule Entry'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    value: selectedDay,
                    decoration: const InputDecoration(labelText: 'Day of Week'),
                    items: List.generate(7, (index) {
                      return DropdownMenuItem(
                        value: index + 1,
                        child: Text(_getDayName(index + 1)),
                      );
                    }),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => selectedDay = value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    title: const Text('Start Time'),
                    trailing: Text(_formatTimeOfDay(startTime)),
                    onTap: () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: startTime,
                      );
                      if (time != null) {
                        setState(() => startTime = time);
                      }
                    },
                  ),
                  ListTile(
                    title: const Text('End Time'),
                    trailing: Text(_formatTimeOfDay(endTime)),
                    onTap: () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: endTime,
                      );
                      if (time != null) {
                        setState(() => endTime = time);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: targetTemperature.toString(),
                    decoration: const InputDecoration(
                      labelText: 'Target Temperature',
                      suffixText: '°C',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a temperature';
                      }
                      final temp = double.tryParse(value);
                      if (temp == null || temp < 5 || temp > 35) {
                        return 'Temperature must be between 5°C and 35°C';
                      }
                      return null;
                    },
                    onChanged: (value) {
                      targetTemperature = double.tryParse(value) ?? 20.0;
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedMode,
                    decoration: const InputDecoration(labelText: 'Mode'),
                    items: const [
                      DropdownMenuItem(value: 'heat', child: Text('Heat')),
                      DropdownMenuItem(value: 'cool', child: Text('Cool')),
                      DropdownMenuItem(value: 'auto', child: Text('Auto')),
                      DropdownMenuItem(value: 'off', child: Text('Off')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => selectedMode = value);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  final entry = ScheduleEntry(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    scheduleId: schedule.id,
                    dayOfWeek: selectedDay,
                    startTime: startTime,
                    endTime: endTime,
                    targetTemperature: targetTemperature,
                    mode: selectedMode,
                  );

                  // Call the provider to add the entry
                  Provider.of<ScheduleProvider>(
                    context,
                    listen: false,
                  ).addEntryToSchedule(schedule.id, entry);

                  Navigator.pop(context); // Close the dialog
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  String _getDayName(int dayOfWeek) {
    switch (dayOfWeek) {
      case 1:
        return 'Monday';
      case 2:
        return 'Tuesday';
      case 3:
        return 'Wednesday';
      case 4:
        return 'Thursday';
      case 5:
        return 'Friday';
      case 6:
        return 'Saturday';
      case 7:
        return 'Sunday';
      default:
        return '';
    }
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final localizations = MaterialLocalizations.of(context);
    return localizations.formatTimeOfDay(time);
  }
}
