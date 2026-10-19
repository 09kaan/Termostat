import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'providers/thermostat_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/schedule_provider.dart';
import 'providers/weather_provider.dart';
import 'providers/auth_provider.dart';
import 'screens/settings_screen.dart';
import 'services/notifications_service.dart';
import 'services/widget_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await WidgetService.configureSharedAuthentication();

  // Initialize notifications service
  await notificationsService.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ThermostatProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => ScheduleProvider()),
        ChangeNotifierProvider(create: (_) => WeatherProvider()),
      ],
      child: Consumer2<SettingsProvider, AuthProvider>(
        builder: (context, settings, auth, _) {
          return MaterialApp(
            title: 'Smart Thermostat',
            debugShowCheckedModeBanner: false,
            theme:
                AppTheme.forAppearance(settings.appearance, Brightness.light),
            darkTheme:
                AppTheme.forAppearance(settings.appearance, Brightness.dark),
            themeMode:
                settings.theme == 'dark' ? ThemeMode.dark : ThemeMode.light,
            home: auth.isLoggedIn ? const HomeScreen() : const LoginScreen(),
            routes: {
              '/settings': (context) => const SettingsScreen(),
            },
          );
        },
      ),
    );
  }
}
