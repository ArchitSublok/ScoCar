
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart'; // 👈 Add this missing import!
import 'firebase_options.dart';

import 'screens/landing_screen.dart';
import 'screens/login_screen.dart';
import 'screens/guard_dashboard.dart';
import 'screens/add_vehicle_screen.dart';
import 'screens/resident_dashboard.dart';
import 'screens/log_movement_screen.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); // Requires your firebase_options.dart setup
  runApp(const ScoCarApp());

  runApp(const ScoCarApp());
}


final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

class ScoCarApp extends StatelessWidget {
  const ScoCarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, mode, __) {
        return MaterialApp(
          themeMode: mode,
          debugShowCheckedModeBanner: false,
          title: 'SCOCAR OS',
          theme: ThemeData(
            brightness: Brightness.light,
            primarySwatch: Colors.blue,
            scaffoldBackgroundColor: Colors.grey[100],
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF0A0E21),
            cardColor: const Color(0xFF1D1E33),
          ),
          // themeMode: mode,
          initialRoute: '/',
          // routes: {
          //   '/': (context) =>  LandingScreen(),
          //   '/login': (context) =>  LoginScreen(),
          //   '/dashboard': (context) =>  GuardDashboard(),
          //   '/add-vehicle': (context) =>  AddVehicleScreen(),
          //   '/resident-dashboard': (context) => ResidentDashboard(),
          //   '/log-movement': (context) => const LogMovementScreen(),
          // },
          routes: {
  '/': (context) => const LandingScreen(),
  '/login': (context) => const LoginScreen(),
  '/guard-dashboard': (context) => const GuardDashboard(),
  '/resident-dashboard': (context) => const ResidentDashboard(),
  '/log-movement': (context) => const LogMovementScreen(),
  '/add-vehicle': (context) => const AddVehicleScreen(),
}
        );
      },
    );
  }
}