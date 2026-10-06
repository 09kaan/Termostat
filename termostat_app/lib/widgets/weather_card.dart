import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../providers/weather_provider.dart';
import 'package:weather/weather.dart';

class WeatherCard extends StatelessWidget {
  const WeatherCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Consumer<WeatherProvider>(
              builder: (context, weatherProvider, child) {
                final cityName = weatherProvider.weatherData?.areaName ?? 'Unknown Location';
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Weather for $cityName',
                      style: theme.textTheme.titleMedium,
                    ),
                    if (weatherProvider.isLoading)
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: () {
                          Provider.of<WeatherProvider>(context, listen: false)
                              .fetchWeatherForCurrentLocation();
                        },
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Consumer<WeatherProvider>(
              builder: (context, weatherProvider, child) {
                if (weatherProvider.error != null) {
                  return Center(child: Text('Error: ${weatherProvider.error}'));
                }
                if (weatherProvider.weatherData == null) {
                   return const Center(child: Text('Fetching weather...'));
                }
                return _WeatherInfo(weather: weatherProvider.weatherData!);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _WeatherInfo extends StatelessWidget {
  final Weather weather;

  const _WeatherInfo({required this.weather});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    final temperature = weather.temperature?.celsius?.toStringAsFixed(1) ?? 'N/A';
    final humidity = weather.humidity?.toString() ?? 'N/A';
    final condition = weather.weatherDescription ?? 'N/A';
    final icon = _mapWeatherConditionToIcon(weather.weatherConditionCode);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _WeatherItem(
          icon: icon,
          label: 'Condition',
          value: condition,
        ),
        _WeatherItem(
          icon: Icons.thermostat,
          label: 'Temperature',
          value: '$temperature°C',
        ),
        _WeatherItem(
          icon: Icons.water_drop,
          label: 'Humidity',
          value: '$humidity%',
        ),
      ],
    ).animate()
      .fadeIn(duration: 600.ms)
      .slideY(delay: 200.ms);
  }

  IconData _mapWeatherConditionToIcon(int? code) {
    if (code == null) return Icons.cloud;
    if (code >= 200 && code < 300) return Icons.cloud_queue;
    if (code >= 300 && code < 400) return Icons.grain;
    if (code >= 500 && code < 600) return Icons.umbrella;
    if (code >= 600 && code < 700) return Icons.ac_unit;
    if (code >= 700 && code < 800) return Icons.dehaze;
    if (code == 800) return Icons.wb_sunny;
    if (code > 800) return Icons.cloud;
    return Icons.cloud;
  }
}

class _WeatherItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _WeatherItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Column(
      children: [
        Icon(
          icon,
          size: 32,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleMedium,
        ),
      ],
    );
  }
} 