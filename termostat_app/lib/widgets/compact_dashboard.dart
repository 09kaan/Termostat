import '../models/heating_feedback.dart';
import 'heating_status.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Only the lower cards change. The original temperature/target widget is reused.
class CompactDashboard extends StatelessWidget {
  const CompactDashboard({
    super.key,
    required this.summary,
    required this.mode,
    required this.onModeChanged,
    required this.waking,
    required this.onWake,
    required this.weather,
    this.feedback = const HeatingFeedback(),
  });
  final HeatingFeedback feedback;
  final Widget summary, weather;
  final String mode;
  final ValueChanged<String> onModeChanged;
  final bool waking;
  final VoidCallback onWake;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          final warm = AppAppearance.isWarm(context);
          final fallback = box.maxWidth < 360 ||
              box.maxHeight < (warm ? 660 : 590) ||
              MediaQuery.textScalerOf(context).scale(1) > 1.15;
          final cards = <Widget>[
            summary,
            CompactModeCard(
                mode: mode, onChanged: onModeChanged, feedback: feedback),
            CompactPcCard(waking: waking, onWake: onWake),
            weather,
          ];
          final content = Column(
            key: const ValueKey('dashboard-cards'),
            mainAxisSize: fallback ? MainAxisSize.min : MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i != 0) const SizedBox(height: 8),
                cards[i],
              ],
            ],
          );
          const padding = EdgeInsets.fromLTRB(16, 4, 16, 12);
          // Very small/landscape/large-text screens retain reachable controls instead
          // of clipping content, shrinking text or disabling scrolling blindly.
          return fallback
              ? SingleChildScrollView(
                  key: const ValueKey('dashboard-accessible-scroll'),
                  padding: padding,
                  child: content,
                )
              : Padding(padding: padding, child: content);
        },
      );
}

class CompactModeCard extends StatelessWidget {
  const CompactModeCard({
    super.key,
    required this.mode,
    required this.onChanged,
    this.feedback = const HeatingFeedback(),
  });
  final String mode;
  final HeatingFeedback feedback;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final onAccent =
        colors.primary.computeLuminance() > .179 ? Colors.black : Colors.white;
    const modes = {'on': 'Açık', 'off': 'Kapalı', 'manual': 'Manuel'};
    return Card(
      key: const ValueKey('compact-mode-card'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const ExcludeSemantics(
                        child: Text('⚙️', style: TextStyle(fontSize: 16))),
                    const SizedBox(width: 6),
                    Text('Sistem modu',
                        style: Theme.of(context).textTheme.titleMedium),
                  ]),
                  HeatingStatus(feedback: feedback),
                ]),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, box) {
                Widget button(MapEntry<String, String> entry) => Semantics(
                      selected: mode == entry.key,
                      child: OutlinedButton(
                        key: ValueKey('compact-mode-${entry.key}'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(44, 48),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 12,
                          ),
                          foregroundColor:
                              mode == entry.key ? onAccent : colors.primary,
                          backgroundColor:
                              mode == entry.key ? colors.primary : null,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () => onChanged(entry.key),
                        child: Text(entry.value),
                      ),
                    );
                if (MediaQuery.textScalerOf(context).scale(1) > 1.3) {
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: modes.entries.map(button).toList(),
                  );
                }
                return Row(
                  children: [
                    for (final entry in modes.entries) ...[
                      if (entry.key != 'on') const SizedBox(width: 8),
                      Expanded(child: button(entry)),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class CompactPcCard extends StatelessWidget {
  const CompactPcCard({super.key, required this.waking, required this.onWake});
  final bool waking;
  final VoidCallback onWake;
  @override
  Widget build(BuildContext context) => Card(
        key: const ValueKey('compact-pc-card'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.computer,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Bilgisayar',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: waking ? null : onWake,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(44, 48),
                  foregroundColor:
                      Theme.of(context).colorScheme.primary.computeLuminance() >
                              .179
                          ? Colors.black
                          : Colors.white,
                ),
                child: waking
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text("PC'yi Aç"),
              ),
            ],
          ),
        ),
      );
}
