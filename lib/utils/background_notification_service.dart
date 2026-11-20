import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import 'notification_service.dart';
import 'firebase_paths.dart';

/// خدمة خلفية (Foreground Service) بتستمع لقاعدة الرسائل حتى والتطبيق
/// مقفول، وتطلق إشعارًا محليًا بأي رسالة جديدة من مستخدم آخر.
/// بدون خادم وبدون Firebase Functions → بدون أي تكلفة.
class BackgroundNotificationService {
  static const String _seenKey = 'bg_seen_message_ids';

  /// تهيئة الخدمة وتشغيلها تلقائيًا بعد أول فتح للتطبيق.
  static Future<void> initialize() async {
    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        // لا تبدأ الخدمة أثناء إقلاع التطبيق قبل اكتمال واجهة Flutter
        // وإذن الإشعارات؛ بدءها مبكرًا كان سببًا شائعًا لإغلاق التطبيق.
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'bg_messages',
      initialNotificationTitle: 'إشعارات Messenger مفعلة',
        initialNotificationContent: 'بتستلم الرسائل الجديدة حتى والتطبيق مقفول',
      ),
      iosConfiguration: IosConfiguration(autoStart: false),
    );
  }

  /// يبدأ بعد دخول المستخدم للمحادثة ومنح إذن الإشعارات، وليس أثناء شاشة
  /// البداية؛ بهذه الطريقة لا يمكن للخدمة أن تغلق التطبيق عند الإقلاع.
  static Future<void> start() async {
    try {
      await FlutterBackgroundService().startService();
    } catch (_) {
      // الإشعارات داخل التطبيق تظل عاملة حتى لو منع النظام الخدمة الخلفية.
    }
  }

  @pragma('vm:entry-point')
  static Future<void> _onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();

    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    } catch (_) {}
    await NotificationService.init();

    final prefs = await SharedPreferences.getInstance();
    final myUid = prefs.getString('uid') ?? '';
    final seen = (prefs.getStringList(_seenKey) ?? []).toSet();

    bool firstSnapshot = true;
    FirebaseDatabase.instance.ref('messages').limitToLast(30).onValue.listen((event) {
      final value = event.snapshot.value;
      if (value is! Map) return;

      final batch = <MapEntry>[];
      value.forEach((key, val) {
        if (val is Map) batch.add(MapEntry(key.toString(), val));
      });

      // أول قراءة: نسجل الرسائل القديمة من غير إشعارات، وبعدها الجديد بس يُنوّه عنه
      if (firstSnapshot) {
        firstSnapshot = false;
        for (final e in batch) {
          final m = Map<String, dynamic>.from(e.value as Map);
          seen.add(e.key);
          if (m['senderId'] != myUid) seen.add(e.key);
        }
        _persist(prefs, seen);
        return;
      }

      for (final e in batch) {
        final id = e.key;
        if (seen.contains(id)) continue;
        seen.add(id);
        final m = Map<String, dynamic>.from(e.value as Map);
        if (m['senderId'] == myUid) continue;

        final name = (m['senderName'] ?? 'مستخدم').toString();
        NotificationService.show(
          title: name,
          body: _bodyOf(m),
          id: id.hashCode,
        );
      }
      _persist(prefs, seen);
    });

    // المحادثات الجديدة تستخدم userChats/{uid} بدل المسار القديم messages.
    if (myUid.isNotEmpty) {
      var firstChatsSnapshot = true;
      FirebaseDatabase.instance.ref(FirebasePaths.userChats(myUid)).onValue.listen((event) {
        final value = event.snapshot.value;
        if (value is! Map) return;
        final current = <MapEntry<String, Map<String, dynamic>>>[];
        value.forEach((key, raw) {
          if (raw is Map) current.add(MapEntry(key.toString(), Map<String, dynamic>.from(raw)));
        });
        if (firstChatsSnapshot) {
          firstChatsSnapshot = false;
          for (final entry in current) {
            final stamp = entry.value['updatedAt']?.toString() ?? '';
            seen.add('chat:${entry.key}:$stamp');
          }
          _persist(prefs, seen);
          return;
        }
        for (final entry in current) {
          final chat = entry.value;
          final unread = chat['unread'] is num ? (chat['unread'] as num).toInt() : int.tryParse('${chat['unread']}') ?? 0;
          final stamp = chat['updatedAt']?.toString() ?? '';
          final id = 'chat:${entry.key}:$stamp';
          if (stamp.isEmpty || seen.contains(id) || unread <= 0) continue;
          seen.add(id);
          NotificationService.show(
            title: (chat['name'] ?? 'رسالة جديدة').toString(),
            body: (chat['lastMessage'] ?? 'رسالة جديدة').toString(),
            id: id.hashCode,
          );
        }
        _persist(prefs, seen);
      });
    }
  }

  static void _persist(SharedPreferences prefs, Set<String> seen) {
    final list = seen.toList();
    if (list.length > 120) {
      prefs.setStringList(_seenKey, list.sublist(list.length - 120));
    } else {
      prefs.setStringList(_seenKey, list);
    }
  }

  static String _bodyOf(Map<String, dynamic> m) {
    final reply = m['replyTo'] as Map?;
    final prefix = reply != null ? 'رد على ${reply['name'] ?? ''}: ' : '';
    final type = (m['mediaType'] ?? '').toString();
    if (type == 'image') return '${prefix}صورة';
    if (type == 'video') return '${prefix}فيديو';
    if ((m['audioBase64'] ?? '').toString().isNotEmpty) return '${prefix}تسجيل صوتي';
    return '$prefix${(m['text'] ?? '').toString()}';
  }
}
