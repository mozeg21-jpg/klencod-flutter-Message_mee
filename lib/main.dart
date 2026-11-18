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
        title: 'Ahmed Saad Community',
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFFE85C5C),
        ),
        home: const SplashScreen(),
      );
}