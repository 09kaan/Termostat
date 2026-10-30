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
    final scheduleId = json['id'] as String? ?? '';
    final entriesRaw = json['entries'];
    List<ScheduleEntry> entriesList = [];
    if (entriesRaw is List) {
      entriesList = entriesRaw
          .whereType<Map>()
          .map((e) => ScheduleEntry.fromJson(
              Map<String, dynamic>.from(e),
              parentScheduleId: scheduleId))
          .toList();
    } else if (entriesRaw is Map) {
      entriesList = entriesRaw.values
          .whereType<Map>()
          .map((e) => ScheduleEntry.fromJson(
              Map<String, dynamic>.from(e),
              parentScheduleId: scheduleId))
          .toList();
    }
    return Schedule(
      id: scheduleId,
      name: json['name'] as String? ?? 'Ana Program',
      entries: entriesList,
      isEnabled: json['isEnabled'] as bool? ?? true,
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
  final String mode; // 'heating_on', 'heating_off', 'manual'
  final String scheduleId;
  final bool isEnabled;
  final String repeat; // 'once', 'weekly', 'daily'
  final List<String> excludedDates; // YYYY-MM-DD
  final String? specificDate; // YYYY-MM-DD
  final bool optimumStart; // Soğuk havada (<5°C) erken başlatma şalteri

  ScheduleEntry({
    required this.id,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.targetTemperature,
    required this.mode,
    required this.scheduleId,
    this.isEnabled = true,
    this.repeat = 'once',
    this.excludedDates = const [],
    this.specificDate,
    this.optimumStart = false,
  });

  factory ScheduleEntry.fromJson(Map<String, dynamic> json,
      {String? parentScheduleId}) {
    return ScheduleEntry(
      id: json['id']?.toString() ?? '',
      dayOfWeek: (json['dayOfWeek'] as num?)?.toInt() ?? 1,
      startTime: TimeOfDay(
        hour: (json['startTimeHour'] as num?)?.toInt() ?? 8,
        minute: (json['startTimeMinute'] as num?)?.toInt() ?? 0,
      ),
      endTime: TimeOfDay(
        hour: (json['endTimeHour'] as num?)?.toInt() ?? 9,
        minute: (json['endTimeMinute'] as num?)?.toInt() ?? 0,
      ),
      targetTemperature:
          (json['targetTemperature'] as num?)?.toDouble() ?? 21.0,
      mode: json['mode'] as String? ?? 'heating_on',
      scheduleId: parentScheduleId ?? json['scheduleId'] as String? ?? '',
      isEnabled: json['isEnabled'] as bool? ?? true,
      repeat: json['repeat'] as String? ?? 'once',
      excludedDates: List<String>.from(json['excludedDates'] as List? ?? []),
      specificDate: json['specificDate'] as String?,
      optimumStart: json['optimumStart'] as bool? ?? false,
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
      'excludedDates': excludedDates,
      'specificDate': specificDate,
      'optimumStart': optimumStart,
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
    String? specificDate,
    bool? optimumStart,
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
      optimumStart: optimumStart ?? this.optimumStart,
    );
  }
}
