import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// إشعارات محلية للرسائل الجديدة والردود.
/// تعمل أثناء فتح التطبيق أو بقائه في الخلفية؛ الإشعار بصفحة مقفلة
/// تمامًا (القتل الكامل) يحتاج لاحقًا إلى Firebase Cloud Messaging.
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'messages',
    'رسائل التطبيق',
    description: 'إشعارات الرسائل الجديدة والردود',
    importance: Importance.high,
  );

  static Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
    _initialized = true;
  }

  /// طلب إذن الإشعارات (أندرويد 13+).
  static Future<bool> requestPermission() async {
    final impl = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    return await impl?.requestNotificationsPermission() ?? true;
  }

  static Future<void> show({
    required String title,
    required String body,
    required int id,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'messages',
        'رسائل التطبيق',
        channelDescription: 'إشعارات الرسائل الجديدة والردود',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    );
    await _plugin.show(id, title, body, details);
  }
}
