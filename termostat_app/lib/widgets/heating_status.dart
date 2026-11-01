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

                final List> logList = [];
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
                                  'Sebep: ${lastReset['reason'] ?? 'Bilinmiyor'} (Kod:${lastReset['reasonCode'] ?? '-'})'),
                              Text(
                                  'Açılış RAM (Free/Min): ${lastReset['freeHeapAtBoot'] ?? '-'} /${lastReset['minFreeHeap'] ?? '-'} byte'),
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
                      child: Row