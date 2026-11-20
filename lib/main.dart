import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'utils/background_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    FirebaseDatabase.instance.setPersistenceEnabled(true);
    // تهيئة الإشعارات بعد Firebase، لكن لا نشغّل Foreground Service تلقائيًا
    // أثناء الإقلاع؛ هذا يمنع crash على أندرويد 13/14 قبل منح إذن الإشعارات.
    await BackgroundNotificationService.initialize();
  } catch (_) {}
  runApp(const AhmedSaadCommunityApp());
}

class AhmedSaadCommunityApp extends StatelessWidget {
  const AhmedSaadCommunityApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Ahmed Messenger',
        themeMode: ThemeMode.system,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF25D366), brightness: Brightness.light),
          scaffoldBackgroundColor: const Color(0xFFF7F7F7),
          appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF075E54), foregroundColor: Colors.white),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE53935), brightness: Brightness.dark),
          scaffoldBackgroundColor: Colors.black,
          appBarTheme: const AppBarTheme(backgroundColor: Colors.black, foregroundColor: Color(0xFFE53935)),
          cardColor: const Color(0xFF151515),
        ),
        home: const SplashScreen(),
      );
}