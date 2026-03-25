import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import '../providers/settings_provider.dart';
import '../providers/auth_provider.dart';
import '../services/geofence_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static void _showLocationPicker(
      BuildContext context, SettingsProvider settings) async {
    // Check location permissions
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission denied')),
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Location permissions are permanently denied, we cannot request permissions.'),
        ),
      );
      return;
    }

    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('Getting current location...'),
              ],
            ),
          );
        },
      );

      // Get current location
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Close loading dialog
      Navigator.of(context).pop();

      // Update settings with new location
      await settings.setHomeLocation(position.latitude, position.longitude);

      // Show success message
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Home location updated to: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      // Close loading dialog if it's still open
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to get location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              ListTile(
                title: const Text('Dark Mode'),
                trailing: Switch(
                  value: settings.theme == 'dark',
                  onChanged: (isOn) {
                    settings.toggleTheme();
                  },
                ),
              ),
              const Divider(),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  'Geofence Settings',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ListTile(
                title: const Text('GPS Geofence'),
                subtitle: Text(settings.geofenceEnabled ? 'Aktif — konum takibi açık' : 'Kapalı'),
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
                    final dist = geo.lastDistance;
                    final distText = dist >= 1000
                        ? '${(dist / 1000).toStringAsFixed(1)} km'
                        : '${dist.toStringAsFixed(0)} m';
                    final statusIcon = geo.isInsideGeofence ? '🏠' : '🚶';
                    final statusText = geo.isInsideGeofence ? 'Evdesiniz' : 'Dışarıdasınız';
                    return ListTile(
                      leading: Text(statusIcon, style: const TextStyle(fontSize: 24)),
                      title: Text('$statusText — $distText'),
                      subtitle: const Text('Eve olan mesafe (3 dk güncellenir)'),
                    );
                  },
                ),
              ListTile(
                title: const Text('Home Location'),
                subtitle: Text(
                  '${settings.homeLatitude.toStringAsFixed(6)}, ${settings.homeLongitude.toStringAsFixed(6)}',
                ),
                trailing: ElevatedButton(
                  onPressed: () => _showLocationPicker(context, settings),
                  child: const Text('Set GPS'),
                ),
              ),
              ListTile(
                title: const Text('Home Radius'),
                subtitle: Text('${settings.homeRadiusMeters.round()} meters'),
                trailing: SizedBox(
                  width: 200,
                  child: Slider(
                    value: settings.homeRadiusMeters,
                    min: 50.0,
                    max: 1000.0,
                    divisions: 19,
                    label: '${settings.homeRadiusMeters.round()}m',
                    onChanged: (value) {
                      settings.setHomeRadius(value);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  'The geofence will automatically update when you change these settings.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 32),
              const Divider(),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  'Hesap',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
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
                                      'Çıkış yapmak istediğinize emin misiniz?'),
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
