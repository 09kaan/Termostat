import 'package:flutter/material.dart';
import '../services/offline_lan_service.dart';

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final lanService = OfflineLanService();
    return ListenableBuilder(
      listenable: lanService,
      builder: (context, _) {
        if (!lanService.isOfflineMode) return const SizedBox.shrink();

        final reachable = lanService.isLanReachable;
        return Container(
          width: double.infinity,
          color: reachable ? Colors.teal[700] : Colors.amber[800],
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                reachable ? Icons.router_rounded : Icons.wifi_off_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  reachable
                      ? 'Bulut Yok · Yerel Ağdan (ESP32) Bağlı (${lanService.espLocalIp})'
                      : 'İnternet Yok · Yerel Ağ (LAN) Modu Aktif',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(50, 28),
                ),
                onPressed: () => _showIpConfigDialog(context),
                child: const Text(
                  'IP Ayarla',
                  style: TextStyle(decoration: TextDecoration.underline),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static void showIpConfigDialog(BuildContext context) =>
      _showIpConfigDialog(context);

  static void _showIpConfigDialog(BuildContext context) {
    final lanService = OfflineLanService();
    final controller = TextEditingController(
      text: lanService.espLocalIp ?? '192.168.1.',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ESP32 Yerel IP Adresi'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Cihaz IP (Örn: 192.168.1.50)',
            hintText: '192.168.1.50',
          ),
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(
            onPressed: () {
              lanService.setOfflineMode(false);
              Navigator.pop(ctx);
            },
            child: const Text('Bulut Moduna Dön'),
          ),
          FilledButton(
            onPressed: () async {
              final ip = controller.text.trim();
              Navigator.pop(ctx);
              final success = await lanService.checkLocalConnection(ip);
              if (success) {
                lanService.setOfflineMode(true, ip: ip);
              }
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? 'ESP32 yerel bağlantısı başarılı ($ip)!'
                          : 'ESP32 ($ip) yerel ağda yanıt vermedi, IP kaydedildi.',
                    ),
                    backgroundColor: success ? Colors.green : Colors.orange,
                  ),
                );
              }
            },
            child: const Text('Kaydet & Test Et'),
          ),
        ],
      ),
    );
  }
}
