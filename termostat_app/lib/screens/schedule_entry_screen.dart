import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/schedule.dart';
import '../providers/schedule_provider.dart';

class ScheduleEntryScreen extends StatefulWidget {
  final Schedule schedule;

  const ScheduleEntryScreen({
    super.key,
    required this.schedule,
  });

  @override
  State<ScheduleEntryScreen> createState() => _ScheduleEntryScreenState();
}

class _ScheduleEntryScreenState extends State<ScheduleEntryScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.schedule.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddEntryDialog(context),
          ),
        ],
      ),
      body: widget.schedule.entries.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'No schedule entries yet',
                    style: TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _showAddEntryDialog(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Entry'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: widget.schedule.entries.length,
              itemBuilder: (context, index) {
                final entry = widget.schedule.entries[index];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(_getDayInitial(entry.dayOfWeek)),
                    ),
                    title: Text(
                      '${_formatTimeOfDay(entry.startTime)} - ${_formatTimeOfDay(entry.endTime)}',
                    ),
                    subtitle: Text(
                      '${entry.mode.toUpperCase()} at ${entry.targetTemperature}°',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          tooltip: 'Edit Entry',
                          onPressed: () {
                            _editEntry(entry);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          tooltip: 'Delete Entry',
                          onPressed: () =>
                              _showDeleteConfirmation(context, entry),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _editEntry(ScheduleEntry entry) async {
    final formKey = GlobalKey<FormState>();
    int selectedDay = entry.dayOfWeek;
    TimeOfDay startTime = entry.startTime;
    TimeOfDay endTime = entry.endTime;
    double targetTemperature = entry.targetTemperature;
    String selectedMode = entry.mode;

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
                  final updatedEntry = entry.copyWith(
                    dayOfWeek: selectedDay,
                    startTime: startTime,
                    endTime: endTime,
                    targetTemperature: targetTemperature,
                    mode: selectedMode,
                  );

                  final entryIndex = widget.schedule.entries
                      .indexWhere((e) => e.id == entry.id);

                  if (entryIndex != -1) {
                    final List<ScheduleEntry> updatedEntries =
                        List<ScheduleEntry>.from(widget.schedule.entries);
                    updatedEntries[entryIndex] = updatedEntry;

                    final updatedSchedule = widget.schedule.copyWith(
                      entries: updatedEntries,
                    );

                    context
                        .read<ScheduleProvider>()
                        .updateSchedule(updatedSchedule);
                  }

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

  Future<void> _showAddEntryDialog(BuildContext context) async {
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
                    scheduleId: widget.schedule.id,
                    dayOfWeek: selectedDay,
                    startTime: startTime,
                    endTime: endTime,
                    targetTemperature: targetTemperature,
                    mode: selectedMode,
                  );

                  final updatedSchedule = widget.schedule.copyWith(
                    entries: [...widget.schedule.entries, entry],
                  );

                  context
                      .read<ScheduleProvider>()
                      .updateSchedule(updatedSchedule);
                  Navigator.pop(context);
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeleteConfirmation(
      BuildContext context, ScheduleEntry entry) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Entry'),
        content: Text(
          'Are you sure you want to delete the entry for ${_getDayName(entry.dayOfWeek)} '
          'from ${_formatTimeOfDay(entry.startTime)} to ${_formatTimeOfDay(entry.endTime)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final updatedSchedule = widget.schedule.copyWith(
                entries: widget.schedule.entries
                    .where((e) => e.id != entry.id)
                    .toList(),
              );
              context.read<ScheduleProvider>().updateSchedule(updatedSchedule);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

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

  String _getDayInitial(int day) {
    return _getDayName(day)[0];
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
