import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import '../providers/thermostat_provider.dart';
import 'package:fl_chart/fl_chart.dart'; // Import fl_chart
import 'package:intl/intl.dart'; // Add intl package import

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
  Map<String, DailyLogSummary> _dailyLogSummaries = {};
  bool _showHeatingOn = true;

  // Add selected week state
  late DateTime _selectedWeekStart;

  // NEW: Room logs state
  Map<String, List<RoomLogEntry>> _roomLogsByDay = {};
  bool _isRoomLogsLoading = false;
  String? _roomLogsError;

  @override
  void initState() {
    super.initState();
    // Initialize with current week's Monday at midnight
    _selectedWeekStart = DateTime.now()
        .subtract(Duration(days: DateTime.now().weekday - 1))
        .copyWith(
            hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0);
    _fetchLogData();
    _fetchRoomLogs(); // NEW: fetch room logs
  }

  void _navigateWeek(int offset) {
    setState(() {
      _selectedWeekStart = _selectedWeekStart
          .add(Duration(days: offset * 7))
          .copyWith(
              hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0);
      _fetchLogData(); // Refresh data for the new week
      _fetchRoomLogs(); // NEW: refresh room logs for new week
    });
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
      lastDate: DateTime.now().add(const Duration(
          days: 365)), // Allow selecting up to a year in the future
    );
    if (picked != null && picked != _selectedWeekStart) {
      // Calculate the Monday of the selected week
      final selectedMonday =
          picked.subtract(Duration(days: picked.weekday - 1));
      setState(() {
        _selectedWeekStart = selectedMonday.copyWith(
            hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0);
      });
      _fetchLogData(); // Fetch data for the newly selected week
      _fetchRoomLogs(); // NEW
    }
  }

  Future<void> _fetchLogData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final deviceId = Provider.of<ThermostatProvider>(context, listen: false)
              .thermostat
              ?.id ??
          "device1";

      final snapshot = await _database.child('devices/$deviceId/log').get();

      print('Snapshot exists: ${snapshot.exists}');
      print('Snapshot value is null: ${snapshot.value == null}');

      if (snapshot.exists && snapshot.value != null) {
        final Map<dynamic, dynamic> data =
            snapshot.value as Map<dynamic, dynamic>;
        _logEntries = data.entries
            .map((entry) {
              // Expecting each log entry to be an object with 'timestamp' and 'mode'
              if (entry.value is Map<dynamic, dynamic>) {
                final Map<dynamic, dynamic> entryMap = entry.value;
                try {
                  // Safely access timestamp and mode, providing a default for mode if null
                  final timestampStr = entryMap['timestamp'] as String?;
                  final modeStr = entryMap['mode'] as String?;

                  if (timestampStr != null && modeStr != null) {
                    return LogEntry(
                      timestamp: DateTime.parse(timestampStr),
                      mode: modeStr,
                    );
                  } else {
                    return null; // Skip entries with missing required fields
                  }
                } catch (e) {
                  return null; // Skip invalid entries
                }
              } else {
                return null; // Skip entries that are not maps
              }
            })
            .whereType<LogEntry>()
            .toList(); // Filter out nulls

        // Sort log entries by timestamp
        _logEntries.sort((a, b) => a.timestamp.compareTo(b.timestamp));

        // Process log entries to calculate daily summaries
        _dailyLogSummaries = _calculateDailyLogSummaries(_logEntries);

        // Process log entries to calculate weekly summaries
        // _dailyLogSummaries = _calculateWeeklyLogSummaries(_logEntries);

        print(
            'Calculated daily log summaries count: ${_dailyLogSummaries.length}');
        print('Calculated daily log summaries: $_dailyLogSummaries');
      } else {
        _dailyLogSummaries = {}; // No log data
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to fetch log data: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Map<String, DailyLogSummary> _calculateDailyLogSummaries(
      List<LogEntry> entries) {
    final Map<String, List<LogEntry>> entriesByDay = {};

    // Group entries by day
    for (var entry in entries) {
      final dayKey =
          '${entry.timestamp.year}-${entry.timestamp.month.toString().padLeft(2, '0')}-${entry.timestamp.day.toString().padLeft(2, '0')}';
      entriesByDay.putIfAbsent(dayKey, () => []).add(entry);
    }

    final Map<String, DailyLogSummary> summaries = {};

    // Calculate duration for each day
    entriesByDay.forEach((day, dayEntries) {
      Duration heatingOnDuration = Duration.zero;
      Duration heatingOffDuration = Duration.zero;
      DateTime? lastTimestamp;
      String? lastMode;

      // Sort entries within the day (should already be sorted by fetch, but good practice)
      dayEntries.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      for (var entry in dayEntries) {
        if (lastTimestamp != null && lastMode != null) {
          final duration = entry.timestamp.difference(lastTimestamp);
          if (lastMode == 'on') {
            heatingOnDuration += duration;
          } else if (lastMode == 'off') {
            heatingOffDuration += duration;
          }
        }
        lastTimestamp = entry.timestamp;
        lastMode = entry.mode;
      }

      // Account for the duration from the last log entry of the day to the end of the day
      // or to the current time if it's today
      if (lastTimestamp != null && lastMode != null) {
        final endOfDay = DateTime(lastTimestamp.year, lastTimestamp.month,
            lastTimestamp.day, 23, 59, 59);
        final endTime =
            endOfDay.isAfter(DateTime.now()) ? DateTime.now() : endOfDay;
        final duration = endTime.difference(lastTimestamp);
        if (lastMode == 'on') {
          heatingOnDuration += duration;
        } else if (lastMode == 'off') {
          heatingOffDuration += duration;
        }
      }

      summaries[day] = DailyLogSummary(
        day: day,
        heatingOnDuration: heatingOnDuration,
        heatingOffDuration: heatingOffDuration,
      );
    });

    // Keep only the last 7 days of summaries
    final sortedDays = summaries.keys.toList()..sort();
    final recentDays = sortedDays.length > 7
        ? sortedDays.sublist(sortedDays.length - 7)
        : sortedDays;
    final recentSummaries = <String, DailyLogSummary>{};
    for (var day in recentDays) {
      recentSummaries[day] = summaries[day]!;
    }

    return recentSummaries;
  }

  // NEW: Fetch room logs from log/{YYYY-MM-DD}/{HH:mm:ss}
  Future<void> _fetchRoomLogs() async {
    setState(() {
      _isRoomLogsLoading = true;
      _roomLogsError = null;
      _roomLogsByDay = {};
    });
    try {
      // Get the 7 days of the selected week
      final List<DateTime> weekDays = List.generate(
          7, (index) => _selectedWeekStart.add(Duration(days: index)));
      for (final day in weekDays) {
        final dayKey =
            '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
        final snapshot = await _database.child('log/$dayKey').get();
        if (snapshot.exists && snapshot.value != null) {
          final Map<dynamic, dynamic> data =
              snapshot.value as Map<dynamic, dynamic>;
          final List<RoomLogEntry> entries = [];
          data.forEach((time, value) {
            if (value is Map<dynamic, dynamic>) {
              final humidity = value['humidity'];
              final temperature = value['temperature'];
              if (humidity != null && temperature != null) {
                entries.add(RoomLogEntry(
                  time: time.toString(),
                  humidity: double.tryParse(humidity.toString()),
                  temperature: double.tryParse(temperature.toString()),
                ));
              }
            }
          });
          // Sort by time in reverse order (newest first)
          entries.sort((a, b) => b.time.compareTo(a.time));
          _roomLogsByDay[dayKey] = entries;
        } else {
          _roomLogsByDay[dayKey] = [];
        }
      }
    } catch (e) {
      setState(() {
        _roomLogsError = 'Failed to fetch room logs: \\${e.toString()}';
      });
    } finally {
      setState(() {
        _isRoomLogsLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(child: Text('Error: ${_error!}'));
    }

    if (_dailyLogSummaries.isEmpty) {
      return const Center(child: Text('No log data available.'));
    }

    // Filter log entries for the selected week (inclusive of start, exclusive of end + 1 day)
    final DateTime startOfNextWeek =
        _selectedWeekStart.add(const Duration(days: 7));
    final List<LogEntry> selectedWeekEntries = _logEntries.where((entry) {
      // Check if the entry is on or after the start of the selected week AND before the start of the next week
      return !entry.timestamp.isBefore(_selectedWeekStart) &&
          entry.timestamp.isBefore(startOfNextWeek);
    }).toList();

    // Calculate daily summaries for the selected week
    final Map<String, DailyLogSummary> selectedWeekSummaries =
        _calculateDailyLogSummaries(selectedWeekEntries);

    // Prepare data for the chart
    final List<BarChartGroupData> barGroups = [];
    // Use the 7 days of the selected week for chart groups
    final List<DateTime> weekDays = List.generate(
        7, (index) => _selectedWeekStart.add(Duration(days: index)));

    // Create a bar group for each of the 7 days in the week
    for (int i = 0; i < 7; i++) {
      final day = _selectedWeekStart.add(Duration(days: i));
      final dayKey =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      final summary = selectedWeekSummaries[dayKey];

      final onDuration = summary?.heatingOnDuration ?? Duration.zero;
      final offDuration = summary?.heatingOffDuration ?? Duration.zero;
      final onHours = onDuration.inMinutes / 60.0;
      final offHours = offDuration.inMinutes / 60.0;

      final List<BarChartRodData> rods = [];

      // Always add a rod, even if the duration is 0, to ensure consistent spacing
      if (_showHeatingOn) {
        rods.add(BarChartRodData(
          toY: onHours, // Use calculated hours (will be 0.0 if no data)
          fromY: 0.0,
          color: (onHours > 0)
              ? Colors.blue
              : Colors.transparent, // Make color transparent if 0 hours
          width: 15,
        ));
      } else {
        // Show heating off
        rods.add(BarChartRodData(
          toY: offHours, // Use calculated hours (will be 0.0 if no data)
          fromY: 0.0,
          color: (offHours > 0)
              ? Colors.red
              : Colors.transparent, // Make color transparent if 0 hours
          width: 15,
        ));
      }

      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: rods,
          // You might need to adjust groupVertically to true if bars should stack,
          // but based on the current design, they seem to be independent.
          // groupVertically: true, // Consider if needed
        ),
      );
    }

    // Calculate dynamic maxY based on the maximum value in the data for the selected week
    double maxDataValue = 0.0;
    for (var group in barGroups) {
      for (var rod in group.barRods) {
        if (rod.toY > maxDataValue) {
          maxDataValue = rod.toY;
        }
      }
    }
    // Add 1 to maxY for padding
    final dynamicMaxY = (maxDataValue + 1).ceilToDouble();

    // Calculate dynamic interval to get 4-6 ticks
    // Round up to nearest nice number (1, 2, 5, 10, etc.)
    double dynamicInterval = dynamicMaxY / 5; // Start with 5 ticks
    if (dynamicInterval <= 1) {
      dynamicInterval = 1;
    } else if (dynamicInterval <= 2) {
      dynamicInterval = 2;
    } else if (dynamicInterval <= 5) {
      dynamicInterval = 5;
    } else {
      dynamicInterval = (dynamicInterval / 10).ceil() * 10;
    }

    // Revert to the original layout structure with Column and Expanded
    return Column(
      children: [
        // Week navigation header
        Padding(
          padding: const EdgeInsets.all(16.0),
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
        // Toggle button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _showHeatingOn
                    ? 'Daily Heating On Time'
                    : 'Daily Heating Off Time',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _showHeatingOn = !_showHeatingOn;
                  });
                },
                child: Text(_showHeatingOn ? 'Show Off Time' : 'Show On Time'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 200,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
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
                        const style = TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        );
                        // Use weekday names for labels
                        const weekdays = [
                          'Mon',
                          'Tue',
                          'Wed',
                          'Thu',
                          'Fri',
                          'Sat',
                          'Sun'
                        ];
                        final dayIndex = value.toInt();
                        final text = weekdays[dayIndex % weekdays.length];
                        return SideTitleWidget(
                          axisSide: meta.axisSide,
                          space: 4.0,
                          child: SizedBox(
                              // Provide a fixed width for the label container
                              width: 30,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text(text,
                                      style: style,
                                      textAlign: TextAlign.center),
                                ],
                              )),
                        );
                      },
                      reservedSize:
                          60, // Increase reserved size significantly for vertical stability attempt
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: dynamicInterval,
                      getTitlesWidget: (value, meta) {
                        // Simplified Y-axis labels
                        const style = TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        );
                        Widget text;
                        // Show labels at intervals
                        if (value % dynamicInterval == 0) {
                          text = Text(value.toInt().toString(), style: style);
                        } else {
                          text = Container(); // Hide other labels
                        }
                        return SideTitleWidget(
                          axisSide: meta.axisSide,
                          space: 4.0, // Adjusted space
                          child: text,
                        );
                      },
                      reservedSize: 28, // Adjusted reserved size
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
                  // Add extra lines data
                  horizontalLines: [
                    HorizontalLine(
                      // Ensure full horizontal line is present
                      y: 0.0,
                      color: Colors.black,
                      strokeWidth: 1,
                      // dashArray: [2, 2],
                    ),
                  ],
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      // Use the same date key format as in selectedWeekSummaries
                      final day = weekDays[group.x.toInt()];
                      final dayKey =
                          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
                      final summary = selectedWeekSummaries[dayKey];
                      final duration = _showHeatingOn
                          ? (summary?.heatingOnDuration ?? Duration.zero)
                                  .inMinutes /
                              60.0
                          : (summary?.heatingOffDuration ?? Duration.zero)
                                  .inMinutes /
                              60.0;
                      final mode =
                          _showHeatingOn ? 'Heating On' : 'Heating Off';

                      return BarTooltipItem(
                        '${DateFormat('MMM d').format(day)}\n$mode: ${duration.toStringAsFixed(1)} hours',
                        const TextStyle(color: Colors.white),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        // NEW: Room temperature/humidity logs section
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Room Temperature & Humidity Logs',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
        _isRoomLogsLoading
            ? const Center(child: CircularProgressIndicator())
            : _roomLogsError != null
                ? Center(child: Text(_roomLogsError!))
                : Expanded(
                    child: Builder(
                      builder: (context) {
                        // Get all days with logs, sort descending (newest first), take 7
                        final daysWithLogs = _roomLogsByDay.keys.toList()
                          ..sort((a, b) => b.compareTo(a));
                        final recentDays = daysWithLogs.take(7).toList();
                        return ListView.builder(
                          itemCount: recentDays.length,
                          itemBuilder: (context, index) {
                            final dayKey = recentDays[index];
                            final day = DateTime.parse(dayKey);
                            final entries = _roomLogsByDay[dayKey] ?? [];
                            if (entries.isEmpty) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(
                                  bottom: 12.0, left: 8, right: 8),
                              child: Card(
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        DateFormat('EEEE, MMM d').format(day),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15),
                                      ),
                                      const SizedBox(height: 8),
                                      // Table header
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 4.0),
                                        child: const Row(
                                          children: [
                                            Expanded(
                                              flex: 2,
                                              child: Text('Time',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 13)),
                                            ),
                                            Expanded(
                                              flex: 2,
                                              child: Row(
                                                children: [
                                                  Icon(Icons.thermostat,
                                                      size: 16,
                                                      color: Colors.blueGrey),
                                                  SizedBox(width: 4),
                                                  Text('Temp (°C)',
                                                      style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 13)),
                                                ],
                                              ),
                                            ),
                                            Expanded(
                                              flex: 2,
                                              child: Row(
                                                children: [
                                                  Icon(Icons.water_drop,
                                                      size: 16,
                                                      color: Colors.lightBlue),
                                                  SizedBox(width: 4),
                                                  Text('Hum (%)',
                                                      style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 13)),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Divider(height: 1, thickness: 1),
                                      // Table rows
                                      ...List.generate(entries.length, (i) {
                                        final e = entries[i];
                                        final isEven = i % 2 == 0;
                                        return Container(
                                          color: isEven
                                              ? Colors.grey.withOpacity(0.07)
                                              : Colors.transparent,
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 4.0),
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
                                                      ? e.temperature!
                                                          .toStringAsFixed(1)
                                                      : '-',
                                                  style: TextStyle(
                                                      fontSize: 13,
                                                      color:
                                                          Colors.blueGrey[800]),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  e.humidity != null
                                                      ? e.humidity!
                                                          .toStringAsFixed(1)
                                                      : '-',
                                                  style: TextStyle(
                                                      fontSize: 13,
                                                      color: Colors
                                                          .lightBlue[800]),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
      ],
    );
  }
}

class LogEntry {
  final DateTime timestamp;
  final String mode;

  LogEntry({required this.timestamp, required this.mode});
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
