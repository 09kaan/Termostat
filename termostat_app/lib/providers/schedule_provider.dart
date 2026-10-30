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
      _error = 'Programlar yüklenemedi: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Eğer hiç program yoksa varsayılan bir "Ana Program" oluşturup döner.
  Future<Schedule?> ensureDefaultSchedule() async {
    if (_schedules.isNotEmpty) return _schedules.first;
    try {
      final newRef = _database.child('schedules').push();
      final defaultSchedule = Schedule(
        id: newRef.key!,
        name: 'Ana Program',
        entries: [],
        isEnabled: true,
      );
      await newRef.set(defaultSchedule.toJson());
      _schedules.add(defaultSchedule);
      notifyListeners();
      return defaultSchedule;
    } catch (e) {
      _error = 'Varsayılan program oluşturulamadı: $e';
      notifyListeners();
      return null;
    }
  }

  Future<void> addSchedule(Schedule schedule) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final newRef = _database.child('schedules').push();
      final newSchedule = schedule.copyWith(id: newRef.key!);
      await newRef.set(newSchedule.toJson());
      _schedules.add(newSchedule);
    } catch (e) {
      _error = 'Program eklenemedi: $e';
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
      _error = 'Program güncellenemedi: $e';
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
      _error = null;
    } catch (e) {
      _error = 'Program silinemedi: $e';
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
      _error = 'Program durumu değiştirilemedi: $e';
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
        _error = 'Program bulunamadı';
      }
    } catch (e) {
      _error = 'Zamanlama eklenemedi: $e';
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
          _error = 'Zamanlama kaydı bulunamadı';
        }
      } else {
        _error = 'Program bulunamadı';
      }
    } catch (e) {
      _error = 'Zamanlama güncellenemedi: $e';
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
        _error = 'Program bulunamadı';
      }
    } catch (e) {
      _error = 'Zamanlama silinemedi: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Aktif zamanlamayı bulur. Dış hava sıcaklığı <= 5°C ise ve kayıtta (veya genel ayarda)
  /// Optimum Start açıksa başlangıç saatini 25 dakika öne çeker.
  ScheduleEntry? findActiveScheduleEntry({
    double? outdoorTempCelsius,
    bool globalOptimumStart = false,
  }) {
    final now = DateTime.now();
    final currentWeekday = now.weekday;
    final currentTime = TimeOfDay.now();
    final formattedToday =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    ScheduleEntry? activeEntry;

    for (final schedule in _schedules) {
      if (!schedule.isEnabled) continue;

      for (final entry in schedule.entries) {
        if (!entry.isEnabled) continue;
        if (entry.excludedDates.contains(formattedToday)) continue;

        bool dayMatches = false;
        if (entry.repeat == 'daily') {
          dayMatches = true;
        } else if (entry.repeat == 'weekly' &&
            entry.dayOfWeek == currentWeekday) {
          dayMatches = true;
        } else if (entry.repeat == 'once') {
          if (entry.specificDate != null) {
            final specificDateTime = DateTime.tryParse(entry.specificDate!);
            if (specificDateTime != null &&
                specificDateTime.year == now.year &&
                specificDateTime.month == now.month &&
                specificDateTime.day == now.day) {
              dayMatches = true;
            }
          }
        }

        if (dayMatches) {
          var entryStartTime = _timeOfDayToDateTime(entry.startTime);
          final entryEndTime = _timeOfDayToDateTime(entry.endTime);
          final currentTimeDateTime = _timeOfDayToDateTime(currentTime);

          final isColdWeather =
              outdoorTempCelsius != null && outdoorTempCelsius <= 5.0;
          final useOptimum =
              (entry.optimumStart || globalOptimumStart) &&
              (entry.mode == 'heating_on' || entry.mode == 'heat');

          if (useOptimum && isColdWeather) {
            entryStartTime =
                entryStartTime.subtract(const Duration(minutes: 25));
          }

          if (!currentTimeDateTime.isBefore(entryStartTime) &&
              currentTimeDateTime.isBefore(entryEndTime)) {
            activeEntry = entry;
          }
        }
      }
    }

    return activeEntry;
  }

  DateTime _timeOfDayToDateTime(TimeOfDay time) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, time.hour, time.minute);
  }

  void startScheduleChecker(ThermostatProvider thermostatProvider) {
    // V10: ESP32 alone executes schedules.
    _timer?.cancel();
  }

  void stopScheduleChecker() {
    _timer?.cancel();
  }

  Timer? _timer;
}
