import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class MorningWeatherNotificationService with WidgetsBindingObserver {
  MorningWeatherNotificationService._();
  static final MorningWeatherNotificationService instance =
      MorningWeatherNotificationService._();

  static const String _city = 'Ankara,TR';
  static const String _prefForecastCacheKey = 'ankara_5day_forecast_cache_v4';
  static const String _prefLastFetchMsKey = 'ankara_forecast_last_fetch_ms_v4';
  static const String _prefEnabledKey = 'morning_weather_briefing_enabled_v4';
  static const int _baseNotificationId = 7070;

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  String _apiKey = '';

  Future<void> initializeAndSync({required String owmApiKey}) async {
    _apiKey = owmApiKey.trim();

    if (!_initialized) {
      WidgetsBinding.instance.addObserver(this);
      tz.initializeTimeZones();
      try {
        tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));
      } catch (_) {}

      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      await _notifications.initialize(
        const InitializationSettings(
          iOS: iosSettings,
          android: androidSettings,
        ),
      );
      _initialized = true;
    }

    await _scheduleFromCache();
    if (_apiKey.isNotEmpty) {
      await refreshForecastAndSchedule(owmApiKey: _apiKey, force: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _apiKey.isNotEmpty) {
      refreshForecastAndSchedule(owmApiKey: _apiKey, force: true);
    }
  }

  Future<void> refreshForecastAndSchedule({
    required String owmApiKey,
    bool force = false,
  }) async {
    try {
      final uri = Uri.parse(
        'https://api.openweathermap.org/data/2.5/forecast?q=$_city&appid=$owmApiKey&units=metric&lang=tr',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefForecastCacheKey, response.body);
      await prefs.setInt(_prefLastFetchMsKey, DateTime.now().millisecondsSinceEpoch);

      await _scheduleFromRawJson(response.body);
    } catch (e) {
      debugPrint('[WeatherBriefing] Fetch error: $e');
    }
  }

  Future<void> _scheduleFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_prefForecastCacheKey);
    if (cached != null && cached.isNotEmpty) {
      await _scheduleFromRawJson(cached);
    }
  }

  Future<void> _scheduleFromRawJson(String rawJson) async {
    try {
      final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
      final list = (decoded['list'] as List?) ?? const [];
      if (list.isEmpty) return;

      final now = tz.TZDateTime.now(tz.local);

      for (int dayOffset = 0; dayOffset < 4; dayOffset++) {
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

        final summary = _buildDailyBriefingForDate(list, targetDate);
        if (summary == null) continue;

        await _notifications.zonedSchedule(
          _baseNotificationId + dayOffset,
          summary.title,
          summary.body,
          scheduledTime,
          const NotificationDetails(
            iOS: DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
            android: AndroidNotificationDetails(
              'ankara_morning_weather_channel',
              'Sabah Hava Durumu Asistanı',
              importance: Importance.max,
              priority: Priority.high,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    } catch (e) {
      debugPrint('[WeatherBriefing] Schedule error: $e');
    }
  }

  _WeatherBriefingMessage? _buildDailyBriefingForDate(
    List<dynamic> forecastList,
    DateTime targetDate,
  ) {
    final daySlots = <_ForecastSlot>[];

    for (final raw in forecastList) {
      if (raw is! Map) continue;
      final dtSec = (raw['dt'] as num?)?.toInt();
      if (dtSec == null) continue;

      final localDt =
          DateTime.fromMillisecondsSinceEpoch(dtSec * 1000, isUtc: true)
              .add(const Duration(hours: 3));

      if (localDt.year == targetDate.year &&
          localDt.month == targetDate.month &&
          localDt.day == targetDate.day) {
        final main = raw['main'] as Map? ?? const {};
        final temp = (main['temp'] as num?)?.toDouble() ?? 15.0;
        final pop = (((raw['pop'] as num?)?.toDouble() ?? 0.0) * 100).round();
        final weatherArr = (raw['weather'] as List?) ?? const [];
        final weatherMain = weatherArr.isNotEmpty
            ? (weatherArr.first['main']?.toString().toLowerCase() ?? '')
            : '';
        final isRainCode = weatherMain.contains('rain') ||
            weatherMain.contains('drizzle') ||
            weatherMain.contains('thunderstorm');

        daySlots.add(
          _ForecastSlot(
            hour: localDt.hour,
            temp: temp,
            rainProb: isRainCode && pop < 60 ? 60 : pop,
          ),
        );
      }
    }

    if (daySlots.isEmpty) return null;

    final isWeekend = targetDate.weekday == DateTime.saturday ||
        targetDate.weekday == DateTime.sunday;

    final daytimeSlots =
        daySlots.where((s) => s.hour >= 9 && s.hour <= 18).toList();
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

    int morningRainProb = 0;
    for (final s in daySlots) {
      if (s.hour >= 6 && s.hour <= 10 && s.rainProb > morningRainProb) {
        morningRainProb = s.rainProb;
      }
    }

    int eveningRainProb = 0;
    for (final s in daySlots) {
      if (s.hour >= 15 && s.rainProb > eveningRainProb) {
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
      headlineRainProb = [
        morningRainProb,
        eveningRainProb,
        overallRainProb,
      ].reduce((a, b) => a > b ? a : b);

      final morningRainy = morningRainProb >= 35;
      final eveningRainy = eveningRainProb >= 35;

      if (morningRainy && eveningRainy) {
        rainAdvice = 'Sabah (08-09: %$morningRainProb) ve akşam 17 sonrası (%$eveningRainProb) yağmurlu, şemsiyeni al ☔';
      } else if (morningRainy) {
        rainAdvice = 'Sabah 08-09 arası yağmur var (%$morningRainProb), çıkarken şemsiye al ☔';
      } else if (eveningRainy) {
        rainAdvice = 'Akşam 17\'den sonra yağmur bekleniyor (%$eveningRainProb), şemsiye al ☔';
      } else {
        rainAdvice = 'Sabah 08-09 ve akşam 17 sonrası yağış beklenmiyor.';
      }
    }

    final title = 'Ankara Bugün $dayMaxTemp°C · Yağmur: %$headlineRainProb';
    final body = '$coatAdvice. $rainAdvice';

    return _WeatherBriefingMessage(title: title, body: body);
  }

  Future<void> sendTestNotificationNow({required String owmApiKey}) async {
    await initializeAndSync(owmApiKey: owmApiKey);
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_prefForecastCacheKey);

    String title = 'Ankara Bugün 14°C · Yağmur: %65';
    String body = 'Hava soğuk (14°C), mont giy 🧥. Akşam 17\'den sonra yağmur bekleniyor (%65), şemsiye al ☔';

    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = jsonDecode(cached) as Map<String, dynamic>;
        final list = (decoded['list'] as List?) ?? const [];
        final msg = _buildDailyBriefingForDate(list, DateTime.now());
        if (msg != null) {
          title = msg.title;
          body = msg.body;
        }
      } catch (_) {}
    }

    await _notifications.show(
      7099,
      title,
      body,
      const NotificationDetails(
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        android: AndroidNotificationDetails(
          'ankara_morning_weather_channel',
          'Sabah Hava Durumu Asistanı',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
    );
  }
}

class _ForecastSlot {
  final int hour;
  final double temp;
  final int rainProb;

  const _ForecastSlot({
    required this.hour,
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
