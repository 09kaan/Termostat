import 'package:flutter/material.dart';
import '../models/heating_feedback.dart';

class HeatingStatus extends StatelessWidget {
  const HeatingStatus({super.key, required this.feedback});
  final HeatingFeedback feedback;
  Color _linkColor(LinkState state, bool dark) => switch (state) {
        LinkState.online =>
          dark ? const Color(0xff72bc8f) : const Color(0xff237948),
        LinkState.offline =>
          dark ? const Color(0xffe97366) : const Color(0xffbb3434),
        LinkState.unknown =>
          dark ? const Color(0xffbdbdbd) : const Color(0xff737373),
      };
  String _label(LinkState state) => switch (state) {
        LinkState.online => 'Yanıt veriyor',
        LinkState.offline => 'Yanıt yok',
        LinkState.unknown => 'Doğrulanamıyor',
      };
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final active = feedback.relay == RelayState.on;
    final off = feedback.relay == RelayState.off;
    final pending = feedback.relay == RelayState.pending;
    final color = active
        ? (dark ? const Color(0xfff4ac77) : const Color(0xffa43e00))
        : off
            ? (dark ? const Color(0xffbdbdbd) : const Color(0xff676767))
            : Theme.of(context).colorScheme.onSurface;
    final text = active
        ? 'Röle açık'
        : off
            ? 'Röle kapalı'
            : pending
                ? 'Bekleniyor'
                : 'Doğrulanamıyor';
    return Semantics(
        label: '$text. ${feedback.detail}',
        button: true,
        child: InkWell(
          key: const ValueKey('heating-status'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              useSafeArea: true,
              builder: (sheet) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  child: SingleChildScrollView(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text('Isıtma bağlantısı',
                            style: Theme.of(sheet).textTheme.titleLarge),
                        const SizedBox(height: 16),
                        Text('ESP32 · ${_label(feedback.esp32)}'),
                        const SizedBox(height: 8),
                        Text('ESP8266 · ${_label(feedback.esp8266)}'),
                        const SizedBox(height: 16),
                        Text(feedback.detail),
                        const SizedBox(height: 12),
                        const Text(
                            'Gösterge ESP8266 röle çıkışının yazılımsal raporudur; kombinin gerçek alevini veya mekanik kontak durumunu ölçmez.'),
                      ])))),
          child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                        active || off
                            ? Icons.local_fire_department
                            : pending
                                ? Icons.hourglass_top
                                : Icons.help_outline,
                        key: ValueKey('relay-${feedback.relay.name}'),
                        size: 20,
                        color: color),
                    const SizedBox(width: 4),
                    Flexible(
                        child: Text(text,
                            style: TextStyle(fontSize: 14, color: color))),
                    const SizedBox(width: 8),
                    Icon(Icons.circle,
                        size: 9, color: _linkColor(feedback.link, dark)),
                  ]))),
        ));
  }
}
