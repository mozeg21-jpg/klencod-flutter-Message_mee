import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/firebase_paths.dart';

class BroadcastScreen extends StatefulWidget {
  const BroadcastScreen({super.key});
  @override
  State<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends State<BroadcastScreen> {
  final _message = TextEditingController();
  final Set<String> _selected = {};
  String _uid = '', _name = '';
  bool _sending = false;

  @override
  void initState() { super.initState(); _loadProfile(); }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() { _uid = prefs.getString('uid') ?? ''; _name = prefs.getString('name') ?? ''; });
  }

  @override
  void dispose() { _message.dispose(); super.dispose(); }

  Future<void> _send(List<Map<String, dynamic>> users) async {
    final text = _message.text.trim();
    if (text.isEmpty || _selected.isEmpty || _uid.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      for (final user in users.where((item) => _selected.contains(item['id']))) {
        final peerId = user['id']!.toString();
        final conversationId = FirebasePaths.conversationId(_uid, peerId);
        await FirebaseDatabase.instance.ref(FirebasePaths.conversation(conversationId)).update({
          'conversationId': conversationId,
          'members': {_uid: true, peerId: true},
          'createdAt': ServerValue.timestamp,
        });
        await FirebaseDatabase.instance.ref(FirebasePaths.conversationMessages(conversationId)).push().set({
          'text': text,
          'senderId': _uid,
          'senderName': _name,
          'broadcast': true,
          'time': ServerValue.timestamp,
          'status': 'sent',
        });
        final preview = 'رسالة جماعية: $text';
        await FirebaseDatabase.instance.ref().update({
          '${FirebasePaths.userChats(_uid)}/$conversationId/peerId': peerId,
          '${FirebasePaths.userChats(_uid)}/$conversationId/name': user['name']?.toString() ?? 'مستخدم',
          '${FirebasePaths.userChats(_uid)}/$conversationId/lastMessage': preview,
          '${FirebasePaths.userChats(_uid)}/$conversationId/updatedAt': ServerValue.timestamp,
          '${FirebasePaths.userChats(_uid)}/$conversationId/unread': 0,
          '${FirebasePaths.userChats(peerId)}/$conversationId/peerId': _uid,
          '${FirebasePaths.userChats(peerId)}/$conversationId/name': _name,
          '${FirebasePaths.userChats(peerId)}/$conversationId/lastMessage': text,
          '${FirebasePaths.userChats(peerId)}/$conversationId/updatedAt': ServerValue.timestamp,
          '${FirebasePaths.userChats(peerId)}/$conversationId/unread': ServerValue.increment(1),
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال الرسالة الجماعية')));
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر إرسال الرسالة الجماعية')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('رسالة جماعية')),
        body: StreamBuilder<DatabaseEvent>(
          stream: FirebaseDatabase.instance.ref('users').onValue,
          builder: (context, snapshot) {
            final users = <Map<String, dynamic>>[];
            final raw = snapshot.data?.snapshot.value;
            if (raw is Map) raw.forEach((id, value) { if (value is Map && id.toString() != _uid) users.add({...Map<String, dynamic>.from(value), 'id': id.toString()}); });
            return Column(children: [
              Padding(padding: const EdgeInsets.all(12), child: TextField(controller: _message, maxLines: 3, decoration: const InputDecoration(labelText: 'الرسالة', border: OutlineInputBorder()))),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Align(alignment: AlignmentDirectional.centerStart, child: Text('اختر حتى 256 جهة (${_selected.length}/256)'))),
              Expanded(child: ListView.builder(itemCount: users.length, itemBuilder: (_, index) {
                final user = users[index];
                final id = user['id'].toString();
                final selected = _selected.contains(id);
                return CheckboxListTile(
                  value: selected,
                  onChanged: selected || _selected.length < 256 ? (value) => setState(() { if (value == true) _selected.add(id); else _selected.remove(id); }) : null,
                  title: Text(user['name']?.toString() ?? 'مستخدم'),
                  subtitle: Text(user['phone']?.toString() ?? user['username']?.toString() ?? ''),
                  secondary: const CircleAvatar(child: Icon(Icons.person)),
                );
              })),
              SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _sending ? null : () => _send(users), icon: const Icon(Icons.send), label: Text(_sending ? 'جاري الإرسال...' : 'إرسال للجميع'))))),
            ]);
          },
        ),
      );
}
