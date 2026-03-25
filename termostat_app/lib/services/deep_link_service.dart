import 'dart:async';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:provider/provider.dart';
import '../providers/thermostat_provider.dart';
import '../constants/app_constants.dart';
import 'notifications_service.dart';

/// Handles deep links from Siri Shortcuts, NFC tags, widgets etc.
/// 
/// Supported commands:
/// - termostat://heating-on     → Turn on heating
/// - termostat://heating-off    → Turn off heating  
/// - termostat://set-temp?value=25 → Set target temperature
/// - termostat://eco-mode       → Set eco mode (away temp + off)
class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._internal();
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();

  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  ThermostatProvider? _thermostatProvider;
  bool _isInitialized = false;

  /// Initialize deep link listener
  Future<void> initialize(BuildContext context) async {
    if (_isInitialized) return;

    _appLinks = AppLinks();

    if (context.mounted) {
      _thermostatProvider = Provider.of<ThermostatProvider>(context, listen: false);
    }

    // Handle link that opened the app (cold start)
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        debugPrint('🔗 Initial deep link: $initialUri');
        _handleDeepLink(initialUri);
      }
    } catch (e) {
      debugPrint('Error getting initial link: $e');
    }

    // Handle links while app is running (warm start)
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (Uri uri) {
        debugPrint('🔗 Deep link received: $uri');
        _handleDeepLink(uri);
      },
      onError: (err) {
        debugPrint('Deep link error: $err');
      },
    );

    _isInitialized = true;
    debugPrint('DeepLinkService initialized');
  }

  /// Process incoming deep link
  void _handleDeepLink(Uri uri) {
    // URI format: termostat://command or termostat://command?param=value
    final command = uri.host.isNotEmpty ? uri.host : uri.path.replaceAll('/', '');
    
    debugPrint('🎯 Deep link command: $command');

    switch (command) {
      case 'heating-on':
        _heatingOn();
        break;
      case 'heating-off':
        _heatingOff();
        break;
      case 'set-temp':
        final valueStr = uri.queryParameters['value'];
        if (valueStr != null) {
          final temp = double.tryParse(valueStr);
          if (temp != null) {
            _setTemperature(temp);
          }
        }
        break;
      case 'eco-mode':
        _ecoMode();
        break;
      default:
        debugPrint('Unknown deep link command: $command');
    }
  }

  /// Turn on heating
  void _heatingOn() {
    if (_thermostatProvider?.thermostat != null) {
      _thermostatProvider!.updateMode('on');
      _thermostatProvider!.updateTemperature(AppConstants.homeTemperature);
      notificationsService.showNotification(
        id: 10,
        title: 'Termostat',
        body: 'Siri: Isıtma açıldı (${AppConstants.homeTemperature.toInt()}°C)',
      );
      debugPrint('✅ Siri: Heating ON');
    }
  }

  /// Turn off heating
  void _heatingOff() {
    if (_thermostatProvider?.thermostat != null) {
      _thermostatProvider!.updateMode('off');
      notificationsService.showNotification(
        id: 10,
        title: 'Termostat',
        body: 'Siri: Isıtma kapatıldı',
      );
      debugPrint('✅ Siri: Heating OFF');
    }
  }

  /// Set specific temperature
  void _setTemperature(double temp) {
    if (_thermostatProvider?.thermostat != null) {
      final clampedTemp = temp.clamp(
        AppConstants.minTemperature,
        AppConstants.maxTemperature,
      );
      _thermostatProvider!.updateTemperature(clampedTemp);
      _thermostatProvider!.updateMode('on');
      notificationsService.showNotification(
        id: 10,
        title: 'Termostat',
        body: 'Siri: Sıcaklık ${clampedTemp.toInt()}°C olarak ayarlandı',
      );
      debugPrint('✅ Siri: Temperature set to $clampedTemp°C');
    }
  }

  /// Activate eco mode
  void _ecoMode() {
    if (_thermostatProvider?.thermostat != null) {
      _thermostatProvider!.updateTemperature(AppConstants.awayTemperature);
      _thermostatProvider!.updateMode('off');
      notificationsService.showNotification(
        id: 10,
        title: 'Termostat',
        body: 'Siri: Eko mod aktif (${AppConstants.awayTemperature.toInt()}°C)',
      );
      debugPrint('✅ Siri: Eco mode activated');
    }
  }

  /// Dispose
  void dispose() {
    _linkSubscription?.cancel();
    _linkSubscription = null;
    _isInitialized = false;
  }
}
