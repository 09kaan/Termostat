import 'package:flutter/material.dart';

/// Responsive thermostat controls. Does not change scheduling or relay logic.
class ThermostatSummary extends StatelessWidget {
  const ThermostatSummary(
      {super.key,
      required this.temperature,
      required this.humidity,
      required this.target,
      required this.onTargetChanged});
  final double temperature;
  final double humidity;
  final double target;
  final ValueChanged<double> onTargetChanged;
  String _number(double value) =>
      value.isFinite ? value.toStringAsFixed(1).replaceAll('.', ',') : '—';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selected =
        target.isFinite ? target.clamp(10.0, 30.0).toDouble() : 20.0;
    return Card(
        child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Oda iklimi', style: theme.textTheme.titleLarge),
        const SizedBox(height: 20),
        Wrap(spacing: 32, runSpacing: 16, children: [
          _Metric(label: 'Sıcaklık', value: '${_number(temperature)} °C'),
          _Metric(label: 'Nem', value: '%${_number(humidity)}'),
        ]),
        const SizedBox(height: 12),
        Text('Son sensör ölçümü',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: colors.onSurfaceVariant)),
        const Divider(height: 40),
        Text('Hedef sıcaklık', style: theme.textTheme.titleMedium),
        const SizedBox(height: 16),
        Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 12,
            children: [
              IconButton.outlined(
                  tooltip: 'Hedefi yarım derece azalt',
                  onPressed: selected > 10
                      ? () => onTargetChanged((selected - .5).clamp(10.0, 30.0))
                      : null,
                  icon: const Icon(Icons.remove)),
              Text('${_number(selected)}°',
                  style: theme.textTheme.displaySmall?.copyWith(
                      color: colors.primary, fontWeight: FontWeight.w500)),
              IconButton.outlined(
                  tooltip: 'Hedefi yarım derece artır',
                  onPressed: selected < 30
                      ? () => onTargetChanged((selected + .5).clamp(10.0, 30.0))
                      : null,
                  icon: const Icon(Icons.add)),
            ]),
        const SizedBox(height: 12),
        Slider(
            value: selected,
            min: 10,
            max: 30,
            divisions: 40,
            label: '${_number(selected)} °C',
            onChanged: onTargetChanged),
      ]),
    ));
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.headlineSmall),
      ]);
}
