import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/thermostat_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/schedule_provider.dart';
import '../models/schedule.dart';
import '../widgets/temperature_display.dart';
import '../widgets/mode_selector.dart';
import '../widgets/schedule_card.dart';
import '../widgets/weather_card.dart';
import '../widgets/default_page_controller.dart';
import './schedule_list_screen.dart';
import './thermostat_log_screen.dart';
import '../services/geofence_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PageController _pageController = PageController(initialPage: 1);
  final ThermostatGeofenceService _geofenceService =
      ThermostatGeofenceService();

  @override
  void initState() {
    super.initState();
    _initializeData();
    _startGeofence();

    // Listen to settings changes to update geofence
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = Provider.of<SettingsProvider>(context, listen: false);
      settings.addListener(_onSettingsChanged);
    });
  }

  Future<void> _initializeData() async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final thermostat = Provider.of<ThermostatProvider>(context, listen: false);
    final schedule = Provider.of<ScheduleProvider>(context, listen: false);
    await thermostat.initializeThermostat('device1');
    await thermostat.startListening();
    await schedule.loadSchedules();
    if (!mounted) return;
    schedule.startScheduleChecker(thermostat);
  }

  void _startGeofence() async {
    await _geofenceService.initialize(context);
    await _geofenceService.start(context);
  }

  void _onSettingsChanged() {
    // Update geofence when settings change
    if (mounted) {
      _geofenceService.updateGeofence(context);
    }
  }

  @override
  void dispose() {
    Provider.of<ThermostatProvider>(context, listen: false).stopListening();
    Provider.of<ScheduleProvider>(context, listen: false).stopScheduleChecker();
    Provider.of<SettingsProvider>(context, listen: false)
        .removeListener(_onSettingsChanged);
    _geofenceService.stop();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Thermostat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              // Navigate to the SettingsScreen
              Navigator.pushNamed(context, '/settings');
            },
          ),
        ],
      ),
      body: PageView(
        controller: _pageController,
        children: [
          const ThermostatLogScreen(),
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 0.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Consumer2<ThermostatProvider, SettingsProvider>(
                    builder: (context, thermostat, settings, _) {
                      if (thermostat.isLoading || settings.isLoading) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (thermostat.error != null) {
                        return Center(
                            child: Text('Error: ${thermostat.error}'));
                      }

                      if (settings.error != null) {
                        return Center(child: Text('Error: ${settings.error}'));
                      }

                      if (thermostat.thermostat == null) {
                        return const Center(
                            child: Text('No thermostat connected'));
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Card(
                            elevation: 4,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12.0, vertical: 12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Center(
                                    child: IntrinsicHeight(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Temperature',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                              ),
                                              const SizedBox(height: 2),
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.center,
                                                children: [
                                                  Icon(Icons.thermostat,
                                                      size: 28,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .primary),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    '${thermostat.thermostat!.currentTemperature.toStringAsFixed(1)}°C',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .headlineMedium
                                                        ?.copyWith(
                                                          color:
                                                              Theme.of(context)
                                                                  .colorScheme
                                                                  .primary,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          fontSize: 32,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                          const SizedBox(width: 40),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Humidity',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                              ),
                                              const SizedBox(height: 2),
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.center,
                                                children: [
                                                  Icon(Icons.water_drop,
                                                      size: 28,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .primary),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    '${thermostat.thermostat!.humidity.toStringAsFixed(1)}%',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .headlineMedium
                                                        ?.copyWith(
                                                          color:
                                                              Theme.of(context)
                                                                  .colorScheme
                                                                  .primary,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          fontSize: 32,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                              Builder(
                                                builder: (context) {
                                                  final humidity = thermostat
                                                      .thermostat!.humidity;
                                                  if (humidity < 40) {
                                                    return const Text('Low',
                                                        style: TextStyle(
                                                            color:
                                                                Colors.orange,
                                                            fontSize: 12));
                                                  } else if (humidity > 60) {
                                                    return const Text('High',
                                                        style: TextStyle(
                                                            color: Colors.blue,
                                                            fontSize: 12));
                                                  } else {
                                                    return const Text('Normal',
                                                        style: TextStyle(
                                                            color: Colors.green,
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold));
                                                  }
                                                },
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Target Temperature',
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                            Icons.remove_circle_outline),
                                        onPressed: () {
                                          if (thermostat.thermostat!
                                                  .targetTemperature >
                                              10.0) {
                                            thermostat.updateTemperature(
                                                thermostat.thermostat!
                                                        .targetTemperature -
                                                    0.5);
                                          }
                                        },
                                      ),
                                      Text(
                                        '${thermostat.thermostat!.targetTemperature.toStringAsFixed(1)}°C',
                                        style: Theme.of(context)
                                            .textTheme
                                            .displayMedium
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .secondary,
                                            ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                            Icons.add_circle_outline),
                                        onPressed: () {
                                          if (thermostat.thermostat!
                                                  .targetTemperature <
                                              30.0) {
                                            thermostat.updateTemperature(
                                                thermostat.thermostat!
                                                        .targetTemperature +
                                                    0.5);
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Slider(
                                    value: thermostat
                                        .thermostat!.targetTemperature,
                                    min: 10.0,
                                    max: 30.0,
                                    divisions: 40,
                                    label: thermostat
                                        .thermostat!.targetTemperature
                                        .round()
                                        .toString(),
                                    onChanged: thermostat.updateTemperature,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ModeSelector(
                            mode: thermostat.thermostat!.mode,
                            onModeChanged: thermostat.updateMode,
                          ),
                          const SizedBox(height: 8),
                          const WeatherCard(),
                          const SizedBox(height: 8),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const ScheduleListScreen(),
        ],
      ),
    );
  }

  Future<void> _showAddEntryDialog(
      BuildContext context, Schedule schedule) async {
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
                    decoration: const InputDecoration(
                      labelText: 'Day of Week',
                    ),
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
                    decoration: const InputDecoration(
                      labelText: 'Mode',
                    ),
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
                  Provider.of<ScheduleProvider>(context, listen: false)
                      .addEntryToSchedule(schedule.id, entry);

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
