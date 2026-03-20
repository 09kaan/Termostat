import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/schedule_list_screen.dart';
import 'widgets/default_page_controller.dart';
import 'providers/thermostat_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/schedule_provider.dart';
import 'providers/weather_provider.dart';
import 'screens/settings_screen.dart';
import 'services/notifications_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
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
        ChangeNotifierProvider(create: (_) => ThermostatProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => ScheduleProvider()),
        ChangeNotifierProvider(create: (_) => WeatherProvider()),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
    return MaterialApp(
            title: 'Smart Thermostat',
      theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.blue,
                brightness: Brightness.light,
              ),
              textTheme: GoogleFonts.interTextTheme(
                Theme.of(context).textTheme,
              ),
            ),
            darkTheme: ThemeData(
               useMaterial3: true,
               colorScheme: ColorScheme.fromSeed(
                 seedColor: Colors.blue,
                 brightness: Brightness.dark,
                 surface: const Color(0xFF1E1E1E),
                 onSurface: Colors.white,
                 background: const Color(0xFF121212),
                 onBackground: Colors.white,
                 primary: Colors.lightBlueAccent[400],
                 onPrimary: Colors.white,
                 secondary: Colors.cyanAccent[200],
                 onSecondary: Colors.white,
                 error: Colors.redAccent,
                 onError: Colors.white,
                 outline: Colors.grey[700],
               ),
              textTheme: GoogleFonts.interTextTheme(
                Theme.of(context).textTheme,
              ).apply(
                 bodyColor: Colors.white,
                 displayColor: Colors.white,
              ),
            ),
            themeMode: settings.theme == 'dark' ? ThemeMode.dark : ThemeMode.light,
            home: DefaultPageController(
              controller: PageController(),
              child: PageView(
                children: const [
                  HomeScreen(),
                  ScheduleListScreen(),
          ],
        ),
      ),
            routes: {
              '/settings': (context) => const SettingsScreen(),
            },
          );
        },
      ),
    );
  }
}
