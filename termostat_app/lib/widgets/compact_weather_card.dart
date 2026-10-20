import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/weather_provider.dart';

/// Uses the existing location/weather provider, never example weather values.
class CompactWeatherCard extends StatelessWidget {
  const CompactWeatherCard({super.key});
  @override
  Widget build(BuildContext context) => Consumer<WeatherProvider>(
        builder: (context, provider, _) {
          final data = provider.weatherData;
          return CompactWeatherSummary(
            city: data?.areaName,
            temperature: data?.temperature?.celsius,
            humidity: data?.humidity,
            condition: _condition(
              data?.weatherConditionCode,
              data?.weatherDescription,
            ),
            icon: _icon(data?.weatherConditionCode),
            loading: provider.isLoading,
            error: provider.error,
            onRefresh: provider.fetchWeatherForCurrentLocation,
          );
        },
      );

  static String? _condition(int? code, String? fallback) {
    if (code == null) return fallback;
    if (code >= 200 && code < 300) return 'Gök gürültülü';
    if (code >= 300 && code < 400) return 'Çisenti';
    if (code >= 500 && code < 600) return 'Yağmurlu';
    if (code >= 600 && code < 700) return 'Karlı';
    if (code >= 700 && code < 800) return 'Puslu';
    if (code == 800) return 'Açık';
    if (code > 800 && code < 900) return 'Bulutlu';
    return fallback;
  }

  static IconData _icon(int? code) {
    if (code == 800) return Icons.wb_sunny_outlined;
    if (code != null && code >= 500 && code < 600)
      return Icons.umbrella_outlined;
    if (code != null && code >= 600 && code < 700) return Icons.ac_unit;
    return Icons.cloud_outlined;
  }
}

class CompactWeatherSummary extends StatelessWidget {
  const CompactWeatherSummary({
    super.key,
    this.city,
    this.temperature,
    this.humidity,
    this.condition,
    this.icon = Icons.cloud_outlined,
    required this.loading,
    this.error,
    required this.onRefresh,
  });
  final String? city, condition, error;
  final double? temperature, humidity;
  final IconData icon;
  final bool loading;
  final VoidCallback onRefresh;
  String number(double? n) => n != null && n.isFinite
      ? n.toStringAsFixed(n % 1 == 0 ? 0 : 1).replaceAll('.', ',')
      : '—';
  @override
  Widget build(BuildContext context) {
    final hasData =
        temperature != null || humidity != null || condition != null;
    final line = hasData
        ? '${number(temperature)} °C · ${condition ?? "Durum yok"} · Nem %${number(humidity)}'
        : loading
            ? 'Hava durumu yükleniyor…'
            : 'Hava durumu alınamadı';
    return Card(
      key: const ValueKey('compact-weather-card'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    city ?? 'Hava durumu',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(line, style: Theme.of(context).textTheme.bodyMedium),
                  if (error != null)
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            hasData
                                ? 'Konum / güncellik uyarısı'
                                : 'Yenilemeyi dene',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Hava durumu uyarısı',
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (dialog) => AlertDialog(
                              title: const Text('Hava durumu'),
                              content: Text(error!),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dialog),
                                  child: const Text('Tamam'),
                                ),
                              ],
                            ),
                          ),
                          icon: const Icon(Icons.more_horiz, size: 18),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            if (loading)
              const SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              IconButton(
                key: const ValueKey('weather-refresh'),
                tooltip: 'Hava durumunu yenile',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
              ),
          ],
        ),
      ),
    );
  }
}
