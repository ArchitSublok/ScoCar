import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';

import 'screens/camera_registration_screen.dart';
import 'screens/landing_screen.dart';
import 'screens/login_screen.dart';
import 'screens/guard_dashboard.dart';
import 'screens/resident_dashboard.dart';
import 'screens/vehicle_detection_screen.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('📩 Background message: ${message.messageId}');
  await NotificationService().showLocalNotification(
    title: message.notification?.title ?? 'SocCar Alert',
    body: message.notification?.body ?? '',
    payload: message.data.toString(),
  );
}

// Global theme notifier — allows dark/light mode toggle from anywhere
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await NotificationService().init();
  final RemoteMessage? initialMessage =
      await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    debugPrint('🚀 App launched from notification: ${initialMessage.data}');
  }
  runApp(const SocCarApp());
}

class SocCarApp extends StatelessWidget {
  const SocCarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, mode, __) {
        return MaterialApp(
          title: 'SocCar OS',
          debugShowCheckedModeBanner: false,
          themeMode: mode,

          // ── Light theme ─────────────────────────────────────────────
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF1565C0),
              brightness: Brightness.light,
            ),
            scaffoldBackgroundColor: const Color(0xFFF0F2F8),
            cardColor: Colors.white,
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF1565C0),
              foregroundColor: Colors.white,
              elevation: 0,
              centerTitle: true,
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.grey.shade100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                    color: Color(0xFF1565C0), width: 1.5),
              ),
              labelStyle:
                  TextStyle(color: Colors.grey.shade700, fontSize: 14),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
            chipTheme: ChipThemeData(
              backgroundColor: Colors.grey.shade200,
              labelStyle: const TextStyle(color: Colors.black87),
              selectedColor: const Color(0xFF1565C0),
            ),
            dividerColor: Colors.grey.shade300,
            textTheme: const TextTheme(
              bodyMedium: TextStyle(color: Color(0xFF1A1A2E)),
              bodySmall: TextStyle(color: Colors.black54),
              titleLarge: TextStyle(
                  color: Color(0xFF1A1A2E), fontWeight: FontWeight.bold),
              labelMedium:
                  TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ),

          // ── Dark theme ──────────────────────────────────────────────
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF00E5FF),
              brightness: Brightness.dark,
              surface: const Color(0xFF0A0A1A),
              onSurface: Colors.white,
            ),
            scaffoldBackgroundColor: const Color(0xFF0A0A1A),
            cardColor: const Color(0xFF141428),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF141428),
              foregroundColor: Colors.white,
              elevation: 0,
              centerTitle: true,
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFF1A1D35),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    const BorderSide(color: Color(0xFF2E3160)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    const BorderSide(color: Color(0xFF2E3160)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                    color: Color(0xFF00E5FF), width: 1.5),
              ),
              labelStyle:
                  const TextStyle(color: Colors.white38, fontSize: 14),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
            chipTheme: const ChipThemeData(
              backgroundColor: Color(0xFF1A1D35),
              labelStyle: TextStyle(color: Colors.white70),
              selectedColor: Color(0xFF00E5FF),
            ),
            dividerColor: const Color(0xFF2E3160),
            textTheme: const TextTheme(
              bodyMedium: TextStyle(color: Colors.white),
              bodySmall: TextStyle(color: Colors.white70),
              titleLarge:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              labelMedium:
                  TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),

          initialRoute: '/',
          routes: {
            '/': (context) => const LandingScreen(),
            '/login': (context) => const LoginScreen(),
            '/guard_dashboard': (context) => const GuardDashboard(),
            '/resident_dashboard': (context) => const ResidentDashboard(),
            '/cameras': (_) => const CameraRegistrationScreen(),
            '/detect_vehicle': (context) => const VehicleDetectionScreen(),
          },
        );
      },
    );
  }
}
