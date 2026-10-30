import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../utils/haptics_helper.dart';

class ClimateLogPoint {
  final String time;
  final double minutesFromMidnight;
  final double? temperature;
  final double? humidity;

  const ClimateLogPoint({
    required this.time,
    required this.minutesFromMidnight,
    this.temperature,
    this.humidity,
  });
}

enum ClimateMetric { temperature, humidity, both }

class DynamicClimateChartCard extends StatefulWidget {
  final List<DateTime> weekDays;
  final Map<String, List<ClimateLogPoint>> logsByDay;
  final String selectedDayKey;
  final ValueChanged<String> onDaySelected;
  final double? targetTemperature;

  const DynamicClimateChartCard({
    super.key,
    required this.weekDays,
    required this.logsByDay,
    required this.selectedDayKey,
    required this.onDaySelected,
    this.targetTemperature,
  });

  @override
  State<DynamicClimateChartCard> createState() =>
      _DynamicClimateChartCardState();
}

class _DynamicClimateChartCardState extends State<DynamicClimateChartCard> {
  ClimateMetric _metric = ClimateMetric.both;

  String _dayKey(DateTime day) =>
      '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  String _formatMinutes(double minutes) {
    final total = minutes.round().clamp(0, 1439);
    final h = (total ~/ 60).toString().padLeft(2, '0');
    final m = (total % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hapticsEnabled =
        context.select<SettingsProvider, bool>((s) => s.enableHaptics);

    final rawPoints = widget.logsByDay[widget.selectedDayKey] ?? const [];
    final sorted = List<ClimateLogPoint>.from(rawPoints)
      ..sort((a, b) => a.minutesFromMidnight.compareTo(b.minutesFromMidnight));

    final tempPoints =
        sorted.where((p) => p.temperature != null && p.temperature!.isFinite).toList();
    final humPoints =
        sorted.where((p) => p.humidity != null && p.humidity!.isFinite).toList();

    double? minTemp, maxTemp, avgTemp;
    if (tempPoints.isNotEmpty) {
      final temps = tempPoints.map((e) => e.temperature!).toList();
      minTemp = temps.reduce(math.min);
      maxTemp = temps.reduce(math.max);
      avgTemp = temps.reduce((a, b) => a + b) / temps.length;
    }

    double? minHum, maxHum, avgHum;
    if (humPoints.isNotEmpty) {
      final hums = humPoints.map((e) => e.humidity!).toList();
      minHum = hums.reduce(math.min);
      maxHum = hums.reduce(math.max);
      avgHum = hums.reduce((a, b) => a + b) / hums.length;
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.auto_graph_rounded,
                      color: theme.colorScheme.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '24 Saatlik İklim Eğrisi',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                SegmentedButton<ClimateMetric>(
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: ClimateMetric.temperature,
                      label: Text('Isı', style: TextStyle(fontSize: 12)),
                    ),
                    ButtonSegment(
                      value: ClimateMetric.humidity,
                      label: Text('Nem', style: TextStyle(fontSize: 12)),
                    ),
                    ButtonSegment(
                      value: ClimateMetric.both,
                      label: Text('İkisi', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                  selected: {_metric},
                  onSelectionChanged: (sel) {
                    if (sel.isEmpty) return;
                    HapticsHelper.temperatureStep(enabled: hapticsEnabled);
                    setState(() => _metric = sel.first);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Haftanın günleri seçici çubuğu
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: widget.weekDays.map((day) {
                  final key = _dayKey(day);
                  final isSelected = key == widget.selectedDayKey;
                  final hasData = (widget.logsByDay[key]?.isNotEmpty ?? false);
                  final label = DateFormat('EEE d').format(day);
                  return Padding(
                    padding: const EdgeInsets.only(right: 6.0),
                    child: ChoiceChip(
                      label: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      selected: isSelected,
                      showCheckmark: false,
                      avatar: hasData
                          ? Icon(
                              Icons.fiber_manual_record,
                              size: 8,
                              color: isSelected
                                  ? theme.colorScheme.onPrimary
                                  : Colors.deepOrangeAccent,
                            )
                          : null,
                      onSelected: (_) {
                        HapticsHelper.temperatureStep(enabled: hapticsEnabled);
                        widget.onDaySelected(key);
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
            if (tempPoints.isEmpty && humPoints.isEmpty)
              Container(
                height: 180,
                alignment: Alignment.center,
                child: Text(
                  'Seçili gün için 5 dakikalık sensör kaydı bulunamadı.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              )
            else ...[
              // Min / Ort / Maks özet rozetleri
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.spaceEvenly,
                children: [
                  if (_metric != ClimateMetric.humidity && minTemp != null) ...[
                    _StatBadge(
                      label: 'Min Isı',
                      value: '${minTemp.toStringAsFixed(1)}°C',
                      color: Colors.blueAccent,
                    ),
                    _StatBadge(
                      label: 'Ort Isı',
                      value: '${avgTemp!.toStringAsFixed(1)}°C',
                      color: Colors.deepOrange,
                    ),
                    _StatBadge(
                      label: 'Maks Isı',
                      value: '${maxTemp!.toStringAsFixed(1)}°C',
                      color: Colors.redAccent,
                    ),
                  ],
                  if (_metric != ClimateMetric.temperature && minHum != null) ...[
                    _StatBadge(
                      label: 'Ort Nem',
                      value: '%${avgHum!.toStringAsFixed(0)}',
                      color: Colors.teal,
                    ),
                    _StatBadge(
                      label: 'Min/Maks Nem',
                      value:
                          '%${minHum.toStringAsFixed(0)}–${maxHum!.toStringAsFixed(0)}',
                      color: Colors.cyan,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 220,
                child: _buildLineChart(
                  context,
                  isDark: isDark,
                  tempPoints: tempPoints,
                  humPoints: humPoints,
                  minTemp: minTemp,
                  maxTemp: maxTemp,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLineChart(
    BuildContext context, {
    required bool isDark,
    required List<ClimateLogPoint> tempPoints,
    required List<ClimateLogPoint> humPoints,
    required double? minTemp,
    required double? maxTemp,
  }) {
    final theme = Theme.of(context);
    final labelColor = theme.colorScheme.onSurface.withOpacity(0.75);
    final gridColor = theme.colorScheme.onSurface.withOpacity(0.1);

    // Sıcaklık Y ekseni sınırları
    double minY = 15.0;
    double maxY = 28.0;
    if (_metric == ClimateMetric.humidity) {
      minY = 0.0;
      maxY = 100.0;
    } else if (minTemp != null && maxTemp != null) {
      final target = widget.targetTemperature;
      final low = target != null ? math.min(minTemp, target) : minTemp;
      final high = target != null ? math.max(maxTemp, target) : maxTemp;
      minY = (low - 1.5).floorToDouble();
      maxY = (high + 1.5).ceilToDouble();
      if (maxY - minY < 4) {
        minY -= 1;
        maxY += 1;
      }
    }

    // İkisi birden seçiliyse nemi sıcaklık eksenine normalize et (0-100% -> minY..maxY)
    double normalizeHum(double hum) {
      if (_metric == ClimateMetric.humidity) return hum.clamp(0.0, 100.0);
      return minY + (hum.clamp(0.0, 100.0) / 100.0) * (maxY - minY);
    }

    double denormalizeHum(double y) {
      if (_metric == ClimateMetric.humidity) return y;
      if (maxY == minY) return 0;
      return ((y - minY) / (maxY - minY)) * 100.0;
    }

    final List<LineChartBarData> bars = [];

    if (_metric != ClimateMetric.humidity && tempPoints.isNotEmpty) {
      bars.add(
        LineChartBarData(
          spots: tempPoints
              .map((p) => FlSpot(p.minutesFromMidnight, p.temperature!))
              .toList(),
          isCurved: true,
          curveSmoothness: 0.25,
          color: Colors.deepOrangeAccent,
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: tempPoints.length <= 18,
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.deepOrangeAccent.withOpacity(isDark ? 0.35 : 0.28),
                Colors.deepOrangeAccent.withOpacity(0.0),
              ],
            ),
          ),
        ),
      );
    }

    if (_metric != ClimateMetric.temperature && humPoints.isNotEmpty) {
      bars.add(
        LineChartBarData(
          spots: humPoints
              .map((p) =>
                  FlSpot(p.minutesFromMidnight, normalizeHum(p.humidity!)))
              .toList(),
          isCurved: true,
          curveSmoothness: 0.25,
          color: Colors.lightBlueAccent,
          barWidth: 2.2,
          isStrokeCapRound: true,
          dashArray: _metric == ClimateMetric.both ? [6, 4] : null,
          dotData: FlDotData(
            show: humPoints.length <= 18 && _metric == ClimateMetric.humidity,
          ),
          belowBarData: BarAreaData(
            show: _metric == ClimateMetric.humidity,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.lightBlueAccent.withOpacity(isDark ? 0.32 : 0.25),
                Colors.lightBlueAccent.withOpacity(0.0),
              ],
            ),
          ),
        ),
      );
    }

    final yInterval = _metric == ClimateMetric.humidity
        ? 20.0
        : ((maxY - minY) <= 6 ? 1.0 : 2.0);

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: 1440,
        minY: minY,
        maxY: maxY,
        lineBarsData: bars,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          horizontalInterval: yInterval,
          verticalInterval: 240, // 4 saatte bir dikey çizgi
          getDrawingHorizontalLine: (_) =>
              FlLine(color: gridColor, strokeWidth: 1),
          getDrawingVerticalLine: (_) =>
              FlLine(color: gridColor, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            if (_metric != ClimateMetric.humidity &&
                widget.targetTemperature != null &&
                widget.targetTemperature! >= minY &&
                widget.targetTemperature! <= maxY)
              HorizontalLine(
                y: widget.targetTemperature!,
                color: Colors.amber.withOpacity(0.75),
                strokeWidth: 1.5,
                dashArray: [5, 5],
                label: HorizontalLineLabel(
                  show: true,
                  alignment: Alignment.topRight,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.amberAccent : Colors.orange[900],
                  ),
                  labelResolver: (_) =>
                      'Hedef ${widget.targetTemperature!.toStringAsFixed(1)}°C',
                ),
              ),
          ],
        ),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: _metric == ClimateMetric.both,
              reservedSize: 34,
              interval: yInterval,
              getTitlesWidget: (val, meta) {
                final hum = denormalizeHum(val).round();
                if (hum < 0 || hum > 100) return const SizedBox.shrink();
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  space: 4,
                  child: Text(
                    '%$hum',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.lightBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: yInterval,
              getTitlesWidget: (val, meta) {
                if (val == minY || val == maxY) {
                  return const SizedBox.shrink();
                }
                final unit = _metric == ClimateMetric.humidity ? '%' : '°';
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  space: 4,
                  child: Text(
                    '${val.toStringAsFixed(val % 1 == 0 ? 0 : 1)}$unit',
                    style: TextStyle(
                      fontSize: 10,
                      color: labelColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: 240, // 00:00, 04:00, 08:00, 12:00, 16:00, 20:00, 24:00
              getTitlesWidget: (val, meta) {
                final mins = val.round();
                if (mins < 0 || mins > 1440 || mins % 240 != 0) {
                  return const SizedBox.shrink();
                }
                final label = mins == 1440
                    ? '24:00'
                    : '${(mins ~/ 60).toString().padLeft(2, '0')}:00';
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  space: 6,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      color: labelColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchCallback: (event, response) {
            if (event is FlTapDownEvent || event is FlPanStartEvent) {
              HapticsHelper.temperatureStep(
                enabled: context.read<SettingsProvider>().enableHaptics,
              );
            }
          },
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final timeLabel = _formatMinutes(spot.x);
                final isTempBar = _metric == ClimateMetric.temperature ||
                    (_metric == ClimateMetric.both && spot.barIndex == 0);
                if (isTempBar) {
                  return LineTooltipItem(
                    '$timeLabel\n🌡️ ${spot.y.toStringAsFixed(1)}°C',
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  );
                } else {
                  final humVal = denormalizeHum(spot.y);
                  return LineTooltipItem(
                    '$timeLabel\n💧 %${humVal.toStringAsFixed(0)} Nem',
                    const TextStyle(
                      color: Colors.lightBlueAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  );
                }
              }).toList();
            },
          ),
        ),
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatBadge({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
