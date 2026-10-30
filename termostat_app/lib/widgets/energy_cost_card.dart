import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../utils/haptics_helper.dart';

class EnergyCostCard extends StatelessWidget {
  final Duration totalOnDuration;
  final double averageTemperature;

  const EnergyCostCard({
    super.key,
    required this.totalOnDuration,
    required this.averageTemperature,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsProvider>();
    final hapticsEnabled = settings.enableHaptics;
    final hourlyCost = settings.hourlyEnergyCost;

    final totalHours = totalOnDuration.inMinutes / 60.0;
    final estimatedCost = totalHours * hourlyCost;
    final estimatedKwh = totalHours * 2.0; // Varsayılan ortalama 2kW kombi tüketim gücü

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.bolt_rounded, color: Colors.amber, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      'Enerji & Maliyet Tahmini',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined, size: 20),
                  tooltip: 'Birim Maliyet Ayarla',
                  onPressed: () {
                    HapticsHelper.temperatureStep(enabled: hapticsEnabled);
                    _showCostSettingsDialog(context, settings);
                  },
                ),
              ],
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _CostMetricItem(
                  title: 'Çalışma Süresi',
                  value: '${totalHours.toStringAsFixed(1)} saat',
                  icon: Icons.timer_outlined,
                  color: Colors.blue,
                ),
                _CostMetricItem(
                  title: 'Tahmini Tüketim',
                  value: '${estimatedKwh.toStringAsFixed(1)} kWh',
                  icon: Icons.electric_meter_outlined,
                  color: Colors.orange,
                ),
                _CostMetricItem(
                  title: 'Tahmini Tutar',
                  value: '₺${estimatedCost.toStringAsFixed(2)}',
                  icon: Icons.payments_outlined,
                  color: Colors.green,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Ortalama Sıcaklık: ${averageTemperature.toStringAsFixed(1)}°C • Birim Saatlik Ücret: ₺${hourlyCost.toStringAsFixed(2)}/saat',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCostSettingsDialog(BuildContext context, SettingsProvider settings) {
    final controller =
        TextEditingController(text: settings.hourlyEnergyCost.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Birim Enerji Maliyeti'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Saatlik Maliyet (₺ / saat)',
            suffixText: '₺',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () {
              final val = double.tryParse(controller.text.replaceAll(',', '.'));
              if (val != null) {
                settings.setHourlyEnergyCost(val);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }
}

class _CostMetricItem extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _CostMetricItem({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          title,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.6),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
