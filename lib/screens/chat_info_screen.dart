import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import '../utils/firebase_paths.dart';
import 'chat_media_screen.dart';

class ChatInfoScreen extends StatefulWidget {
  final String conversationId;
  final String name;
  final String? phone;
  const ChatInfoScreen({super.key, required this.conversationId, required this.name, this.phone});

  @override State<ChatInfoScreen> createState() => _ChatInfoScreenState();
}

class _ChatInfoScreenState extends State<ChatInfoScreen> {
  bool _muted = false;
  String _disappearing = 'off';

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('معلومات المحادثة')),
        body: ListView(
          children: [
            const SizedBox(height: 22),
            const CircleAvatar(radius: 42, child: Icon(Icons.person, size: 42)),
            const SizedBox(height: 10),
            Center(child: Text(widget.name, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold))),
            if (widget.phone != null && widget.phone!.isNotEmpty) Center(child: Text(widget.phone!)),
            const Divider(height: 32),
            SwitchListTile(title: const Text('كتم الإشعارات'), value: _muted, onChanged: (value) => setState(() => _muted = value)),
            ListTile(leading: const Icon(Icons.timer_outlined), title: const Text('الرسائل المؤقتة'), subtitle: Text(_disappearing == 'off' ? 'متوقفة' : _disappearing), onTap: _chooseDisappearing),
            const ListTile(leading: Icon(Icons.lock_outline), title: Text('التشفير من الطرف إلى الطرف'), subtitle: Text('لا أحد خارج هذه المحادثة يستطيع قراءة الرسائل')),
            const Padding(padding: EdgeInsets.all(16), child: Text('الوسائط والروابط والمستندات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
            ListTile(
              leading: const Icon(Icons.perm_media_outlined),
              title: const Text('عرض كل الوسائط والروابط والمستندات'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatMediaScreen(conversationId: widget.conversationId))),
            ),
            _mediaGrid(),
            ListTile(leading: const Icon(Icons.block, color: Colors.red), title: const Text('حظر المستخدم', style: TextStyle(color: Colors.red)), onTap: () {}),
          ],
        ),
      );

  Future<void> _chooseDisappearing() async {
    final value = await showModalBottomSheet<String>(context: context, builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      for (final item in const {'off': 'متوقفة', '24h': 'بعد 24 ساعة', '7d': 'بعد 7 أيام', '90d': 'بعد 90 يومًا'}.entries)
        ListTile(title: Text(item.value), onTap: () => Navigator.pop(context, item.key)),
    ])));
    if (value != null) {
      await FirebaseDatabase.instance.ref('${FirebasePaths.conversation(widget.conversationId)}/settings/disappearing').set(value);
      if (mounted) setState(() => _disappearing = value);
    }
  }

  Widget _mediaGrid() => FutureBuilder<DataSnapshot>(
        future: FirebaseDatabase.instance.ref(FirebasePaths.conversationMessages(widget.conversationId)).get(),
        builder: (context, snapshot) {
          final media = <String>[];
          final value = snapshot.data?.value;
          if (value is Map) {
            for (final raw in value.values) {
              if (raw is Map && raw['mediaType'] == 'image' && raw['mediaBase64'] != null) media.add(raw['mediaBase64'].toString());
            }
          }
          if (media.isEmpty) return const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('لا توجد وسائط بعد'));
          return GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: media.length, gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 4, mainAxisSpacing: 4), itemBuilder: (_, i) => Image.memory(base64Decode(media[i]), fit: BoxFit.cover));
        },
      );
}
