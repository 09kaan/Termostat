import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/schedule_provider.dart';
import '../widgets/schedule_card.dart';
import '../models/schedule.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

class ScheduleListScreen extends StatefulWidget {
  const ScheduleListScreen({super.key});

  @override
  State<ScheduleListScreen> createState() => _ScheduleListScreenState();
}

class _ScheduleListScreenState extends State<ScheduleListScreen> {
  // State variables for the calendar
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay; // Initialize selectedDay
  }

  // Method to handle editing a schedule entry
  Future<void> _editScheduleEntry(
      String scheduleId, ScheduleEntry entry) async {
    final formKey = GlobalKey<FormState>();
    int selectedDay = entry.dayOfWeek;
    TimeOfDay startTime = entry.startTime;
    TimeOfDay endTime = entry.endTime;
    double targetTemperature = entry.targetTemperature;
    String selectedMode =
        entry.mode ?? 'heat'; // Initialize with entry.mode, default to 'heat'

    return showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit Schedule Entry'),
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
                  // Only show temperature input if the mode is heating_on
                  if (selectedMode == 'heating_on')
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
                      DropdownMenuItem(
                          value: 'heating_on', child: Text('Heating on')),
                      DropdownMenuItem(
                          value: 'heating_off', child: Text('Heating off')),
                      DropdownMenuItem(
                          value: 'manual', child: Text('Manual control')),
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
                  // Add validation to check if start and end times are the same
                  if (startTime.hour == endTime.hour &&
                      startTime.minute == endTime.minute) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content:
                            Text('Start time and end time cannot be the same.'),
                      ),
                    );
                    return; // Prevent saving if times are the same
                  }

                  final updatedEntry = entry.copyWith(
                    dayOfWeek: selectedDay,
                    startTime: startTime,
                    endTime: endTime,
                    targetTemperature: targetTemperature,
                    mode: selectedMode,
                    scheduleId: scheduleId, // Ensure scheduleId is kept
                  );

                  Provider.of<ScheduleProvider>(context, listen: false)
                      .updateEntryInSchedule(scheduleId, updatedEntry);

                  Navigator.pop(context);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  // Method to show delete confirmation dialog
  Future<void> _showDeleteConfirmation(BuildContext context, String scheduleId,
      ScheduleEntry entry, DateTime selectedDay) async {
    // Determine the confirmation message based on repeat type
    String confirmationMessage;
    if (entry.repeat == 'once') {
      confirmationMessage =
          'Are you sure you want to delete this one-time entry for ${_getDayName(entry.dayOfWeek)} '
          'from ${_formatTimeOfDay(entry.startTime)} to ${_formatTimeOfDay(entry.endTime)}?';
    } else {
      // For 'weekly' and 'daily', deletion for all days removes the recurring entry entirely
      confirmationMessage =
          'Are you sure you want to delete this recurring entry '
          '(${entry.repeat}) for ${_getDayName(entry.dayOfWeek)}s '
          'from ${_formatTimeOfDay(entry.startTime)} to ${_formatTimeOfDay(entry.endTime)}? '
          'This will remove it for all repeating days.';
    }

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Entry'),
        content: Text(confirmationMessage), // Use the dynamic message
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          // Option to delete for this day only (for recurring entries) or the single entry (for once)
          if (entry.repeat !=
              'once') // Only show 'Delete for this day' for recurring entries
            TextButton(
              onPressed: () {
                if (!mounted) return; // Check if the widget is still mounted
                // Add selected day to excluded dates and update the entry
                final dateToExclude =
                    '${selectedDay.year}-${selectedDay.month.toString().padLeft(2, '0')}-${selectedDay.day.toString().padLeft(2, '0')}';
                final updatedExcludedDates =
                    List<String>.from(entry.excludedDates)..add(dateToExclude);
                final updatedEntry =
                    entry.copyWith(excludedDates: updatedExcludedDates);
                Provider.of<ScheduleProvider>(context, listen: false)
                    .updateEntryInSchedule(scheduleId, updatedEntry);
                Navigator.pop(context); // Close the dialog
              },
              child: const Text('Delete for this day'),
            ),
          // Option to delete for all days (or the single entry for once)
          ElevatedButton(
            onPressed: () {
              if (!mounted) return; // Check if the widget is still mounted
              // Call the provider to remove the entry completely
              Provider.of<ScheduleProvider>(context, listen: false)
                  .removeEntryFromSchedule(scheduleId, entry.id);
              Navigator.pop(context); // Close the dialog
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child:
                const Text('Delete All'), // Button to delete the entire entry
          ),
        ],
      ),
    );
  }

  // Method to get a list of schedule entries for a given day
  List<ScheduleEntry> _getEntriesForDay(DateTime day) {
    final scheduleProvider =
        Provider.of<ScheduleProvider>(context, listen: false);
    final entries = <ScheduleEntry>[];
    final normalizedDay = DateTime(day.year, day.month, day.day);
    final formattedDay =
        '${normalizedDay.year}-${normalizedDay.month.toString().padLeft(2, '0')}-${normalizedDay.day.toString().padLeft(2, '0')}'; // Format for exclusion check

    for (var schedule in scheduleProvider.schedules) {
      for (var entry in schedule.entries) {
        // Include entries that match the day of the week, repeat daily, or match the specific date for 'once' entries
        final isRecurringEntryForDay = (entry.repeat == 'daily' ||
                (entry.repeat == 'weekly' &&
                    entry.dayOfWeek == normalizedDay.weekday)) &&
            !entry.excludedDates.contains(formattedDay);
        final isOnceEntryForDay =
            entry.repeat == 'once' && entry.specificDate == formattedDay;
        if (isRecurringEntryForDay || isOnceEntryForDay) {
          entries.add(entry);
        }
      }
    }
    // Sort entries by start time
    entries.sort((a, b) => _timeOfDayToDateTime(a.startTime)
        .compareTo(_timeOfDayToDateTime(b.startTime)));
    return entries;
  }

  // Helper to convert TimeOfDay to DateTime for sorting
  DateTime _timeOfDayToDateTime(TimeOfDay time) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, time.hour, time.minute);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedules'),
      ),
      body: Consumer<ScheduleProvider>(
        builder: (context, scheduleProvider, _) {
          if (scheduleProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (scheduleProvider.error != null) {
            return Center(child: Text('Error: ${scheduleProvider.error}'));
          }

          if (scheduleProvider.schedules.isEmpty) {
            return const Center(
              child: Text(
                  'No schedules available. Tap the + button to create one.'),
            );
          }

          // Get entries for the selected day
          final entriesForSelectedDay = _getEntriesForDay(_selectedDay!);

          return Column(
            children: [
              // TableCalendar Widget
              TableCalendar(
                firstDay: DateTime.utc(2020, 1, 1),
                lastDay: DateTime.utc(2030, 12, 31),
                focusedDay: _focusedDay,
                calendarFormat: _calendarFormat,
                selectedDayPredicate: (day) {
                  return isSameDay(_selectedDay, day);
                },
                onDaySelected: (selectedDay, focusedDay) {
                  if (!isSameDay(_selectedDay, selectedDay)) {
                    setState(() {
                      _selectedDay = selectedDay;
                      _focusedDay = focusedDay;
                    });
                  }
                },
                onFormatChanged: (format) {
                  // Manually determine the next format based on the current format
                  final nextFormat = _calendarFormat == CalendarFormat.month
                      ? CalendarFormat.twoWeeks
                      : _calendarFormat == CalendarFormat.twoWeeks
                          ? CalendarFormat.week
                          : CalendarFormat.month;

                  // Update the state with the determined next format
                  if (_calendarFormat != nextFormat) {
                    setState(() {
                      _calendarFormat = nextFormat;
                    });
                  }
                },
                onPageChanged: (focusedDay) {
                  _focusedDay = focusedDay;
                },
                // Implement eventLoader to show events on days with schedules
                eventLoader: (day) {
                  // Determine if the given day has any relevant schedule entries
                  final formattedDay =
                      '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}'; // Format for comparison

                  bool hasRelevantEntry =
                      scheduleProvider.schedules.any((schedule) {
                    return schedule.entries.any((entry) {
                      final isRecurringEntryForDay = (entry.repeat == 'daily' ||
                              (entry.repeat == 'weekly' &&
                                  entry.dayOfWeek == day.weekday)) &&
                          !entry.excludedDates.contains(formattedDay);
                      final isOnceEntryForDay = entry.repeat == 'once' &&
                          entry.specificDate == formattedDay;

                      return isRecurringEntryForDay || isOnceEntryForDay;
                    });
                  });

                  // Return a dummy event list if there are relevant entries to show a dot
                  return hasRelevantEntry ? ['event'] : [];
                },
                headerStyle: const HeaderStyle(formatButtonShowsNext: false),
              ),
              const SizedBox(height: 8.0),
              // Show selected date title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Schedule for ${DateFormat('EEE, MMM d').format(_selectedDay ?? DateTime.now())}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              const SizedBox(height: 8.0),
              // Display entries for the selected day
              Expanded(
                child: entriesForSelectedDay.isEmpty
                    ? const Center(child: Text('No schedules for this day.'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16.0),
                        itemCount: entriesForSelectedDay.length,
                        itemBuilder: (context, index) {
                          final entry = entriesForSelectedDay[index];
                          // Determine if this entry is the currently active one
                          final activeEntry =
                              scheduleProvider.findActiveScheduleEntry();
                          final isEntryActive =
                              activeEntry != null && activeEntry.id == entry.id;

                          // Display entry details as ListTile
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8.0),
                            child: ListTile(
                              leading: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // LED indicator
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isEntryActive
                                          ? Colors.green
                                          : Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(
                                      width:
                                          8), // Spacing between LED and CircleAvatar
                                  CircleAvatar(
                                      child: Text(
                                          _getDayInitial(entry.dayOfWeek))),
                                ],
                              ),
                              title: Text(
                                  '${_formatTimeOfDay(entry.startTime)} - ${_formatTimeOfDay(entry.endTime)}'),
                              subtitle: Text((entry.mode == 'heating_on'
                                      ? 'Heating on'
                                      : entry.mode == 'heating_off'
                                          ? 'Heating off'
                                          : 'Manual control') +
                                  (entry.mode == 'heating_on'
                                      ? ' at ${entry.targetTemperature}°'
                                      : '') +
                                  (entry.repeat == 'weekly'
                                      ? ' (Weekly)'
                                      : entry.repeat == 'daily'
                                          ? ' (Daily)'
                                          : ' (Once)')),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    tooltip: 'Edit Entry',
                                    onPressed: () {
                                      // Pass scheduleId and entry to edit handler
                                      _editScheduleEntry(
                                          entry.scheduleId, entry);
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete),
                                    tooltip: 'Delete Entry',
                                    onPressed: () {
                                      // Pass context, scheduleId, entry, and selectedDay to delete handler
                                      _showDeleteConfirmation(
                                          context,
                                          entry.scheduleId,
                                          entry,
                                          _selectedDay!);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (!mounted) return; // Check if the widget is still mounted
          _showAddEntryDialog(
              context, Provider.of<ScheduleProvider>(context, listen: false));
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  // Helper method to get day initial (copying from ScheduleEntryScreen)
  String _getDayInitial(int day) {
    switch (day) {
      case 1:
        return 'M';
      case 2:
        return 'T';
      case 3:
        return 'W';
      case 4:
        return 'T';
      case 5:
        return 'F';
      case 6:
        return 'S';
      case 7:
        return 'S';
      default:
        return '';
    }
  }

  // Helper method to format TimeOfDay (copying from ScheduleEntryScreen)
  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  // Helper method to get day name (copying from ScheduleEntryScreen)
  String _getDayName(int day) {
    switch (day) {
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

  // Method to show a dialog to add a new schedule entry
  Future<void> _showAddEntryDialog(
      BuildContext context, ScheduleProvider scheduleProvider) async {
    if (scheduleProvider.schedules.isEmpty) {
      // Show a message if no schedules exist
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please create a schedule first.'),
        ),
      );
      return;
    }

    // Directly show the new entry details dialog for the first schedule
    final firstSchedule = scheduleProvider.schedules.first;
    _showNewEntryDetailsDialog(context, scheduleProvider, firstSchedule,
        _selectedDay ?? DateTime.now());
  }

  // Method to show a dialog to add a new schedule entry details
  Future<void> _showNewEntryDetailsDialog(
      BuildContext context,
      ScheduleProvider scheduleProvider,
      Schedule schedule,
      DateTime initialDate) async {
    final formKey = GlobalKey<FormState>();
    int selectedDay =
        initialDate.weekday; // Default to the selected date's weekday
    TimeOfDay startTime = TimeOfDay.now();
    TimeOfDay endTime = TimeOfDay.now();
    double targetTemperature = 20.0; // Default temperature
    String selectedMode = 'heating_on'; // Default mode
    String selectedRepeat =
        'once'; // Define this variable at the beginning of _showNewEntryDetailsDialog

    return showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add New Schedule Entry'),
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
                  // Only show temperature input if the mode is heating_on
                  if (selectedMode == 'heating_on')
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
                    value: selectedRepeat,
                    decoration: const InputDecoration(
                      labelText: 'Repeat',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'once', child: Text('Once')),
                      DropdownMenuItem(
                          value: 'weekly', child: Text('Every Week')),
                      DropdownMenuItem(
                          value: 'daily', child: Text('Every Day')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => selectedRepeat = value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedMode,
                    decoration: const InputDecoration(
                      labelText: 'Mode',
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'heating_on', child: Text('Heating on')),
                      DropdownMenuItem(
                          value: 'heating_off', child: Text('Heating off')),
                      DropdownMenuItem(
                          value: 'manual', child: Text('Manual control')),
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
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  // Add validation to check if start and end times are the same
                  if (startTime.hour == endTime.hour &&
                      startTime.minute == endTime.minute) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content:
                            Text('Start time and end time cannot be the same.'),
                      ),
                    );
                    return; // Prevent saving if times are the same
                  }

                  // Create a new ScheduleEntry object
                  final newEntry = ScheduleEntry(
                    id: DateTime.now()
                        .millisecondsSinceEpoch
                        .toString(), // Simple unique ID
                    dayOfWeek: selectedDay,
                    startTime: startTime,
                    endTime: endTime,
                    targetTemperature: targetTemperature,
                    mode: selectedMode,
                    repeat: selectedRepeat, // Include the selected repetition
                    scheduleId: schedule.id, // Assign to the selected schedule
                    specificDate: selectedRepeat == 'once'
                        ? _selectedDay?.toShortString()
                        : null, // Set specificDate for 'once' entries
                  );

                  // Add the new entry to the selected schedule using the provider
                  scheduleProvider.addEntryToSchedule(schedule.id, newEntry);

                  Navigator.pop(context); // Close the dialog
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

extension on DateTime {
  String toShortString() {
    return '${year}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
  }
}
