import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/firebase_paths.dart';
import 'chat_screen.dart';
import 'contacts_screen.dart';
import 'settings_screen.dart';
import 'broadcast_screen.dart';

class ChatsListScreen extends StatefulWidget {
  const ChatsListScreen({super.key});
  @override State<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends State<ChatsListScreen> {
  String _uid = '';
  String _query = '';
  String _filter = 'all';
  bool _searching = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _uid = prefs.getString('uid') ?? '');
  }

  Future<void> _showChatActions(Map<String, dynamic> row) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.push_pin_outlined), title: Text(row['pinned'] == true ? 'إلغاء التثبيت' : 'تثبيت'), onTap: () => Navigator.pop(context, 'pin')),
        ListTile(leading: const Icon(Icons.notifications_off_outlined), title: Text(row['muted'] == true ? 'إلغاء الكتم' : 'كتم الإشعارات'), onTap: () => Navigator.pop(context, 'mute')),
        ListTile(leading: const Icon(Icons.done_all), title: const Text('تحديد كمقروءة'), onTap: () => Navigator.pop(context, 'read')),
        ListTile(leading: Icon(row['favorite'] == true ? Icons.favorite : Icons.favorite_border, color: Colors.red), title: Text(row['favorite'] == true ? 'إزالة من المفضلة' : 'إضافة للمفضلة'), onTap: () => Navigator.pop(context, 'favorite')),
        ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red), title: const Text('حذف المحادثة'), onTap: () => Navigator.pop(context, 'delete')),
      ])),
    );
    if (!mounted || action == null) return;
    final ref = FirebaseDatabase.instance.ref('${FirebasePaths.userChats(_uid)}/${FirebasePaths.safeSegment(row['id'].toString())}');
    if (action == 'pin') await ref.update({'pinned': row['pinned'] != true});
    if (action == 'mute') await ref.update({'muted': row['muted'] != true});
    if (action == 'read') await ref.update({'unread': 0});
    if (action == 'favorite') await ref.update({'favorite': row['favorite'] != true});
    if (action == 'delete') {
      final old = await ref.get();
      await ref.remove();
      if (mounted && old.exists) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('تم حذف المحادثة'), action: SnackBarAction(label: 'تراجع', onPressed: () => ref.set(old.value))));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: _searching
              ? TextField(autofocus: true, textDirection: TextDirection.rtl, decoration: const InputDecoration(hintText: 'بحث في المحادثات', border: InputBorder.none), onChanged: (value) => setState(() => _query = value.trim().toLowerCase()))
              : const Text('الدردشات'),
          actions: [
            IconButton(onPressed: () => setState(() { _searching = !_searching; if (!_searching) _query = ''; }), icon: Icon(_searching ? Icons.close : Icons.search)),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'broadcast') {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const BroadcastScreen()));
                } else {
                  setState(() => _filter = value);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'broadcast', child: Text('رسالة جماعية جديدة')),
                PopupMenuItem(value: 'all', child: Text('الكل')),
                PopupMenuItem(value: 'unread', child: Text('غير مقروءة')),
                PopupMenuItem(value: 'favorites', child: Text('المفضلة')),
                PopupMenuItem(value: 'groups', child: Text('الجروبات')),
              ],
            ),
            IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())), icon: const Icon(Icons.settings_outlined)),
          ],
        ),
        body: _uid.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _filterBar(),
                  Expanded(child: StreamBuilder<DatabaseEvent>(
                stream: FirebaseDatabase.instance.ref(FirebasePaths.userChats(_uid)).onValue,
                builder: (context, snapshot) {
                  final rows = <Map<String, dynamic>>[];
                  final raw = snapshot.data?.snapshot.value;
                  if (raw is Map) {
                    raw.forEach((id, value) {
                      if (value is Map) {
                        final row = Map<String, dynamic>.from(value)..['id'] = id.toString();
                        final haystack = '${row['name'] ?? ''} ${row['phone'] ?? ''} ${row['lastMessage'] ?? ''}'.toLowerCase();
                        final matchesFilter = _filter == 'all' ||
                            (_filter == 'unread' && ((row['unread'] as num?) ?? 0) > 0) ||
                            (_filter == 'favorites' && row['favorite'] == true) ||
                            (_filter == 'groups' && row['isGroup'] == true);
                        if (row['archived'] != true && matchesFilter && (_query.isEmpty || haystack.contains(_query))) rows.add(row);
                      }
                    });
                  }
                  rows.sort((a, b) {
                    if (a['pinned'] == true && b['pinned'] != true) return -1;
                    if (a['pinned'] != true && b['pinned'] == true) return 1;
                    return ((b['updatedAt'] as num?) ?? 0).compareTo((a['updatedAt'] as num?) ?? 0);
                  });
                  if (rows.isEmpty) return const Center(child: Text('لا توجد محادثات بعد'));
                  return RefreshIndicator(
                    onRefresh: () async => setState(() {}),
                    color: Theme.of(context).colorScheme.primary,
                    child: ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (_, index) {
                        final row = rows[index];
                        return Dismissible(
                          key: ValueKey(row['id']),
                          direction: DismissDirection.endToStart,
                          background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 24), child: const Icon(Icons.archive, color: Colors.white)),
                          onDismissed: (_) async {
                            final ref = FirebaseDatabase.instance.ref('${FirebasePaths.userChats(_uid)}/${FirebasePaths.safeSegment(row['id'].toString())}');
                            await ref.update({'archived': true});
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('تمت أرشفة المحادثة'), action: SnackBarAction(label: 'تراجع', onPressed: () => ref.update({'archived': false}))));
                          },
                          child: ListTile(
                            leading: CircleAvatar(child: Text((row['name']?.toString() ?? 'م').characters.first)),
                            title: Text(row['name']?.toString() ?? 'محادثة'),
                            subtitle: Text(row['lastMessage']?.toString() ?? ''),
                            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                              if (row['pinned'] == true) const Icon(Icons.push_pin, size: 15, color: Color(0xFF667781)),
                              Text(_timeLabel(row['updatedAt']), style: const TextStyle(fontSize: 11, color: Color(0xFF667781))),
                              if ((row['unread'] as num? ?? 0) > 0) CircleAvatar(radius: 10, backgroundColor: const Color(0xFF25D366), child: Text('${row['unread']}', style: const TextStyle(fontSize: 11, color: Colors.white))),
                            ]),
                            onLongPress: () => _showChatActions(row),
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(conversationId: row['id'].toString(), peerId: row['peerId']?.toString(), peerName: row['name']?.toString()))),
                          ),
                        );
                      },
                    ),
                  );
                },
                  )),
                ],
              ),
        floatingActionButton: FloatingActionButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactsScreen())), child: const Icon(Icons.chat)),
      );

  Widget _filterBar() => SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          children: [
            ['all', 'الكل'],
            ['unread', 'غير مقروءة'],
            ['favorites', 'المفضلة'],
            ['groups', 'الجروبات'],
          ].map((item) => Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: ChoiceChip(
              label: Text(item[1]),
              selected: _filter == item[0],
              selectedColor: const Color(0xFFD9FDD3),
              onSelected: (_) => setState(() => _filter = item[0]),
            ),
          )).toList(),
        ),
      );

  String _timeLabel(dynamic value) {
    final milliseconds = value is num ? value.toInt() : 0;
    if (milliseconds <= 0) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
