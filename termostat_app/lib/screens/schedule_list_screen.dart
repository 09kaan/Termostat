import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/schedule_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/weather_provider.dart';
import '../models/schedule.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

class ScheduleListScreen extends StatefulWidget {
  const ScheduleListScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  State<ScheduleListScreen> createState() => _ScheduleListScreenState();
}

class _ScheduleListScreenState extends State<ScheduleListScreen> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
  }

  Future<void> _editScheduleEntry(
      String scheduleId, ScheduleEntry entry) async {
    final formKey = GlobalKey<FormState>();
    int selectedDay = entry.dayOfWeek;
    TimeOfDay startTime = entry.startTime;
    TimeOfDay endTime = entry.endTime;
    double targetTemperature = entry.targetTemperature;
    String selectedMode = entry.mode.isNotEmpty ? entry.mode : 'heating_on';
    bool optimumStart = entry.optimumStart;

    return showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Zamanlamayı Düzenle'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    value: selectedDay,
                    decoration: const InputDecoration(
                      labelText: 'Gün',
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
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Başlangıç Saati'),
                    trailing: Text(
                      _formatTimeOfDay(startTime),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
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
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Bitiş Saati'),
                    trailing: Text(
                      _formatTimeOfDay(endTime),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
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
                  const SizedBox(height: 8),
                  if (selectedMode == 'heating_on')
                    TextFormField(
                      initialValue: targetTemperature.toString(),
                      decoration: const InputDecoration(
                        labelText: 'Hedef Sıcaklık',
                        suffixText: '°C',
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Lütfen bir sıcaklık girin';
                        }
                        final temp = double.tryParse(value);
                        if (temp == null || temp < 10 || temp > 30) {
                          return 'Sıcaklık 10°C ile 30°C arasında olmalı';
                        }
                        return null;
                      },
                      onChanged: (value) {
                        targetTemperature = double.tryParse(value) ?? 21.0;
                      },
                    ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedMode,
                    decoration: const InputDecoration(
                      labelText: 'Kombi Modu',
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'heating_on', child: Text('Kombi Açık (Isıtma)')),
                      DropdownMenuItem(
                          value: 'heating_off', child: Text('Kombi Kapalı')),
                      DropdownMenuItem(
                          value: 'manual', child: Text('Manuel Kontrol')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => selectedMode = value);
                      }
                    },
                  ),
                  if (selectedMode == 'heating_on') ...[
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(
                        Icons.ac_unit_rounded,
                        color: Colors.lightBlue,
                      ),
                      title: const Text(
                        'Soğuk Havada Erken Başlat',
                        style: TextStyle(fontSize: 14),
                      ),
                      subtitle: const Text(
                        'Dış hava ≤ 5°C ise kombiyi 25 dk erken açar',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: optimumStart,
                      onChanged: (val) => setState(() => optimumStart = val),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  if (startTime.hour == endTime.hour &&
                      startTime.minute == endTime.minute) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content:
                            Text('Başlangıç ve bitiş saati aynı olamaz.'),
                      ),
                    );
                    return;
                  }

                  final updatedEntry = entry.copyWith(
                    dayOfWeek: selectedDay,
                    startTime: startTime,
                    endTime: endTime,
                    targetTemperature: targetTemperature,
                    mode: selectedMode,
                    scheduleId: scheduleId,
                    optimumStart: optimumStart,
                  );

                  Provider.of<ScheduleProvider>(context, listen: false)
                      .updateEntryInSchedule(scheduleId, updatedEntry);

                  Navigator.pop(context);
                }
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeleteConfirmation(BuildContext context, String scheduleId,
      ScheduleEntry entry, DateTime selectedDay) async {
    String confirmationMessage;
    if (entry.repeat == 'once') {
      confirmationMessage =
          '${_getDayName(entry.dayOfWeek)} günü ${_formatTimeOfDay(entry.startTime)} - ${_formatTimeOfDay(entry.endTime)} arasındaki tek seferlik zamanlamayı silmek istediğinize emin misiniz?';
    } else {
      confirmationMessage =
          '${_getDayName(entry.dayOfWeek)} günü ${_formatTimeOfDay(entry.startTime)} - ${_formatTimeOfDay(entry.endTime)} arasındaki tekrarlayan zamanlamayı nasıl silmek istersiniz?';
    }

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Zamanlamayı Sil'),
        content: Text(confirmationMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç'),
          ),
          if (entry.repeat != 'once')
            TextButton(
              onPressed: () {
                if (!mounted) return;
                final dateToExclude =
                    '${selectedDay.year}-${selectedDay.month.toString().padLeft(2, '0')}-${selectedDay.day.toString().padLeft(2, '0')}';
                final updatedExcludedDates =
                    List<String>.from(entry.excludedDates)..add(dateToExclude);
                final updatedEntry =
                    entry.copyWith(excludedDates: updatedExcludedDates);
                Provider.of<ScheduleProvider>(context, listen: false)
                    .updateEntryInSchedule(scheduleId, updatedEntry);
                Navigator.pop(context);
              },
              child: const Text('Sadece Bugün İçin Sil'),
            ),
          ElevatedButton(
            onPressed: () {
              if (!mounted) return;
              Provider.of<ScheduleProvider>(context, listen: false)
                  .removeEntryFromSchedule(scheduleId, entry.id);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Tümünü Sil'),
          ),
        ],
      ),
    );
  }

  List<ScheduleEntry> _getEntriesForDay(DateTime day) {
    final scheduleProvider =
        Provider.of<ScheduleProvider>(context, listen: false);
    final entries = <ScheduleEntry>[];
    final normalizedDay = DateTime(day.year, day.month, day.day);
    final formattedDay =
        '${normalizedDay.year}-${normalizedDay.month.toString().padLeft(2, '0')}-${normalizedDay.day.toString().padLeft(2, '0')}';

    for (final schedule in scheduleProvider.schedules) {
      for (final entry in schedule.entries) {
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
    entries.sort((a, b) => _timeOfDayToDateTime(a.startTime)
        .compareTo(_timeOfDayToDateTime(b.startTime)));
    return entries;
  }

  DateTime _timeOfDayToDateTime(TimeOfDay time) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, time.hour, time.minute);
  }

  @override
  Widget build(BuildContext context) {
    final outdoorTemp = context.watch<WeatherProvider>().outdoorCelsius;
    final globalOptimum = context.watch<SettingsProvider>().optimumStartEnabled;

    final body = Consumer<ScheduleProvider>(
      builder: (context, scheduleProvider, _) {
        if (scheduleProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (scheduleProvider.error != null) {
          return Center(child: Text('Hata: ${scheduleProvider.error}'));
        }

        final entriesForSelectedDay =
            _getEntriesForDay(_selectedDay ?? DateTime.now());

        return Column(
          children: [
            TableCalendar(
              availableGestures: widget.embedded
                  ? AvailableGestures.verticalSwipe
                  : AvailableGestures.all,
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
                final nextFormat = _calendarFormat == CalendarFormat.month
                    ? CalendarFormat.twoWeeks
                    : _calendarFormat == CalendarFormat.twoWeeks
                        ? CalendarFormat.week
                        : CalendarFormat.month;

                if (_calendarFormat != nextFormat) {
                  setState(() {
                    _calendarFormat = nextFormat;
                  });
                }
              },
              onPageChanged: (focusedDay) {
                _focusedDay = focusedDay;
              },
              eventLoader: (day) {
                final formattedDay =
                    '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

                final hasRelevantEntry =
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

                return hasRelevantEntry ? ['event'] : [];
              },
              headerStyle: const HeaderStyle(formatButtonShowsNext: false),
            ),
            const SizedBox(height: 8.0),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${DateFormat('d MMM EEEE').format(_selectedDay ?? DateTime.now())} Programı',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  if (globalOptimum)
                    const Tooltip(
                      message: 'Genel Soğuk Hava Erken Başlatma Aktif',
                      child: Icon(
                        Icons.ac_unit_rounded,
                        size: 18,
                        color: Colors.lightBlue,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8.0),
            Expanded(
              child: entriesForSelectedDay.isEmpty
                  ? const Center(
                      child: Text(
                        'Bu gün için zamanlama yok. Sağ alttaki + ile ekleyebilirsin.',
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16.0),
                      itemCount: entriesForSelectedDay.length,
                      itemBuilder: (context, index) {
                        final entry = entriesForSelectedDay[index];
                        final activeEntry =
                            scheduleProvider.findActiveScheduleEntry(
                          outdoorTempCelsius: outdoorTemp,
                          globalOptimumStart: globalOptimum,
                        );
                        final isEntryActive =
                            activeEntry != null && activeEntry.id == entry.id;
                        final hasOptimum =
                            (entry.optimumStart || globalOptimum) &&
                            entry.mode == 'heating_on';

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8.0),
                          child: ListTile(
                            leading: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
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
                                const SizedBox(width: 8),
                                CircleAvatar(
                                  child: Text(_getDayInitial(entry.dayOfWeek)),
                                ),
                              ],
                            ),
                            title: Text(
                              '${_formatTimeOfDay(entry.startTime)} - ${_formatTimeOfDay(entry.endTime)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              (entry.mode == 'heating_on'
                                      ? 'Kombi Açık (${entry.targetTemperature}°C)'
                                      : entry.mode == 'heating_off'
                                          ? 'Kombi Kapalı'
                                          : 'Manuel Kontrol') +
                                  (entry.repeat == 'weekly'
                                      ? ' · Haftalık'
                                      : entry.repeat == 'daily'
                                          ? ' · Her Gün'
                                          : ' · Tek Seferlik') +
                                  (hasOptimum ? '\n❄️ Soğuk Havada 25 dk Erken Başlatma' : ''),
                            ),
                            isThreeLine: hasOptimum,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  tooltip: 'Düzenle',
                                  onPressed: () {
                                    _editScheduleEntry(entry.scheduleId, entry);
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete),
                                  tooltip: 'Sil',
                                  onPressed: () {
                                    _showDeleteConfirmation(context,
                                        entry.scheduleId, entry, _selectedDay!);
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
    );
    final addButton = FloatingActionButton(
      onPressed: () {
        if (!mounted) return;
        _showAddEntryDialog(
            context, Provider.of<ScheduleProvider>(context, listen: false));
      },
      tooltip: 'Zamanlama ekle',
      child: const Icon(Icons.add),
    );
    if (widget.embedded) {
      return Stack(children: [
        Positioned.fill(child: body),
        Positioned(right: 16, bottom: 16, child: addButton),
      ]);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Takvim')),
      body: body,
      floatingActionButton: addButton,
    );
  }

  String _getDayInitial(int day) {
    switch (day) {
      case 1:
        return 'Pt';
      case 2:
        return 'Sa';
      case 3:
        return 'Ça';
      case 4:
        return 'Pe';
      case 5:
        return 'Cu';
      case 6:
        return 'Ct';
      case 7:
        return 'Pz';
      default:
        return '';
    }
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _getDayName(int day) {
    switch (day) {
      case 1:
        return 'Pazartesi';
      case 2:
        return 'Salı';
      case 3:
        return 'Çarşamba';
      case 4:
        return 'Perşembe';
      case 5:
        return 'Cuma';
      case 6:
        return 'Cumartesi';
      case 7:
        return 'Pazar';
      default:
        return '';
    }
  }

  Future<void> _showAddEntryDialog(
      BuildContext context, ScheduleProvider scheduleProvider) async {
    Schedule? targetSchedule;
    if (scheduleProvider.schedules.isEmpty) {
      targetSchedule = await scheduleProvider.ensureDefaultSchedule();
      if (targetSchedule == null) return;
    } else {
      targetSchedule = scheduleProvider.schedules.first;
    }

    if (!context.mounted) return;
    _showNewEntryDetailsDialog(
      context,
      scheduleProvider,
      targetSchedule,
      _selectedDay ?? DateTime.now(),
    );
  }

  Future<void> _showNewEntryDetailsDialog(
      BuildContext context,
      ScheduleProvider scheduleProvider,
      Schedule schedule,
      DateTime initialDate) async {
    final formKey = GlobalKey<FormState>();
    int selectedDay = initialDate.weekday;
    TimeOfDay startTime = TimeOfDay.now();
    TimeOfDay endTime =
        TimeOfDay(hour: (TimeOfDay.now().hour + 1) % 24, minute: TimeOfDay.now().minute);
    double targetTemperature = 21.0;
    String selectedMode = 'heating_on';
    String selectedRepeat = 'once';
    bool optimumStart = context.read<SettingsProvider>().optimumStartEnabled;

    return showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Yeni Zamanlama Ekle'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    value: selectedDay,
                    decoration: const InputDecoration(
                      labelText: 'Gün',
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
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Başlangıç Saati'),
                    trailing: Text(
                      _formatTimeOfDay(startTime),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
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
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Bitiş Saati'),
                    trailing: Text(
                      _formatTimeOfDay(endTime),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
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
                  const SizedBox(height: 8),
                  if (selectedMode == 'heating_on')
                    TextFormField(
                      initialValue: targetTemperature.toString(),
                      decoration: const InputDecoration(
                        labelText: 'Hedef Sıcaklık',
                        suffixText: '°C',
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Lütfen bir sıcaklık girin';
                        }
                        final temp = double.tryParse(value);
                        if (temp == null || temp < 10 || temp > 30) {
                          return 'Sıcaklık 10°C ile 30°C arasında olmalı';
                        }
                        return null;
                      },
                      onChanged: (value) {
                        targetTemperature = double.tryParse(value) ?? 21.0;
                      },
                    ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedRepeat,
                    decoration: const InputDecoration(
                      labelText: 'Tekrar Sıklığı',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'once', child: Text('Tek Seferlik')),
                      DropdownMenuItem(
                          value: 'weekly', child: Text('Her Hafta')),
                      DropdownMenuItem(
                          value: 'daily', child: Text('Her Gün')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => selectedRepeat = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedMode,
                    decoration: const InputDecoration(
                      labelText: 'Kombi Modu',
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'heating_on', child: Text('Kombi Açık (Isıtma)')),
                      DropdownMenuItem(
                          value: 'heating_off', child: Text('Kombi Kapalı')),
                      DropdownMenuItem(
                          value: 'manual', child: Text('Manuel Kontrol')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => selectedMode = value);
                      }
                    },
                  ),
                  if (selectedMode == 'heating_on') ...[
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(
                        Icons.ac_unit_rounded,
                        color: Colors.lightBlue,
                      ),
                      title: const Text(
                        'Soğuk Havada Erken Başlat',
                        style: TextStyle(fontSize: 14),
                      ),
                      subtitle: const Text(
                        'Dış hava ≤ 5°C ise kombiyi 25 dk erken açar',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: optimumStart,
                      onChanged: (val) => setState(() => optimumStart = val),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  if (startTime.hour == endTime.hour &&
                      startTime.minute == endTime.minute) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content:
                            Text('Başlangıç ve bitiş saati aynı olamaz.'),
                      ),
                    );
                    return;
                  }

                  final newEntry = ScheduleEntry(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    dayOfWeek: selectedDay,
                    startTime: startTime,
                    endTime: endTime,
                    targetTemperature: targetTemperature,
                    mode: selectedMode,
                    repeat: selectedRepeat,
                    scheduleId: schedule.id,
                    specificDate: selectedRepeat == 'once'
                        ? (_selectedDay ?? DateTime.now()).toShortString()
                        : null,
                    optimumStart: optimumStart,
                  );

                  scheduleProvider.addEntryToSchedule(schedule.id, newEntry);
                  Navigator.pop(context);
                }
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }
}

extension on DateTime {
  String toShortString() {
    return '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
  }
}
