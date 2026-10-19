import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Visual variants only. The existing provider still owns temperature writes.
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
  String _number(double value, {bool turkish = false}) {
    final text = value.isFinite ? value.toStringAsFixed(1) : '—';
    return turkish ? text.replaceAll('.', ',') : text;
  }

  @override
  Widget build(BuildContext context) {
    final selected =
        target.isFinite ? target.clamp(10.0, 30.0).toDouble() : 20.0;
    return AppAppearance.isWarm(context)
        ? _warm(context, selected)
        : _original(context, selected);
  }

  List<Widget> _targetControls(BuildContext context, double value,
          {required bool warm}) =>
      [
        IconButton(
            tooltip: 'Hedefi yarım derece azalt',
            icon: Icon(warm ? Icons.remove : Icons.remove_circle_outline),
            onPressed: value > 10
                ? () => onTargetChanged((value - .5).clamp(10.0, 30.0))
                : null),
        Text(warm ? '${_number(value, turkish: true)}°' : '${_number(value)}°C',
            style: (warm
                    ? Theme.of(context).textTheme.displaySmall
                    : Theme.of(context).textTheme.displayMedium)
                ?.copyWith(
                    color: warm
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.secondary)),
        IconButton(
            tooltip: 'Hedefi yarım derece artır',
            icon: Icon(warm ? Icons.add : Icons.add_circle_outline),
            onPressed: value < 30
                ? () => onTargetChanged((value + .5).clamp(10.0, 30.0))
                : null),
      ];
  Widget _slider(double value) => Slider(
      value: value,
      min: 10,
      max: 30,
      divisions: 40,
      label: _number(value),
      onChanged: onTargetChanged);

  Widget _original(BuildContext context, double value) {
    final theme = Theme.of(context);
    Widget metric(String label, IconData icon, String reading,
            {Widget? note}) =>
        Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                Icon(icon, size: 28, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(reading,
                    style: theme.textTheme.headlineMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 32)),
              ]),
              if (note != null) note,
            ]);
    return Card(
        key: const ValueKey('original-thermostat-card'),
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(
                alignment: WrapAlignment.center,
                spacing: 40,
                runSpacing: 12,
                children: [
                  metric('Temperature', Icons.thermostat,
                      '${_number(temperature)}°C'),
                  metric('Humidity', Icons.water_drop, '${_number(humidity)}%',
                      note: Text(
                          humidity < 40
                              ? 'Low'
                              : humidity > 60
                                  ? 'High'
                                  : 'Normal',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: humidity >= 40 && humidity <= 60
                                  ? FontWeight.bold
                                  : null,
                              color: humidity < 40
                                  ? Colors.orange
                                  : humidity > 60
                                      ? Colors.blue
                                      : Colors.green))),
                ]),
            const SizedBox(height: 10),
            Text('Target Temperature',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: _targetControls(context, value, warm: false)),
            const SizedBox(height: 8),
            _slider(value),
          ]),
        ));
  }

  Widget _warm(BuildContext context, double value) {
    final theme = Theme.of(context);
    Widget metric(String label, String reading) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 4),
          Text(reading, style: theme.textTheme.headlineMedium),
        ]);
    return Column(
        key: const ValueKey('warm-thermostat-card'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 32,
                  runSpacing: 16,
                  children: [
                    metric('Oda iklimi',
                        '${_number(temperature, turkish: true)} °C'),
                    metric('Nem', '%${_number(humidity, turkish: true)}'),
                  ])),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Hedef sıcaklık',
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: 20),
                        Wrap(
                            alignment: WrapAlignment.spaceEvenly,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 12,
                            children:
                                _targetControls(context, value, warm: true)),
                        const SizedBox(height: 16),
                        _slider(value),
                      ]))),
        ]);
  }
}

class WarmModeSelector extends StatelessWidget {
  const WarmModeSelector(
      {super.key, required this.mode, required this.onModeChanged});
  final String mode;
  final ValueChanged<String> onModeChanged;
  static const _modes = {'on': 'Açık', 'off': 'Kapalı', 'manual': 'Manuel'};
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < 340 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.2) {
          return Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in _modes.entries)
                  ChoiceChip(
                      label: Text(entry.value),
                      selected: mode == entry.key,
                      showCheckmark: false,
                      onSelected: (_) => onModeChanged(entry.key))
              ]);
        }
        return SegmentedButton<String>(
          segments: [
            for (final entry in _modes.entries)
              ButtonSegment(value: entry.key, label: Text(entry.value))
          ],
          selected: _modes.containsKey(mode) ? {mode} : {},
          emptySelectionAllowed: true,
          showSelectedIcon: false,
          onSelectionChanged: (values) {
            if (values.isNotEmpty) onModeChanged(values.single);
          },
        );
      });
}
