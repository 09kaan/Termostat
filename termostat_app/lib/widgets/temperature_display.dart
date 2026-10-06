import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class TemperatureDisplay extends StatelessWidget {
  final double currentTemperature;
  final double targetTemperature;
  final Function(double) onTemperatureChanged;
  final bool useCelsius;

  const TemperatureDisplay({
    super.key,
    required this.currentTemperature,
    required this.targetTemperature,
    required this.onTemperatureChanged,
    required this.useCelsius,
  });

  String _formatTemperature(double temperature) {
    return '${temperature.toStringAsFixed(1)}°${useCelsius ? 'C' : 'F'}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Text(
              'Current Temperature',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              _formatTemperature(currentTemperature),
              style: theme.textTheme.displayLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ).animate()
              .fadeIn(duration: 600.ms)
              .scale(delay: 200.ms),
            const SizedBox(height: 24),
            Text(
              'Target Temperature',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () {
                    if (targetTemperature > 10.0) {
                      onTemperatureChanged(targetTemperature - 0.5);
                    }
                  },
                ),
                Text(
                  _formatTemperature(targetTemperature),
                  style: theme.textTheme.displayMedium?.copyWith(
                    color: theme.colorScheme.secondary,
                  ),
                ).animate()
                  .fadeIn(duration: 600.ms)
                  .scale(delay: 200.ms),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () {
                    if (targetTemperature < 30.0) {
                      onTemperatureChanged(targetTemperature + 0.5);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Slider(
              value: targetTemperature,
              min: 10.0,
              max: 30.0,
              divisions: 40,
              label: targetTemperature.round().toString(),
              onChanged: onTemperatureChanged,
            ),
          ],
        ),
      ),
    );
  }
} 