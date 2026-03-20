import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/schedule.dart';
import '../providers/thermostat_provider.dart';
import 'dart:async';

class ScheduleProvider with ChangeNotifier {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  List<Schedule> _schedules = [];
  bool _isLoading = false;
  String? _error;

  List<Schedule> get schedules => _schedules;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadSchedules() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final snapshot = await _database.child('schedules').get();
      if (snapshot.exists && snapshot.value is Map) {
        final raw = snapshot.value as Map;
        _schedules =
            raw.entries.where((entry) => entry.value is Map).map((entry) {
          final scheduleData = Map<String, dynamic>.from(entry.value as Map);
          scheduleData['id'] = entry.key;
          return Schedule.fromJson(scheduleData);
        }).toList();
      } else {
        _schedules = [];
      }
    } catch (e) {
      _error = 'Failed to load schedules: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addSchedule(Schedule schedule) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final newRef = _database.child('schedules').push();
      await newRef.set(schedule.toJson());
      final newSchedule = schedule.copyWith(id: newRef.key!);
      _schedules.add(newSchedule);
    } catch (e) {
      _error = 'Failed to add schedule: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateSchedule(Schedule schedule) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _database
          .child('schedules/${schedule.id}')
          .update(schedule.toJson());
      final index = _schedules.indexWhere((s) => s.id == schedule.id);
      if (index != -1) {
        _schedules[index] = schedule;
      }
    } catch (e) {
      _error = 'Failed to update schedule: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteSchedule(String scheduleId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _database.child('schedules/$scheduleId').remove();
      _schedules.removeWhere((s) => s.id == scheduleId);
      _error = null; // Clear error on successful deletion
    } catch (e) {
      _error = 'Failed to delete schedule: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> toggleSchedule(String scheduleId, bool enabled) async {
    try {
      final schedule = _schedules.firstWhere((s) => s.id == scheduleId);
      final updatedSchedule = schedule.copyWith(isEnabled: enabled);
      await updateSchedule(updatedSchedule);
    } catch (e) {
      _error = 'Failed to toggle schedule: $e';
      notifyListeners();
    }
  }

  Future<void> addEntryToSchedule(
      String scheduleId, ScheduleEntry entry) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final scheduleIndex = _schedules.indexWhere((s) => s.id == scheduleId);
      if (scheduleIndex != -1) {
        final updatedEntries =
            List<ScheduleEntry>.from(_schedules[scheduleIndex].entries);
        updatedEntries.add(entry);
        final updatedSchedule =
            _schedules[scheduleIndex].copyWith(entries: updatedEntries);

        await _database
            .child('schedules/$scheduleId/entries')
            .set(updatedEntries.map((e) => e.toJson()).toList());

        _schedules[scheduleIndex] = updatedSchedule;
      } else {
        _error = 'Schedule not found';
      }
    } catch (e) {
      _error = 'Failed to add schedule entry: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateEntryInSchedule(
      String scheduleId, ScheduleEntry entry) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final scheduleIndex = _schedules.indexWhere((s) => s.id == scheduleId);
      if (scheduleIndex != -1) {
        final updatedEntries =
            List<ScheduleEntry>.from(_schedules[scheduleIndex].entries);
        final entryIndex = updatedEntries.indexWhere((e) => e.id == entry.id);
        if (entryIndex != -1) {
          updatedEntries[entryIndex] = entry;
          final updatedSchedule =
              _schedules[scheduleIndex].copyWith(entries: updatedEntries);

          await _database
              .child('schedules/$scheduleId/entries')
              .set(updatedEntries.map((e) => e.toJson()).toList());

          _schedules[scheduleIndex] = updatedSchedule;
        } else {
          _error = 'Entry not found';
        }
      } else {
        _error = 'Schedule not found';
      }
    } catch (e) {
      _error = 'Failed to update schedule entry: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> removeEntryFromSchedule(
      String scheduleId, String entryId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final scheduleIndex = _schedules.indexWhere((s) => s.id == scheduleId);
      if (scheduleIndex != -1) {
        final updatedEntries =
            List<ScheduleEntry>.from(_schedules[scheduleIndex].entries)
                .where((e) => e.id != entryId)
                .toList();
        final updatedSchedule =
            _schedules[scheduleIndex].copyWith(entries: updatedEntries);

        await _database
            .child('schedules/$scheduleId/entries')
            .set(updatedEntries.map((e) => e.toJson()).toList());

        _schedules[scheduleIndex] = updatedSchedule;
      } else {
        _error = 'Schedule with ID $scheduleId not found';
      }
    } catch (e) {
      _error = 'Failed to remove schedule entry: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Method to find the currently active schedule entry
  ScheduleEntry? findActiveScheduleEntry() {
    final now = DateTime.now();
    final currentWeekday = now.weekday; // Monday is 1, Sunday is 7
    final currentTime = TimeOfDay.now();

    ScheduleEntry? activeEntry;

    for (var schedule in _schedules) {
      if (!schedule.isEnabled) continue; // Skip disabled schedules

      for (var entry in schedule.entries) {
        // Check if the entry is enabled
        if (!entry.isEnabled) continue;

        bool dayMatches = false;
        if (entry.repeat == 'daily') {
          dayMatches = true;
        } else if (entry.repeat == 'weekly' &&
            entry.dayOfWeek == currentWeekday) {
          dayMatches = true;
        } else if (entry.repeat == 'once') {
          // For 'once' entries, check the specific date
          if (entry.specificDate != null) {
            final specificDateTime = DateTime.parse(entry.specificDate!);
            // Compare date part only
            if (specificDateTime.year == now.year &&
                specificDateTime.month == now.month &&
                specificDateTime.day == now.day) {
              dayMatches = true;
            }
          }
        }

        if (dayMatches) {
          // Check if the current time is within the entry's time range
          final entryStartTime = _timeOfDayToDateTime(entry.startTime);
          final entryEndTime = _timeOfDayToDateTime(entry.endTime);
          final currentTimeDateTime = _timeOfDayToDateTime(currentTime);

          if (currentTimeDateTime.isAfter(entryStartTime) &&
              currentTimeDateTime.isBefore(entryEndTime)) {
            // Found an active entry. If multiple entries overlap, the last one found will be considered active.
            // This is a simple approach, could be refined to prioritize or handle overlaps differently.
            activeEntry = entry;
          }
        }
      }
    }

    return activeEntry;
  }

  // Helper to convert TimeOfDay to DateTime for comparison (uses today's date)
  DateTime _timeOfDayToDateTime(TimeOfDay time) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, time.hour, time.minute);
  }

  // Method to add a timer to periodically check and apply schedule
  void startScheduleChecker(ThermostatProvider thermostatProvider) {
    // Dispose of any existing timer first
    _timer?.cancel();

    // Create a new timer that checks every minute
    _timer = Timer.periodic(const Duration(minutes: 1), (Timer t) {
      final activeEntry = findActiveScheduleEntry();
      if (activeEntry != null) {
        // Apply the active entry's settings
        // Map schedule modes to thermostat modes if necessary
        String thermostatMode = activeEntry.mode;
        if (thermostatMode == 'heating_on') {
          thermostatMode = 'on';
        } else if (thermostatMode == 'heating_off') thermostatMode = 'off';
        // 'manual' maps directly to 'manual'

        // Check if thermostatProvider and its thermostat are available before updating
        if (thermostatProvider.thermostat != null) {
          thermostatProvider.updateMode(thermostatMode);
          thermostatProvider.updateTemperature(activeEntry.targetTemperature);
          print(
              'Applying schedule: Mode: ${activeEntry.mode}, Temp: ${activeEntry.targetTemperature}');
        } else {
          print(
              'Thermostat provider or thermostat not available, cannot apply schedule.');
        }
      } else {
        // If no schedule is active, should we revert to a default mode or leave the current setting?
        // For now, let's leave the current setting unless we decide otherwise.
        print('No active schedule.');
      }
    });
  }

  void stopScheduleChecker() {
    _timer?.cancel();
  }

  Timer? _timer; // Timer instance
}
