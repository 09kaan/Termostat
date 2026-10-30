import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';

import '../providers/settings_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/weather_provider.dart';
import '../services/geofence_service.dart';
import '../services/offline_lan_service.dart';
import '../widgets/geofence_exit_options.dart';
import '../widgets/appearance_selector.dart';
import '../widgets/offline_banner.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static void _showLocationPicker(
    BuildContext context,
    SettingsProvider settings,
  ) async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Konum izni reddedildi')),
          );
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Konum izni kalıcı olarak kapalı. iOS Ayarlar menüsünden izin verin.',
            ),
          ),
        );
      }
      return;
    }

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('Mevcut konum alınıyor...'),
              ],
            ),
          );
        },
      );

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (context.mounted) Navigator.of(context).pop();

      await settings.setHomeLocation(position.latitude, position.longitude);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ev konumu güncellendi: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Konum alınamadı: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  static void _showEnergyCostDialog(
    BuildContext context,
    SettingsProvider settings,
  ) {
    final controller = TextEditingController(
      text: settings.hourlyEnergyCost.toStringAsFixed(2),
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Saatlik Enerji Maliyeti'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Saatlik Kombi Tüketim Ücreti (₺ / saat)',
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
              if (val != null && val >= 0) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          final outdoorTemp = context.watch<WeatherProvider>().outdoorCelsius;
          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              AppearanceSelector(
                value: settings.appearance,
                onChanged: settings.setAppearance,
              ),
              const SizedBox(height: 16),
              ListTile(
                title: const Text('Koyu mod'),
                trailing: Switch(
                  value: settings.theme == 'dark',
                  onChanged: (_) => settings.toggleTheme(),
                ),
              ),
              SwitchListTile.adaptive(
                secondary: const Icon(
                  Icons.gradient_rounded,
                  color: Colors.deepOrangeAccent,
                ),
                title: const Text('Görsel durum geçişleri'),
                subtitle: const Text(
                  'Isıtma ve bekleme durumuna göre arka plan rengini yumuşakça değiştirir.',
                ),
                value: settings.enableDynamicBackground,
                onChanged: (val) => settings.setDynamicBackground(val),
              ),
              SwitchListTile.adaptive(
                secondary: const Icon(
                  Icons.vibration_rounded,
                  color: Colors.teal,
                ),
                title: const Text('Haptik geri bildirim'),
                subtitle: const Text(
                  'Sıcaklık ve mod değişimlerinde dokunsal titreşim hissi verir.',
                ),
                value: settings.enableHaptics,
                onChanged: (val) => settings.setEnableHaptics(val),
              ),
              ListTile(
                leading: const Icon(Icons.bolt_rounded, color: Colors.amber),
                title: const Text('Birim enerji maliyeti'),
                subtitle: Text(
                  '₺${settings.hourlyEnergyCost.toStringAsFixed(2)} / saat (Analiz ekranı için)',
                ),
                trailing: TextButton(
                  onPressed: () => _showEnergyCostDialog(context, settings),
                  child: const Text('Düzenle'),
                ),
              ),
              const Divider(),

              // YENİ: Hava Durumu Destekli Akıllı Kontroller Bölümü
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Hava Durumu Asistanı',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    if (outdoorTemp != null)
                      Chip(
                        avatar: const Icon(Icons.thermostat_outlined, size: 16),
                        label: Text('Dış: ${outdoorTemp.toStringAsFixed(1)}°C'),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
              SwitchListTile.adaptive(
                secondary: const Icon(
                  Icons.ac_unit_rounded,
                  color: Colors.lightBlue,
                ),
                title: const Text('Soğuk hava erken başlatma (Optimum Start)'),
                subtitle: const Text(
                  'Dış sıcaklık 5°C altındayken zamanlayıcıları 25 dk erken başlatarak evi tam vaktinde ısıtır.',
                ),
                value: settings.optimumStartEnabled,
                onChanged: (val) => settings.setOptimumStartEnabled(val),
              ),
              SwitchListTile.adaptive(
                secondary: const Icon(
                  Icons.shield_outlined,
                  color: Colors.indigo,
                ),
                title: const Text('Don koruması (Kritik düşük sıcaklık)'),
                subtitle: Text(
                  'Ev içi sıcaklık ${settings.frostProtectionTemp.toStringAsFixed(0)}°C altına düşerse kombiyi koruma amaçlı çalıştırır.',
                ),
                value: settings.frostProtectionEnabled,
                onChanged: (val) => settings.setFrostProtectionEnabled(val),
              ),
              SwitchListTile.adaptive(
                secondary: const Icon(
                  Icons.wb_sunny_outlined,
                  color: Colors.orange,
                ),
                title: const Text('Sıcak hava tasarruf kilidi'),
                subtitle: const Text(
                  'Dış hava sıcaklığı 20°C ve üzerindeyken gereksiz kombi çalışmasını engeller.',
                ),
                value: settings.warmWeatherAutoOff,
                onChanged: (val) => settings.setWarmWeatherAutoOff(val),
              ),
              const Divider(),

              // YENİ: Çevrimdışı Yerel Ağ (ESP32 LAN) Bölümü
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  'Yerel Ağ (Çevrimdışı Kontrol)',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ListenableBuilder(
                listenable: OfflineLanService(),
                builder: (context, _) {
                  final lan = OfflineLanService();
                  final ip = lan.espLocalIp;
                  final status = ip == null
                      ? 'Henüz ESP32 IP adresi tanımlanmadı'
                      : lan.isLanReachable
                          ? 'ESP32 yerel ağda aktif ($ip) · Ev Wi-Fi kilidi açık'
                          : 'Kayıtlı IP: $ip (Şu an bulut üzerinden bağlı)';
                  return ListTile(
                    leading: Icon(
                      lan.isLanReachable
                          ? Icons.router_rounded
                          : Icons.settings_ethernet_rounded,
                      color: lan.isLanReachable ? Colors.teal : null,
                    ),
                    title: const Text('ESP32 Yerel IP Adresi'),
                    subtitle: Text(status),
                    trailing: OutlinedButton(
                      onPressed: () =>
                          OfflineBanner.showIpConfigDialog(context),
                      child: const Text('IP Ayarla'),
                    ),
                  );
                },
              ),
              const Divider(),

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  'Konum ayarları',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                title: const Text('Konum otomasyonu'),
                subtitle: Text(
                  settings.geofenceEnabled
                      ? 'Açık — iOS izleme durumu aşağıda'
                      : 'Kapalı',
                ),
                trailing: Switch(
                  value: settings.geofenceEnabled,
                  onChanged: (isOn) {
                    settings.setGeofenceEnabled(isOn);
                  },
                ),
              ),
              if (settings.geofenceEnabled)
                ListenableBuilder(
                  listenable: ThermostatGeofenceService(),
                  builder: (context, _) {
                    final geo = ThermostatGeofenceService();
                    final diagnostic = geo.diagnostics;
                    final dist = geo.lastDistance;
                    final distText = dist == null
                        ? 'Güncel mesafe yok'
                        : dist >= 1000
                            ? '${(dist / 1000).toStringAsFixed(1)} km'
                            : '${dist.toStringAsFixed(0)} m';
                    final inside = diagnostic?.inside;
                    final statusText = inside == null
                        ? 'Bölge durumu bekleniyor'
                        : inside
                            ? 'Son bölge durumu: Evde'
                            : 'Son bölge durumu: Dışarıda';
                    String timeText(DateTime time) =>
                        '${time.day.toString().padLeft(2, '0')}.${time.month.toString().padLeft(2, '0')} '
                        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                    final details = <String>[
                      diagnostic?.status ?? 'iOS izleme bilgisi alınamadı',
                      '$statusText — $distText',
                      if (geo.isLanHomeLocked)
                        'Ev Wi-Fi / LAN Kilidi: Aktif (Sahte çıkış korumalı)',
                      if (dist != null && diagnostic?.accuracy != null)
                        'Konum doğruluğu: ±${diagnostic!.accuracy!.round()} m',
                      if (diagnostic?.sampledAt != null)
                        'Son konum örneği: ${timeText(diagnostic!.sampledAt!)}',
                      if (diagnostic?.lastEventAt != null)
                        'Son olay: ${diagnostic!.lastEvent ?? 'Bölge geçişi'} · ${timeText(diagnostic.lastEventAt!)}',
                      if (geo.lastAutomationMessage != null)
                        geo.lastAutomationMessage!,
                      if (diagnostic?.lastResultAt != null)
                        'Son sonuç: ${timeText(diagnostic!.lastResultAt!)}',
                    ];
                    return ListTile(
                      leading: Icon(
                        diagnostic?.monitoring == true
                            ? Icons.location_on_outlined
                            : Icons.location_off_outlined,
                      ),
                      title: const Text('Konum izleme durumu'),
                      subtitle: Text(details.join('\n')),
                      trailing: IconButton(
                        tooltip: 'Konum izleme bilgisini yenile',
                        icon: const Icon(Icons.refresh),
                        onPressed: () => geo.refreshDiagnostics(),
                      ),
                    );
                  },
                ),
              const GeofenceExitOptions(),
              ListTile(
                title: const Text('Ev konumu'),
                subtitle: Text(
                  '${settings.homeLatitude.toStringAsFixed(6)}, ${settings.homeLongitude.toStringAsFixed(6)}',
                ),
                trailing: ElevatedButton(
                  onPressed: () => _showLocationPicker(context, settings),
                  child: const Text('Konumu seç'),
                ),
              ),
              const SizedBox(height: 32),
              const Divider(),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  'Hesap',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Consumer<AuthProvider>(
                builder: (context, auth, _) {
                  return Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: const Text('Giriş Yapan'),
                        subtitle: Text(auth.currentUser?.email ?? 'Bilinmiyor'),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Çıkış Yap'),
                                  content: const Text(
                                    'Çıkış yapmak istediğinize emin misiniz?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('İptal'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('Çıkış Yap'),
                                    ),
                                  ],
                                ),
                              );

                              if (confirmed == true && context.mounted) {
                                await auth.signOut();
                                if (context.mounted) {
                                  Navigator.of(context)
                                      .popUntil((route) => route.isFirst);
                                }
                              }
                            },
                            icon: const Icon(Icons.logout),
                            label: const Text('Çıkış Yap'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}
