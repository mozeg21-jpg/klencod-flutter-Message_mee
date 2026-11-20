import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import '../utils/firebase_paths.dart';

class StarredMessagesScreen extends StatelessWidget {
  final String uid;
  const StarredMessagesScreen({super.key, required this.uid});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('الرسائل المميزة')),
        body: StreamBuilder<DatabaseEvent>(
          stream: FirebaseDatabase.instance.ref('starredMessages/${FirebasePaths.safeSegment(uid)}').onValue,
          builder: (context, snapshot) {
            final rows = <Map<String, dynamic>>[];
            final raw = snapshot.data?.snapshot.value;
            if (raw is Map) {
              raw.forEach((conversationId, messages) {
                if (messages is Map) {
                  messages.forEach((messageId, value) {
                    if (value is Map) rows.add({...Map<String, dynamic>.from(value), 'conversationId': conversationId.toString(), 'messageId': messageId.toString()});
                  });
                }
              });
            }
            rows.sort((a, b) => ((b['time'] as num?) ?? 0).compareTo((a['time'] as num?) ?? 0));
            if (rows.isEmpty) return const Center(child: Text('لا توجد رسائل مميزة'));
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final message = rows[index];
                final preview = message['text']?.toString() ?? (message['mediaType'] == 'image' ? 'صورة' : message['audioBase64'] != null ? 'تسجيل صوتي' : 'رسالة');
                return ListTile(leading: const Icon(Icons.star, color: Colors.amber), title: Text(preview, maxLines: 2, overflow: TextOverflow.ellipsis), subtitle: Text(message['senderName']?.toString() ?? 'مستخدم'));
              },
            );
          },
        ),
      );
}
