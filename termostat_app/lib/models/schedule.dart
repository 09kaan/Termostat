import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class Schedule {
  final String id;
  final String name;
  final List<ScheduleEntry> entries;
  bool isEnabled;

  Schedule({
    required this.id,
    required this.name,
    required this.entries,
    this.isEnabled = true,
  });

  factory Schedule.fromJson(Map<String, dynamic> json) {
    final scheduleId = json['id'] as String;
    final entriesRaw = json['entries'];
    List<ScheduleEntry> entriesList = [];
    if (entriesRaw is List) {
      entriesList = entriesRaw
          .whereType<Map>()
          .map((e) => ScheduleEntry.fromJson(
              Map<String, dynamic>.from(e as Map),
              parentScheduleId: scheduleId))
          .toList();
    } else {
      // Optionally log or handle the unexpected type
      print('Unexpected entries type: \${entriesRaw}');
    }
    return Schedule(
      id: scheduleId,
      name: json['name'] as String,
      entries: entriesList,
      isEnabled: json['isEnabled'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'entries': entries.map((e) => e.toJson()).toList(),
      'isEnabled': isEnabled,
    };
  }

  Schedule copyWith({
    String? id,
    String? name,
    List<ScheduleEntry>? entries,
    bool? isEnabled,
  }) {
    return Schedule(
      id: id ?? this.id,
      name: name ?? this.name,
      entries: entries ?? this.entries,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }
}

class ScheduleEntry {
  final String id;
  final int dayOfWeek; // 1-7 (Monday-Sunday)
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final double targetTemperature;
  final String mode; // 'heat', 'cool', 'auto', 'off'
  final String scheduleId; // Link back to the parent schedule
  final bool isEnabled; // Whether this specific entry is enabled
  final String repeat; // 'once', 'weekly', 'daily'
  final List<String>
      excludedDates; // Dates when this recurring entry is excluded (YYYY-MM-DD)
  final String? specificDate; // For 'once' entries: YYYY-MM-DD

  ScheduleEntry({
    required this.id,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.targetTemperature,
    required this.mode,
    required this.scheduleId,
    this.isEnabled = true,
    this.repeat = 'once', // Default to 'once'
    this.excludedDates = const [], // Default to empty list
    this.specificDate, // specificDate is optional
  });

  factory ScheduleEntry.fromJson(Map<String, dynamic> json,
      {String? parentScheduleId}) {
    return ScheduleEntry(
      id: json['id'] as String,
      dayOfWeek: json['dayOfWeek'] as int,
      startTime: TimeOfDay(
        hour: json['startTimeHour'] as int,
        minute: json['startTimeMinute'] as int,
      ),
      endTime: TimeOfDay(
        hour: json['endTimeHour'] as int,
        minute: json['endTimeMinute'] as int,
      ),
      targetTemperature:
          (json['targetTemperature'] as num?)?.toDouble() ?? 20.0,
      mode: json['mode'] as String? ?? 'heat',
      scheduleId: parentScheduleId ?? json['scheduleId'] as String? ?? '',
      isEnabled: json['isEnabled'] as bool? ?? true,
      repeat: json['repeat'] as String? ?? 'once',
      excludedDates: List<String>.from(
          json['excludedDates'] as List? ?? []), // Read excludedDates
      specificDate: json['specificDate'] as String?, // Read specificDate
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'dayOfWeek': dayOfWeek,
      'startTimeHour': startTime.hour,
      'startTimeMinute': startTime.minute,
      'endTimeHour': endTime.hour,
      'endTimeMinute': endTime.minute,
      'targetTemperature': targetTemperature,
      'mode': mode,
      'scheduleId': scheduleId,
      'isEnabled': isEnabled,
      'repeat': repeat,
      'excludedDates': excludedDates, // Include excludedDates in JSON
      'specificDate': specificDate, // Include specificDate in JSON
    };
  }

  ScheduleEntry copyWith({
    String? id,
    int? dayOfWeek,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    double? targetTemperature,
    String? mode,
    String? scheduleId,
    bool? isEnabled,
    String? repeat,
    List<String>? excludedDates,
    String? specificDate, // Add specificDate to copyWith
  }) {
    return ScheduleEntry(
      id: id ?? this.id,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      targetTemperature: targetTemperature ?? this.targetTemperature,
      mode: mode ?? this.mode,
      scheduleId: scheduleId ?? this.scheduleId,
      isEnabled: isEnabled ?? this.isEnabled,
      repeat: repeat ?? this.repeat,
      excludedDates: excludedDates ?? this.excludedDates,
      specificDate: specificDate ?? this.specificDate,
    );
  }
}
