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

// ─────────────────────────────────────────────────────────────────────────────
// BACKGROUND MESSAGE HANDLER
// Must be a top-level function (not a class method).
// Runs when app is terminated or in background.
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase must be re-initialized in isolate
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  debugPrint('📩 Background message: ${message.messageId}');
  debugPrint('   Title: ${message.notification?.title}');
  debugPrint('   Body:  ${message.notification?.body}');

  // Show local notification even in background
  await NotificationService().showLocalNotification(
    title: message.notification?.title ?? 'SocCar Alert',
    body: message.notification?.body ?? '',
    payload: message.data.toString(),
  );
}

// Global theme notifier — allows dark/light mode toggle from anywhere
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 2. Register background handler BEFORE runApp
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // 3. Initialize local notifications + request permissions
  await NotificationService().init();

  // 4. Handle notification that launched the app from terminated state
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
          theme: ThemeData(
            colorSchemeSeed: Colors.blueAccent,
            brightness: Brightness.light,
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorSchemeSeed: Colors.blueAccent,
            brightness: Brightness.dark,
            useMaterial3: true,
          ),
          initialRoute: '/',
          routes: {
            '/': (context) => const LandingScreen(),
            '/login': (context) => const LoginScreen(),
            '/guard_dashboard': (context) => const GuardDashboard(),
            '/resident_dashboard': (context) => const ResidentDashboard(),
            '/cameras': (_) => const CameraRegistrationScreen(),
          },
        );
      },
    );
  }
}
