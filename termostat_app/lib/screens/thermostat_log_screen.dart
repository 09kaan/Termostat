import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import '../providers/thermostat_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/haptics_helper.dart';
import '../widgets/dynamic_climate_chart.dart';
import '../widgets/energy_cost_card.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

class ThermostatLogScreen extends StatefulWidget {
  const ThermostatLogScreen({super.key});

  @override
  State<ThermostatLogScreen> createState() => _ThermostatLogScreenState();
}

class _ThermostatLogScreenState extends State<ThermostatLogScreen> {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  List<LogEntry> _logEntries = [];
  bool _isLoading = true;
  String? _error;
  bool _showHeatingOn = true;

  late DateTime _selectedWeekStart;
  late String _selectedDayKey;

  Map<String, List<RoomLogEntry>> _roomLogsByDay = {};
  bool _isRoomLogsLoading = false;
  String? _roomLogsError;

  String _formatDayKey(DateTime day) =>
      '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  double _parseTimeMinutes(String timeStr) {
    final parts = timeStr.split(':');
    if (parts.length < 2) return 0;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    final s = parts.length > 2 ? (int.tryParse(parts[2]) ?? 0) : 0;
    return (h * 60 + m + s / 60.0).clamp(0.0, 1439.9);
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedWeekStart = now
        .subtract(Duration(days: now.weekday - 1))
        .copyWith(
            hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0);
    _selectedDayKey = _formatDayKey(now);
    _fetchLogData();
    _fetchRoomLogs();
  }

  void _navigateWeek(int offset) {
    HapticsHelper.temperatureStep(
      enabled: context.read<SettingsProvider>().enableHaptics,
    );
    setState(() {
      _selectedWeekStart = _selectedWeekStart
          .add(Duration(days: offset * 7))
          .copyWith(
              hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0);
      _selectedDayKey = _formatDayKey(_selectedWeekStart);
    });
    _fetchRoomLogs();
  }

  String _getWeekRangeText() {
    final endOfWeek = _selectedWeekStart.add(const Duration(days: 6));
    return '${DateFormat('d').format(_selectedWeekStart)} – ${DateFormat('d MMM').format(endOfWeek)}';
  }

  Future<void> _selectWeek() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedWeekStart,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && picked != _selectedWeekStart) {
      final selectedMonday =
          picked.subtract(Duration(days: picked.weekday - 1));
      setState(() {
        _selectedWeekStart = selectedMonday.copyWith(
            hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0);
        _selectedDayKey = _formatDayKey(picked);
      });
      _fetchRoomLogs();
    }
  }

  Future<void> _fetchLogData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final deviceId = Provider.of<ThermostatProvider>(context, listen: false)
              .thermostat
              ?.id ??
          'device1';

      final snapshot = await _database.child('devices/$deviceId/log').get();

      if (snapshot.exists && snapshot.value is Map) {
        final Map<dynamic, dynamic> data =
            snapshot.value as Map<dynamic, dynamic>;
        final parsed = data.entries
            .map((entry) {
              if (entry.value is Map) {
                final entryMap = Map<String, dynamic>.from(entry.value as Map);
                final timestampStr = entryMap['timestamp']?.toString();
                final modeStr = entryMap['mode']?.toString();
                final sourceStr = entryMap['source']?.toString();
                if (timestampStr != null && modeStr != null) {
                  final dt = DateTime.tryParse(timestampStr);
                  if (dt != null) {
                    return LogEntry(
                      timestamp: dt.toLocal(),
                      mode: modeStr == 'on' ? 'on' : 'off',
                      source: sourceStr,
                    );
                  }
                }
              }
              return null;
            })
            .whereType<LogEntry>()
            .toList();

        parsed.sort((a, b) => a.timestamp.compareTo(b.timestamp));

        // Ardışık aynı mod kayıtlarını (eski uygulama açılış loglarını) temizle
        final deduplicated = <LogEntry>[];
        for (final entry in parsed) {
          if (deduplicated.isEmpty || deduplicated.last.mode != entry.mode) {
            deduplicated.add(entry);
          }
        }
        _logEntries = deduplicated;
      } else {
        _logEntries = [];
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Log verileri alınamadı: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Seçili haftanın 7 günü için gece yarısı devrini (midnight rollover)
  /// ve önceki haftadan devreden son kombi durumunu hesaba katarak özet üretir.
  Map<String, DailyLogSummary> _calculateWeekSummaries(
    List<LogEntry> allEntries,
    DateTime weekStart,
  ) {
    final Map<String, DailyLogSummary> summaries = {};
    final now = DateTime.now();

    // Hafta başlamadan önceki son durumu bul (Pazar gecesinden Pazartesi 00:00'a devir)
    String? carryOverMode;
    for (final entry in allEntries) {
      if (entry.timestamp.isBefore(weekStart)) {
        carryOverMode = entry.mode;
      } else {
        break;
      }
    }

    final Map<String, List<LogEntry>> entriesByDay = {};
    for (final entry in allEntries) {
      final key = _formatDayKey(entry.timestamp);
      entriesByDay.putIfAbsent(key, () => []).add(entry);
    }

    for (int i = 0; i < 7; i++) {
      final dayDate = weekStart.add(Duration(days: i));
      final dayKey = _formatDayKey(dayDate);
      final dayEntries = entriesByDay[dayKey] ?? [];

      final startOfDay =
          DateTime(dayDate.year, dayDate.month, dayDate.day, 0, 0, 0);
      final endOfDay =
          DateTime(dayDate.year, dayDate.month, dayDate.day, 23, 59, 59);

      if (startOfDay.isAfter(now)) {
        summaries[dayKey] = DailyLogSummary(
          day: dayKey,
          heatingOnDuration: Duration.zero,
          heatingOffDuration: Duration.zero,
        );
        continue;
      }

      Duration heatingOnDuration = Duration.zero;
      Duration heatingOffDuration = Duration.zero;
      DateTime? lastTimestamp = carryOverMode != null ? startOfDay : null;
      String? lastMode = carryOverMode;

      for (final entry in dayEntries) {
        if (entry.timestamp.isAfter(now)) break;
        if (lastTimestamp != null && lastMode != null) {
          final duration = entry.timestamp.difference(lastTimestamp);
          if (!duration.isNegative) {
            if (lastMode == 'on') {
              heatingOnDuration += duration;
            } else {
              heatingOffDuration += duration;
            }
          }
        }
        lastTimestamp = entry.timestamp;
        lastMode = entry.mode;
      }

      if (lastTimestamp != null && lastMode != null) {
        final effectiveEnd = endOfDay.isAfter(now) ? now : endOfDay;
        if (effectiveEnd.isAfter(lastTimestamp)) {
          final duration = effectiveEnd.difference(lastTimestamp);
          if (lastMode == 'on') {
            heatingOnDuration += duration;
          } else {
            heatingOffDuration += duration;
          }
        }
      }

      carryOverMode = lastMode;
      summaries[dayKey] = DailyLogSummary(
        day: dayKey,
        heatingOnDuration: heatingOnDuration,
        heatingOffDuration: heatingOffDuration,
      );
    }

    return summaries;
  }

  Future<void> _fetchRoomLogs() async {
    if (!mounted) return;
    setState(() {
      _isRoomLogsLoading = true;
      _roomLogsError = null;
      _roomLogsByDay = {};
    });
    try {
      final deviceId = Provider.of<ThermostatProvider>(context, listen: false)
              .thermostat
              ?.id ??
          'device1';
      final List<DateTime> weekDays = List.generate(
          7, (index) => _selectedWeekStart.add(Duration(days: index)));

      for (final day in weekDays) {
        final dayKey = _formatDayKey(day);
        // Önce kök log/$dayKey, yoksa devices/$deviceId/room_logs/$dayKey kontrol et
        var snapshot = await _database.child('log/$dayKey').get();
        if (!snapshot.exists || snapshot.value == null) {
          snapshot = await _database
              .child('devices/$deviceId/room_logs/$dayKey')
              .get();
        }
        if (snapshot.exists && snapshot.value is Map) {
          final Map<dynamic, dynamic> data =
              snapshot.value as Map<dynamic, dynamic>;
          final List<RoomLogEntry> entries = [];
          data.forEach((time, value) {
            if (value is Map) {
              final humidity = value['humidity'];
              final temperature = value['temperature'];
              if (humidity != null || temperature != null) {
                entries.add(RoomLogEntry(
                  time: time.toString(),
                  humidity: humidity != null
                      ? double.tryParse(humidity.toString())
                      : null,
                  temperature: temperature != null
                      ? double.tryParse(temperature.toString())
                      : null,
                ));
              }
            }
          });
          entries.sort((a, b) => b.time.compareTo(a.time));
          _roomLogsByDay[dayKey] = entries;
        } else {
          _roomLogsByDay[dayKey] = [];
        }
      }

      if ((_roomLogsByDay[_selectedDayKey]?.isEmpty ?? true)) {
        final nonEmptyDays = _roomLogsByDay.entries
            .where((e) => e.value.isNotEmpty)
            .map((e) => e.key)
            .toList()
          ..sort((a, b) => b.compareTo(a));
        if (nonEmptyDays.isNotEmpty) {
          _selectedDayKey = nonEmptyDays.first;
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _roomLogsError = 'Sensör geçmişi alınamadı: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRoomLogsLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final axisTextColor = theme.colorScheme.onSurface;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(child: Text('Hata: ${_error!}'));
    }

    final DateTime startOfNextWeek =
        _selectedWeekStart.add(const Duration(days: 7));
    final Map<String, DailyLogSummary> selectedWeekSummaries =
        _calculateWeekSummaries(_logEntries, _selectedWeekStart);

    Duration totalWeekOnDuration = Duration.zero;
    double accumulatedTempSum = 0;
    int tempCount = 0;

    selectedWeekSummaries.forEach((_, summary) {
      totalWeekOnDuration += summary.heatingOnDuration;
    });

    _roomLogsByDay.forEach((dayKey, entries) {
      final parsedDate = DateTime.tryParse(dayKey);
      if (parsedDate != null &&
          !parsedDate.isBefore(_selectedWeekStart) &&
          parsedDate.isBefore(startOfNextWeek)) {
        for (final e in entries) {
          if (e.temperature != null) {
            accumulatedTempSum += e.temperature!;
            tempCount++;
          }
        }
      }
    });

    // Sadece targetTemperature değiştiğinde dinle (gereksiz rebuild önleme)
    final targetTemp = context.select<ThermostatProvider, double?>(
      (p) => p.thermostat?.targetTemperature,
    );
    final currentTemp = context.select<ThermostatProvider, double?>(
      (p) => p.thermostat?.currentTemperature,
    );
    final weekAvgTemp =
        tempCount > 0 ? accumulatedTempSum / tempCount : (currentTemp ?? 21.0);

    final List<BarChartGroupData> barGroups = [];
    final List<DateTime> weekDays = List.generate(
        7, (index) => _selectedWeekStart.add(Duration(days: index)));

    for (int i = 0; i < 7; i++) {
      final day = weekDays[i];
      final dayKey = _formatDayKey(day);
      final summary = selectedWeekSummaries[dayKey];

      final onDuration = summary?.heatingOnDuration ?? Duration.zero;
      final offDuration = summary?.heatingOffDuration ?? Duration.zero;
      final onHours = onDuration.inMinutes / 60.0;
      final offHours = offDuration.inMinutes / 60.0;

      final isSelectedDay = dayKey == _selectedDayKey;
      final List<BarChartRodData> rods = [];

      if (_showHeatingOn) {
        rods.add(BarChartRodData(
          toY: onHours,
          fromY: 0.0,
          color: (onHours > 0)
              ? (isSelectedDay ? Colors.deepOrange : Colors.deepOrangeAccent)
              : Colors.transparent,
          width: isSelectedDay ? 18 : 14,
          borderRadius: BorderRadius.circular(4),
        ));
      } else {
        rods.add(BarChartRodData(
          toY: offHours,
          fromY: 0.0,
          color: (offHours > 0)
              ? (isSelectedDay ? Colors.blueGrey.shade700 : Colors.blueGrey)
              : Colors.transparent,
          width: isSelectedDay ? 18 : 14,
          borderRadius: BorderRadius.circular(4),
        ));
      }

      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: rods,
        ),
      );
    }

    double maxDataValue = 0.0;
    for (final group in barGroups) {
      for (final rod in group.barRods) {
        if (rod.toY > maxDataValue) {
          maxDataValue = rod.toY;
        }
      }
    }
    final dynamicMaxY =
        maxDataValue < 4.0 ? 4.0 : (maxDataValue + 1).ceilToDouble();

    double dynamicInterval = dynamicMaxY / 4;
    if (dynamicInterval <= 1) {
      dynamicInterval = 1;
    } else if (dynamicInterval <= 2) {
      dynamicInterval = 2;
    } else if (dynamicInterval <= 4) {
      dynamicInterval = 4;
    } else {
      dynamicInterval = 6;
    }

    final Map<String, List<ClimateLogPoint>> climateMap = {
      for (final entry in _roomLogsByDay.entries)
        entry.key: entry.value
            .map(
              (e) => ClimateLogPoint(
                time: e.time,
                minutesFromMidnight: _parseTimeMinutes(e.time),
                temperature: e.temperature,
                humidity: e.humidity,
              ),
            )
            .toList(),
    };

    final daysWithLogs = _roomLogsByDay.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    final recentDays = daysWithLogs.take(7).toList();

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([_fetchLogData(), _fetchRoomLogs()]);
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios),
                  onPressed: () => _navigateWeek(-1),
                ),
                Text(
                  _getWeekRangeText(),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.calendar_today),
                  onPressed: _selectWeek,
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward_ios),
                  onPressed: () => _navigateWeek(1),
                ),
              ],
            ),
          ),

          EnergyCostCard(
            totalOnDuration: totalWeekOnDuration,
            averageTemperature: weekAvgTemp,
          ),

          const SizedBox(height: 4),

          if (_isRoomLogsLoading)
            const Padding(
              padding: EdgeInsets.all(24.0),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            DynamicClimateChartCard(
              weekDays: weekDays,
              logsByDay: climateMap,
              selectedDayKey: _selectedDayKey,
              targetTemperature: targetTemp,
              onDaySelected: (newKey) {
                setState(() => _selectedDayKey = newKey);
              },
            ),

          const SizedBox(height: 8),

          Card(
            elevation: 2,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _showHeatingOn
                            ? 'Günlük Açık Kalma (Saat)'
                            : 'Günlük Kapalı Kalma (Saat)',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          HapticsHelper.modeToggle(
                            enabled:
                                context.read<SettingsProvider>().enableHaptics,
                          );
                          setState(() {
                            _showHeatingOn = !_showHeatingOn;
                          });
                        },
                        icon: const Icon(Icons.swap_horiz, size: 18),
                        label:
                            Text(_showHeatingOn ? 'Kapalı Süre' : 'Açık Süre'),
                      ),
                    ],
                  ),
                  SizedBox(
                    height: 180,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12.0, right: 8.0),
                      child: BarChart(
                        BarChartData(
                          barGroups: barGroups,
                          maxY: dynamicMaxY,
                          minY: 0.0,
                          baselineY: 0.0,
                          titlesData: FlTitlesData(
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                interval: 1.0,
                                getTitlesWidget: (value, meta) {
                                  const weekdays = [
                                    'Pzt',
                                    'Sal',
                                    'Çar',
                                    'Per',
                                    'Cum',
                                    'Cmt',
                                    'Paz'
                                  ];
                                  final dayIndex = value.toInt();
                                  final dayKey = _formatDayKey(
                                      weekDays[dayIndex % weekDays.length]);
                                  final isSelected = dayKey == _selectedDayKey;
                                  final style = TextStyle(
                                    color: isSelected
                                        ? Colors.deepOrangeAccent
                                        : axisTextColor,
                                    fontWeight: isSelected
                                        ? FontWeight.w900
                                        : FontWeight.bold,
                                    fontSize: 12,
                                  );
                                  final text =
                                      weekdays[dayIndex % weekdays.length];
                                  return SideTitleWidget(
                                    axisSide: meta.axisSide,
                                    space: 4.0,
                                    child: Text(text, style: style),
                                  );
                                },
                                reservedSize: 28,
                              ),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                interval: dynamicInterval,
                                getTitlesWidget: (value, meta) {
                                  final style = TextStyle(
                                    color: axisTextColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10,
                                  );
                                  if (value % dynamicInterval == 0) {
                                    return SideTitleWidget(
                                      axisSide: meta.axisSide,
                                      space: 4.0,
                                      child: Text('${value.toInt()}s',
                                          style: style),
                                    );
                                  }
                                  return const SizedBox.shrink();
                                },
                                reservedSize: 32,
                              ),
                            ),
                            topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                          ),
                          gridData: const FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                          extraLinesData: ExtraLinesData(
                            horizontalLines: [
                              HorizontalLine(
                                y: 0.0,
                                color: axisTextColor.withOpacity(0.3),
                                strokeWidth: 1,
                              ),
                            ],
                          ),
                          barTouchData: BarTouchData(
                            touchCallback: (event, response) {
                              if (event is FlTapUpEvent &&
                                  response?.spot != null) {
                                final idx =
                                    response!.spot!.touchedBarGroupIndex;
                                if (idx >= 0 && idx < weekDays.length) {
                                  HapticsHelper.temperatureStep(
                                    enabled: context
                                        .read<SettingsProvider>()
                                        .enableHaptics,
                                  );
                                  setState(() {
                                    _selectedDayKey =
                                        _formatDayKey(weekDays[idx]);
                                  });
                                }
                              }
                            },
                            touchTooltipData: BarTouchTooltipData(
                              getTooltipItem:
                                  (group, groupIndex, rod, rodIndex) {
                                final day = weekDays[group.x.toInt()];
                                final dayKey = _formatDayKey(day);
                                final summary = selectedWeekSummaries[dayKey];
                                final duration = _showHeatingOn
                                    ? (summary?.heatingOnDuration ??
                                                Duration.zero)
                                            .inMinutes /
                                        60.0
                                    : (summary?.heatingOffDuration ??
                                                Duration.zero)
                                            .inMinutes /
                                        60.0;
                                final mode =
                                    _showHeatingOn ? 'Açık' : 'Kapalı';

                                return BarTooltipItem(
                                  '${DateFormat('d MMM').format(day)}\n$mode: ${duration.toStringAsFixed(1)} saat',
                                  const TextStyle(color: Colors.white),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Detaylı Sensör Kayıtları',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          if (_roomLogsError != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(_roomLogsError!),
            )
          else
            ...recentDays.map((dayKey) {
              final day = DateTime.parse(dayKey);
              final entries = _roomLogsByDay[dayKey] ?? [];
              if (entries.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding:
                    const EdgeInsets.only(bottom: 12.0, left: 12, right: 12),
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: ExpansionTile(
                    key: ValueKey('tile_${dayKey}_${dayKey == _selectedDayKey}'),
                    initiallyExpanded: dayKey == _selectedDayKey,
                    title: Text(
                      DateFormat('EEEE, MMM d').format(day),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    subtitle: Text('${entries.length} ölçüm kaydı'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: Column(
                          children: [
                            Container(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 4.0),
                              child: const Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Text('Saat',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13)),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Row(
                                      children: [
                                        Icon(Icons.thermostat,
                                            size: 16, color: Colors.deepOrange),
                                        SizedBox(width: 4),
                                        Text('Isı (°C)',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13)),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Row(
                                      children: [
                                        Icon(Icons.water_drop,
                                            size: 16, color: Colors.lightBlue),
                                        SizedBox(width: 4),
                                        Text('Nem (%)',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1, thickness: 1),
                            ...List.generate(entries.length, (i) {
                              final e = entries[i];
                              final isEven = i % 2 == 0;
                              return Container(
                                color: isEven
                                    ? theme.colorScheme.onSurface
                                        .withOpacity(0.04)
                                    : Colors.transparent,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4.0),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: Text(e.time,
                                          style: const TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 13)),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        e.temperature != null
                                            ? '${e.temperature!.toStringAsFixed(1)}°C'
                                            : '-',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        e.humidity != null
                                            ? '%${e.humidity!.toStringAsFixed(0)}'
                                            : '-',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Colors.lightBlue,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class LogEntry {
  final DateTime timestamp;
  final String mode;
  final String? source;

  LogEntry({required this.timestamp, required this.mode, this.source});
}

class DailyLogSummary {
  final String day;
  final Duration heatingOnDuration;
  final Duration heatingOffDuration;

  DailyLogSummary({
    required this.day,
    required this.heatingOnDuration,
    required this.heatingOffDuration,
  });
}

class RoomLogEntry {
  final String time;
  final double? temperature;
  final double? humidity;
  RoomLogEntry({required this.time, this.temperature, this.humidity});
}
