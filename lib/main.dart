import 'package:flutter/material.dart';

import 'data/local/database/app_database.dart';
import 'services/background_service_manager.dart';
import 'services/event_coordinator.dart';
import 'ui/home/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SQLite database
  try {
    await AppDatabase.instance.database;
  } catch (_) {}

  // Initialize native event capture & coordination
  try {
    await EventCoordinator.instance.initialize();
  } catch (_) {}

  // Initialize background service
  try {
    await BackgroundServiceManager.instance.initialize();
  } catch (_) {}

  runApp(const MsgToServerApp());
}

class MsgToServerApp extends StatelessWidget {
  const MsgToServerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MSG to Server',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E88E5),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
