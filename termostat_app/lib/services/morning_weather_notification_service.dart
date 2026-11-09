import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Ankara için 5 günlük / saatlik hava durumu tahminlerini:
/// 1) Uygulama açıldığında, ön plana geldiğinde ve arka planda her 3 saatte bir (akşamları dahil) çeker,
/// 2) Wi-Fi / internet kesintilerine karşı SharedPreferences içine yerel olarak depolar,
/// 3) Önümüzdeki 5 günün sabah 07:00 bildirimlerini işletim sistemine (zonedSchedule) önceden kaydeder,
/// 4) Test butonuna basıldığında önce güncel veriyi çekmeyi dener (internet yoksa depolanan veriyi kullanır)
///    ve hem anlık hem de 4 saniye gecikmeli bildirim tetikler.
class MorningWeatherNotificationService with WidgetsBindingObserver {
  MorningWeatherNotificationService._();
  static final MorningWeatherNotificationService instance =
      MorningWeatherNotificationService._();

  static const String _prefForecastCacheKey = 'ankara_forecast_hourly_cache_v5';
  static const String _prefLastFetchMsKey = 'ankara_forecast_last_fetch_ms_v5';
  static const int _baseNotificationId = 7070;

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  Timer? _periodicSyncTimer;

  static const NotificationDetails _notifDetails = NotificationDetails(
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    ),
    android: AndroidNotificationDetails(
      'ankara_morning_weather_channel',
      'Sabah Hava Durumu Asistanı',
      channelDescription:
          'Her sabah 07:00 Ankara gün sıcaklığı, yağmur ve mont önerisi',
      importance: Importance.max,
      priority: Priority.high,
    ),
  );

  Future<void> initializeAndSync({String owmApiKey = ''}) async {
    if (!_initialized) {
      WidgetsBinding.instance.addObserver(this);
      try {
        tz.initializeTimeZones();
        tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));
      } catch (_) {}

      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
        defaultPresentAlert: true,
        defaultPresentBanner: true,
        defaultPresentList: true,
        defaultPresentSound: true,
      );
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      try {
        await _notifications.initialize(
          const InitializationSettings(
            iOS: iosSettings,
            android: androidSettings,
          ),
        );
      } catch (e) {
        debugPrint('[WeatherBriefing] Init warning: $e');
      }

      try {
        final iosImpl = _notifications.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        await iosImpl?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
      } catch (_) {}

      _periodicSyncTimer?.cancel();
      _periodicSyncTimer = Timer.periodic(
        const Duration(hours: 3),
        (_) => unawaited(refreshForecastAndSchedule(force: true)),
      );

      _initialized = true;
    }

    // Önce yerel depodaki (offline cache) veriden 5 günlük 07:00 bildirimlerini kur
    await _scheduleFromCache();
    // Ardından internet varsa güncel 5 günlük veriyi çekip depola ve bildirimleri güncelle
    unawaited(refreshForecastAndSchedule(owmApiKey: owmApiKey, force: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(refreshForecastAndSchedule(force: true));
    }
  }

  Future<bool> refreshForecastAndSchedule({
    String owmApiKey = '',
    bool force = false,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!force) {
        final lastFetch = prefs.getInt(_prefLastFetchMsKey) ?? 0;
        final ageMs = DateTime.now().millisecondsSinceEpoch - lastFetch;
        if (ageMs >= 0 && ageMs < 30 * 60 * 1000) {
          await _scheduleFromCache();
          return true;
        }
      }

      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=39.9334&longitude=32.8597&hourly=temperature_2m,precipitation_probability&timezone=Europe%2FIstanbul&forecast_days=5',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return false;

      await prefs.setString(_prefForecastCacheKey, response.body);
      await prefs.setInt(
        _prefLastFetchMsKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      await _scheduleFromRawJson(response.body);
      return true;
    } catch (e) {
      debugPrint('[WeatherBriefing] Fetch offline/fallback to cache: $e');
      await _scheduleFromCache();
      return false;
    }
  }

  Future<void> _scheduleFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_prefForecastCacheKey);
      if (cached != null && cached.isNotEmpty) {
        await _scheduleFromRawJson(cached);
      }
    } catch (_) {}
  }

  Future<void> _scheduleFromRawJson(String rawJson) async {
    try {
      final slots = _parseSlots(rawJson);
      if (slots.isEmpty) return;

      final now = tz.TZDateTime.now(tz.local);

      // 5 günlük tahminleri işletim sistemine kaydet (Wi-Fi kesilse bile sabah 07:00'de çalar)
      for (int dayOffset = 0; dayOffset < 5; dayOffset++) {
        final targetDate = DateTime(now.year, now.month, now.day)
            .add(Duration(days: dayOffset));
        final scheduledTime = tz.TZDateTime(
          tz.local,
          targetDate.year,
          targetDate.month,
          targetDate.day,
          7,
          0,
          0,
        );

        if (scheduledTime.isBefore(now)) continue;

        final summary = _buildDailyBriefingForDate(slots, targetDate);
        if (summary == null) continue;

        await _notifications.zonedSchedule(
          _baseNotificationId + dayOffset,
          summary.title,
          summary.body,
          scheduledTime,
          _notifDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    } catch (e) {
      debugPrint('[WeatherBriefing] Schedule error: $e');
    }
  }

  List<_ForecastSlot> _parseSlots(String rawJson) {
    final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
    final hourly = decoded['hourly'] as Map<String, dynamic>?;
    if (hourly == null) return const [];

    final times = (hourly['time'] as List?) ?? const [];
    final temps = (hourly['temperature_2m'] as List?) ?? const [];
    final pops = (hourly['precipitation_probability'] as List?) ?? const [];

    final result = <_ForecastSlot>[];
    final count = [times.length, temps.length, pops.length]
        .reduce((a, b) => a < b ? a : b);

    for (int i = 0; i < count; i++) {
      final dt = DateTime.tryParse(times[i].toString());
      if (dt == null) continue;
      final t = (temps[i] as num?)?.toDouble() ?? 15.0;
      final p = (pops[i] as num?)?.toInt() ?? 0;
      result.add(_ForecastSlot(dateTime: dt, temp: t, rainProb: p));
    }
    return result;
  }

  _WeatherBriefingMessage? _buildDailyBriefingForDate(
    List<_ForecastSlot> allSlots,
    DateTime targetDate,
  ) {
    final daySlots = allSlots
        .where((s) =>
            s.dateTime.year == targetDate.year &&
            s.dateTime.month == targetDate.month &&
            s.dateTime.day == targetDate.day)
        .toList();

    if (daySlots.isEmpty) return null;

    final isWeekend = targetDate.weekday == DateTime.saturday ||
        targetDate.weekday == DateTime.sunday;

    // Sabah hissedilen değil, gün içi normal sıcaklık (09:00 - 18:00)
    final daytimeSlots = daySlots
        .where((s) => s.dateTime.hour >= 9 && s.dateTime.hour <= 18)
        .toList();
    final refSlots = daytimeSlots.isNotEmpty ? daytimeSlots : daySlots;
    final dayMaxTemp =
        refSlots.map((s) => s.temp).reduce((a, b) => a > b ? a : b).round();

    String coatAdvice;
    if (dayMaxTemp < 15) {
      coatAdvice = 'Hava soğuk ($dayMaxTemp°C), mont giy 🧥';
    } else if (dayMaxTemp <= 17) {
      coatAdvice = 'Hava serin ($dayMaxTemp°C), mont giyebilirsin 🧥';
    } else {
      coatAdvice = 'Hava iyi ($dayMaxTemp°C), mont gerekmez 🤵';
    }

    // Hafta içi işe gidiş (08:00 - 09:00) ve işten çıkış (17:00 sonrası)
    int morningRainProb = 0;
    for (final s in daySlots) {
      if (s.dateTime.hour >= 8 &&
          s.dateTime.hour <= 9 &&
          s.rainProb > morningRainProb) {
        morningRainProb = s.rainProb;
      }
    }

    int eveningRainProb = 0;
    for (final s in daySlots) {
      if (s.dateTime.hour >= 17 && s.rainProb > eveningRainProb) {
        eveningRainProb = s.rainProb;
      }
    }

    int overallRainProb = 0;
    for (final s in daySlots) {
      if (s.rainProb > overallRainProb) overallRainProb = s.rainProb;
    }

    String rainAdvice;
    int headlineRainProb;

    if (isWeekend) {
      headlineRainProb = overallRainProb;
      if (overallRainProb >= 40) {
        rainAdvice = 'Bugün yağmur bekleniyor (%$overallRainProb), şemsiye al ☔';
      } else {
        rainAdvice = 'Bugün yağış beklenmiyor ☀️';
      }
    } else {
      headlineRainProb =
          morningRainProb > eveningRainProb ? morningRainProb : eveningRainProb;
      if (overallRainProb > headlineRainProb) {
        headlineRainProb = overallRainProb;
      }

      final morningRainy = morningRainProb >= 35;
      final eveningRainy = eveningRainProb >= 35;

      if (morningRainy && eveningRainy) {
        rainAdvice =
            'Sabah (08-09: %$morningRainProb) ve akşam 17 sonrası (%$eveningRainProb) yağmurlu, şemsiyeni al ☔';
      } else if (morningRainy) {
        rainAdvice =
            'Sabah 08-09 arası yağmur var (%$morningRainProb), çıkarken şemsiye al ☔';
      } else if (eveningRainy) {
        rainAdvice =
            'Akşam 17\'den sonra yağmur bekleniyor (%$eveningRainProb), şemsiye al ☔';
      } else {
        rainAdvice = 'Sabah 08-09 ve akşam 17 sonrası yağış beklenmiyor.';
      }
    }

    final title = 'Ankara Bugün $dayMaxTemp°C · Yağmur: %$headlineRainProb';
    final body = '$coatAdvice. $rainAdvice';

    return _WeatherBriefingMessage(title: title, body: body);
  }

  Future<String> sendTestNotificationNow({String owmApiKey = ''}) async {
    try {
      if (!_initialized) {
        await initializeAndSync(owmApiKey: owmApiKey);
      }

      // Test butonuna basıldığında hemen güncel veriyi çekmeyi dene; Wi-Fi yoksa depodaki veriyi kullan
      await refreshForecastAndSchedule(owmApiKey: owmApiKey, force: true);

      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_prefForecastCacheKey);

      String title = 'Ankara Bugün 14°C · Yağmur: %65';
      String body =
          'Hava soğuk (14°C), mont giy 🧥. Akşam 17\'den sonra yağmur bekleniyor (%65), şemsiye al ☔';

      if (cached != null && cached.isNotEmpty) {
        try {
          final slots = _parseSlots(cached);
          final msg = _buildDailyBriefingForDate(slots, DateTime.now());
          if (msg != null) {
            title = msg.title;
            body = msg.body;
          }
        } catch (_) {}
      }

      // 1) Anında bildirim gönder
      await _notifications.show(
        7098,
        title,
        body,
        _notifDetails,
      );

      // 2) 4 saniye sonrasına zamanlı bildirim kur (Uygulamayı arka plana attığında / ekranı kilitlediğinde de kesin görünür)
      final nowTz = tz.TZDateTime.now(tz.local).add(const Duration(seconds: 4));
      await _notifications.zonedSchedule(
        7099,
        title,
        body,
        nowTz,
        _notifDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );

      return 'Bildirim tetiklendi (Anlık + 4 sn sonra): $title';
    } catch (e) {
      return 'Bildirim hatası: $e';
    }
  }
}

class _ForecastSlot {
  final DateTime dateTime;
  final double temp;
  final int rainProb;

  const _ForecastSlot({
    required this.dateTime,
    required this.temp,
    required this.rainProb,
  });
}

class _WeatherBriefingMessage {
  final String title;
  final String body;

  const _WeatherBriefingMessage({
    required this.title,
    required this.body,
  });
}
