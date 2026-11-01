import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/heating_feedback.dart';

class HeatingStatus extends StatefulWidget {
  const HeatingStatus({super.key, required this.feedback});
  final HeatingFeedback feedback;
  @override
  State<HeatingStatus> createState() => _HeatingStatusState();
}

class _HeatingStatusState extends State<HeatingStatus> {
  late final ValueNotifier<HeatingFeedback> _feedback =
      ValueNotifier(widget.feedback);
  bool _sheetOpen = false;
  HeatingFeedback get feedback => widget.feedback;

  @override
  void didUpdateWidget(covariant HeatingStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_sheetOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _feedback.value = widget.feedback;
      });
    } else {
      _feedback.value = widget.feedback;
    }
  }

  @override
  void dispose() {
    if (!_sheetOpen) _feedback.dispose();
    super.dispose();
  }

  Future<void> _showEsp32ResetLogsDialog(BuildContext parentContext) async {
    final db = FirebaseDatabase.instance.ref('devices/device1');
    showModalBottomSheet<void>(
      context: parentContext,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return FutureBuilder<List<DataSnapshot>>(
              future: Future.wait([
                db.child('lastReset').get(),
                db.child('resetLogs').limitToLast(30).get(),
              ]),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text('Reset kayıtları alınamadı: ${snapshot.error}'),
                    ),
                  );
                }

                final lastResetSnap = snapshot.data?[0];
                final logsSnap = snapshot.data?[1];

                Map<String, dynamic>? lastReset;
                if (lastResetSnap != null &&
                    lastResetSnap.exists &&
                    lastResetSnap.value is Map) {
                  lastReset =
                      Map<String, dynamic>.from(lastResetSnap.value as Map);
                }

                final List<Map<String, dynamic>> logList = [];
                if (logsSnap != null &&
                    logsSnap.exists &&
                    logsSnap.value is Map) {
                  final rawMap = logsSnap.value as Map;
                  for (final entry in rawMap.entries) {
                    if (entry.value is Map) {
                      final item =
                          Map<String, dynamic>.from(entry.value as Map);
                      item['_key'] = entry.key.toString();
                      logList.add(item);
                    }
                  }
                  logList.sort((a, b) {
                    final ea = (a['epoch'] as num?)?.toInt() ?? 0;
                    final eb = (b['epoch'] as num?)?.toInt() ?? 0;
                    return eb.compareTo(ea);
                  });
                }

                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'ESP32 Reset & Tanılama Kayıtları',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (logList.isNotEmpty)
                          TextButton.icon(
                            onPressed: () async {
                              await db.child('resetLogs').remove();
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                            icon: const Icon(Icons.delete_sweep_outlined,
                                size: 18, color: Colors.red),
                            label: const Text('Temizle',
                                style: TextStyle(color: Colors.red)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (lastReset != null)
                      Card(
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.memory,
                                      size: 18, color: Colors.deepOrange),
                                  SizedBox(width: 6),
                                  Text(
                                    'Son Başlangıç (Boot) Durumu',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text('Tarih/Saat: ${lastReset['time'] ?? '-'}'),
                              Text(
                                  'Sebep: ${lastReset['reason'] ?? 'Bilinmiyor'} (Kod: ${lastReset['reasonCode'] ?? '-'})'),
                              Text(
                                  'Açılış RAM (Free/Min): ${lastReset['freeHeapAtBoot'] ?? '-'} / ${lastReset['minFreeHeap'] ?? '-'} byte'),
                              Text(
                                  'Kurtarma Sayacı: ${lastReset['recoveryUsed'] ?? 0}/8'),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      'Geçmiş Reset Kayıtları (${logList.length})',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    if (logList.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24.0),
                        child: Center(
                          child: Text(
                            'Henüz kaydedilmiş ESP32 reset kaydı yok.\nYeni ESP32 yazılımını yükledikten sonra tüm yeniden başlamalar burada listelenir.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    else
                      ...logList.map((item) {
                        final reason = item['reason']?.toString() ?? 'Bilinmiyor';
                        final isPanic = reason.contains('Panic') ||
                            reason.contains('Watchdog');
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            dense: true,
                            leading: Icon(
                              isPanic
                                  ? Icons.warning_amber_rounded
                                  : Icons.restart_alt_rounded,
                              color: isPanic ? Colors.red : Colors.orange,
                            ),
                            title: Text(
                              reason,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              '${item['time'] ?? '-'}\nMin RAM: ${item['minFreeHeap'] ?? '-'} B · Kurtarma: ${item['recoveryUsed'] ?? 0}/8',
                            ),
                            isThreeLine: true,
                          ),
                        );
                      }),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _showDetails() async {
    if (_sheetOpen) return;
    _sheetOpen = true;
    try {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (sheet) => ValueListenableBuilder<HeatingFeedback>(
          valueListenable: _feedback,
          builder: (context, current, _) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Isıtma bağlantısı',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _showEsp32ResetLogsDialog(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 6.0, horizontal: 4.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'ESP32 · ${_label(current.esp32)}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primaryContainer,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'Reset Logları',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onPrimaryContainer,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                _reportTime(
                                    context,
                                    current.controllerLastSeenAt,
                                    current.evaluatedAt,
                                    'controller-report-time'),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, size: 22),
                        ],
                      ),
                    ),
                  ),
                  if (current.esp32 != LinkState.online)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        current.recovery?.describe(
                              phoneConnected: current.phoneConnected,
                              now: current.evaluatedAt,
                            ) ??
                            'Reset planı bilgisi yok. Bu bilgi için güncel ESP32 kurtarma yazılımından yeni rapor gerekli.',
                        key: const ValueKey('controller-recovery-plan'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text('ESP8266 · ${_label(current.esp8266)}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  _reportTime(context, current.relayLastSeenAt,
                      current.evaluatedAt, 'relay-report-time'),
                  const SizedBox(height: 16),
                  Text(current.detail),
                  const SizedBox(height: 12),
                  const Text(
                      'Zamanlar cihazdan gelen son bildirime aittir; ekranı açmak bu zamanı yenilemez.'),
                  const SizedBox(height: 8),
                  const Text(
                      'Gösterge ESP8266 röle çıkışının yazılımsal raporudur; kombinin gerçek alevini veya mekanik kontak durumunu ölçmez.'),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (_) {
      // Ignored
    } finally {
      _sheetOpen = false;
      if (!mounted) _feedback.dispose();
    }
  }

  Widget _reportTime(
      BuildContext context, int? timestamp, int? now, String key) {
    String text;
    if (timestamp == null) {
      text = 'Son bildirim: henüz geçerli kayıt yok';
    } else {
      final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final clock = DateFormat('dd.MM.yyyy HH:mm:ss').format(date);
      var age = '';
      if (now != null) {
        final seconds = ((now - timestamp) ~/ 1000).clamp(0, 2147483647);
        age = seconds < 60
            ? '$seconds sn önce'
            : seconds < 3600
                ? '${seconds ~/ 60} dk önce'
                : seconds < 86400
                    ? '${seconds ~/ 3600} sa önce'
                    : '${seconds ~/ 86400} gün önce';
      }
      text = 'Son bildirim: $clock${age.isEmpty ? '' : ' · $age'}';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(text,
          key: ValueKey(key), style: Theme.of(context).textTheme.bodySmall),
    );
  }

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
          onTap: _showDetails,
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
