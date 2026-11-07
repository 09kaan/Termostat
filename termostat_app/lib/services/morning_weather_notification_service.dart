import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Ankara için 5 günlük / 3 saatlik OpenWeatherMap tahminlerini:
/// 1) Uygulama her açıldığında ve ön plana (resumed) geldiğinde,
/// 2) Uygulama açıkken her akşam (18:00 - 23:59 arası) ve 2 saatte bir otomatik olarak çeker.
/// Her çekişte mevcut 07:00 bildirimlerini en güncel tahminle üzerine yazar (overwrite).
///
/// Özellikler:
/// - Doğrudan günün normal sıcaklığına (temp) bakar (hissedilen veya sabah sıcaklığına değil):
///   * < 15°C      -> "Hava soğuk, mont giy 🧥"
///   * 15°C - 17°C -> "Hava serin, mont giyebilirsin 🧥"
///   * > 17°C      -> "Hava ılıman, mont gerekmez 🤵"
/// - Hafta içi (Pzt-Cum): Sabah 08:00-09:00 ve akşam 17:00 sonrası yağmura odaklanır.
/// - Hafta sonu (Cmt-Paz): Saat kısıtlaması olmadan tüm günün genel yağmur oranına bakar.
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
  Timer? _periodicRefreshTimer;

  /// Uygulama açılışında (ör. main.dart veya HomeScreen initState içinde) çağırın.
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

      _periodicRefreshTimer?.cancel();
      _periodicRefreshTimer = Timer.periodic(
        const Duration(hours: 2),
        (_) {
          if (_apiKey.isNotEmpty) {
            refreshForecastAndSchedule(owmApiKey: _apiKey, force: true);
          }
        },
      );
    }

    await _scheduleFromCache();

    if (_apiKey.isNotEmpty) {
      await refreshForecastAndSchedule(owmApiKey: _apiKey, force: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _apiKey.isNotEmpty) {
      _refreshIfNeededOnResume();
    }
  }

  Future<void> _refreshIfNeededOnResume() async {
    final prefs = await SharedPreferences.getInstance();
    final lastMs = prefs.getInt(_prefLastFetchMsKey) ?? 0;
    final now = DateTime.now();
    final elapsedMin = (now.millisecondsSinceEpoch - lastMs) / 60000.0;

    // Akşam 18:00 - 23:59 arasındaysa 15 dakikada bir, gündüz ise 45 dakikada bir en yeniyi çeker
    final isEvening = now.hour >= 18;
    if (elapsedMin >= (isEvening ? 15 : 45)) {
      await refreshForecastAndSchedule(owmApiKey: _apiKey, force: true);
    }
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefEnabledKey) ?? true;
  }

  Future<void> setEnabled(bool enabled, {required String owmApiKey}) async {
    _apiKey = owmApiKey.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabledKey, enabled);
    if (!enabled) {
      for (int i = 0; i < 5; i++) {
        await _notifications.cancel(_baseNotificationId + i);
      }
    } else {
      await refreshForecastAndSchedule(owmApiKey: _apiKey, force: true);
    }
  }

  Future<void> refreshForecastAndSchedule({
    required String owmApiKey,
    bool force = false,
  }) async {
    try {
      final enabled = await isEnabled();
      if (!enabled) return;

      final uri = Uri.parse(
        'https://api.openweathermap.org/data/2.5/forecast?q=$_city&appid=$owmApiKey&units=metric&lang=tr',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefForecastCacheKey, response.body);
      await prefs.setInt(
        _prefLastFetchMsKey,
        DateTime.now().millisecondsSinceEpoch,
      );

      await _scheduleFromRawJson(response.body);
    } catch (e) {
      debugPrint('[WeatherBriefing] Forecast fetch skipped/offline: $e');
    }
  }

  Future<void> _scheduleFromCache() async {
    final enabled = await isEnabled();
    if (!enabled) return;
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
              channelDescription:
                  'Her sabah 07:00 Ankara gün sıcaklığı, yağmur ve mont önerisi',
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

    // Gündüz (09:00 - 18:00) normal gün sıcaklığı (hissedilen veya sabah ayazı değil)
    final daytimeSlots =
        daySlots.where((s) => s.hour >= 9 && s.hour <= 18).toList();
    final refSlots = daytimeSlots.isNotEmpty ? daytimeSlots : daySlots;

    // Günün tepe (maksimum) normal sıcaklığı (hava durumu raporlarındaki "Bugün X derece" değeri)
    final dayMaxTemp =
        refSlots.map((s) => s.temp).reduce((a, b) => a > b ? a : b).round();

    // 1. DOĞRUDAN GÜNÜN NORMAL SICAKLIĞINA GÖRE MONT KURALI (<15, 15-17, >17)
    String coatAdvice;
    if (dayMaxTemp < 15) {
      coatAdvice = 'Hava soğuk ($dayMaxTemp°C), mont giy 🧥';
    } else if (dayMaxTemp <= 17) {
      coatAdvice = 'Hava serin ($dayMaxTemp°C), mont giyebilirsin 🧥';
    } else {
      coatAdvice = 'Hava iyi ($dayMaxTemp°C), mont gerekmez 🤵';
    }

    // 2. YAĞMUR KURALI (Hafta sonu genel, Hafta içi 08-09 ve 17+ odaklı)
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
      // HAFTA SONU: Doğrudan günün genel yağmur oranına bakar
      headlineRainProb = overallRainProb;
      if (overallRainProb >= 40) {
        rainAdvice =
            'Bugün yağmur bekleniyor (%$overallRainProb), dışarı çıkarsan şemsiye al ☔';
      } else if (overallRainProb >= 25) {
        rainAdvice =
            'Gün içinde hafif yağış ihtimali var (%$overallRainProb) 🌦️';
      } else {
        rainAdvice = 'Bugün yağış beklenmiyor ☀️';
      }
    } else {
      // HAFTA İÇİ: Sabah 08:00-09:00 ve Akşam 17:00 sonrasına odaklanır
      headlineRainProb = [
        morningRainProb,
        eveningRainProb,
        overallRainProb,
      ].reduce((a, b) => a > b ? a : b);

      final morningRainy = morningRainProb >= 35;
      final eveningRainy = eveningRainProb >= 35;

      if (morningRainy && eveningRainy) {
        rainAdvice =
            'Sabah (08-09: %$morningRainProb) ve akşam 17 sonrası (%$eveningRainProb) yağmurlu, şemsiyeni kesin al ☔';
      } else if (morningRainy) {
        rainAdvice =
            'Sabah 08-09 arası yağmur var (%$morningRainProb), çıkarken şemsiye al ☔';
      } else if (eveningRainy) {
        rainAdvice =
            'Akşam 17\'den sonra yağmur bekleniyor (%$eveningRainProb), yanına şemsiye al ☔';
      } else if (overallRainProb >= 45) {
        rainAdvice =
            'Gün ortasında yağmur geçişi olabilir (%$overallRainProb), şemsiye bulundur 🌂';
      } else {
        rainAdvice = 'Sabah 08-09 ve akşam 17 sonrası yağış beklenmiyor.';
      }
    }

    final title = 'Ankara Bugün $dayMaxTemp°C · Yağmur: %$headlineRainProb';
    final body = '$coatAdvice. $rainAdvice';

    return _WeatherBriefingMessage(title: title, body: body);
  }

  /// Test amaçlı anında bildirim gönderir.
  Future<void> sendTestNotificationNow({required String owmApiKey}) async {
    await initializeAndSync(owmApiKey: owmApiKey);
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_prefForecastCacheKey);

    String title = 'Ankara Bugün 14°C · Yağmur: %65';
    String body =
        'Hava soğuk (14°C), mont giy 🧥. Akşam 17\'den sonra yağmur bekleniyor (%65), yanına şemsiye al ☔';

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
