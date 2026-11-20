import 'dart:convert';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/firebase_paths.dart';
import 'starred_messages_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _uid = '';
  String _name = '';
  String _photoBase64 = '';
  bool _lastSeen = true;
  bool _readReceipts = true;
  bool _notifications = true;
  bool _loading = true;

  DatabaseReference get _settingsRef =>
      FirebaseDatabase.instance.ref('${FirebasePaths.user(_uid)}/settings');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('uid') ?? '';
    final name = prefs.getString('name') ?? '';
    final photoBase64 = prefs.getString('photoBase64') ?? '';
    var lastSeen = prefs.getBool('last_seen') ?? true;
    var readReceipts = prefs.getBool('read_receipts') ?? true;
    var notifications = prefs.getBool('notifications') ?? true;
    if (uid.isNotEmpty) {
      try {
        final snapshot = await _settingsRef.get();
        if (snapshot.value is Map) {
          final data = Map<String, dynamic>.from(snapshot.value as Map);
          lastSeen = data['lastSeen'] is bool ? data['lastSeen'] as bool : lastSeen;
          readReceipts = data['readReceipts'] is bool ? data['readReceipts'] as bool : readReceipts;
          notifications = data['notifications'] is bool ? data['notifications'] as bool : notifications;
        }
      } catch (_) {}
    }
    await prefs.setBool('last_seen', lastSeen);
    await prefs.setBool('read_receipts', readReceipts);
    await prefs.setBool('notifications', notifications);
    if (!mounted) return;
    setState(() {
      _uid = uid;
      _name = name;
      _photoBase64 = photoBase64;
      _lastSeen = lastSeen;
      _readReceipts = readReceipts;
      _notifications = notifications;
      _loading = false;
    });
  }

  Future<void> _setValue(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key == 'lastSeen' ? 'last_seen' : key == 'readReceipts' ? 'read_receipts' : 'notifications', value);
    if (_uid.isNotEmpty) {
      await _settingsRef.update({key: value, 'updatedAt': ServerValue.timestamp});
    }
  }

  Future<void> _toggle(String key, bool value) async {
    setState(() {
      if (key == 'lastSeen') _lastSeen = value;
      if (key == 'readReceipts') _readReceipts = value;
      if (key == 'notifications') _notifications = value;
    });
    try {
      await _setValue(key, value);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر حفظ الإعداد، حاول مرة أخرى')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: const Color(0xFFD9FDD3),
                  backgroundImage: _profileImage(),
                  child: _photoBase64.isEmpty ? const Icon(Icons.person, size: 36, color: Color(0xFF075E54)) : null,
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_name.isEmpty ? 'مستخدم' : _name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text('متاح', style: TextStyle(color: Colors.grey)),
                ])),
                IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _message('يمكن تعديل الاسم والصورة من الملف الشخصي')),
              ],
            ),
          ),
          const Divider(height: 1),
          _settingTile(Icons.person_outline, 'الحساب', 'الاسم والصورة ورقم الهاتف'),
          const Divider(),
          const ListTile(leading: Icon(Icons.lock_outline), title: Text('الخصوصية')),
          SwitchListTile(
            secondary: const Icon(Icons.visibility_outlined),
            title: const Text('إظهار آخر ظهور'),
            value: _lastSeen,
            onChanged: (value) => _toggle('lastSeen', value),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.done_all),
            title: const Text('علامات القراءة'),
            value: _readReceipts,
            onChanged: (value) => _toggle('readReceipts', value),
          ),
          const Divider(),
          _settingTile(Icons.account_circle_outlined, 'الصورة الرمزية', 'اختيار صورة الملف الشخصي'),
          _settingTile(Icons.chat_bubble_outline, 'الدردشات', 'الخلفية والرسائل المؤقتة'),
          ListTile(leading: const Icon(Icons.star_border, color: Colors.amber), title: const Text('الرسائل المميزة'), onTap: _uid.isEmpty ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => StarredMessagesScreen(uid: _uid)))),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_none),
            title: const Text('الإشعارات'),
            value: _notifications,
            onChanged: (value) => _toggle('notifications', value),
          ),
          ListTile(leading: const Icon(Icons.storage_outlined), title: const Text('التخزين والبيانات'), onTap: () => _message('إدارة التخزين متاحة من إعدادات الجهاز')), 
          ListTile(leading: const Icon(Icons.help_outline), title: const Text('المساعدة'), onTap: () => _message('للدعم، راجع إعدادات Firebase وسجل الأخطاء')), 
          ListTile(leading: const Icon(Icons.group_add_outlined), title: const Text('دعوة صديق'), onTap: () => _message('يمكنك مشاركة التطبيق مع أصدقائك')), 
        ],
      ),
    );
  }

  Widget _settingTile(IconData icon, String title, String subtitle) {
    return ListTile(
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: const Color(0xFFD9FDD3),
        child: Icon(icon, color: const Color(0xFF075E54)),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _message('$title: الإعداد متاح من هذه الشاشة'),
    );
  }

  ImageProvider? _profileImage() {
    if (_photoBase64.trim().isEmpty) return null;
    try {
      var encoded = _photoBase64.trim();
      if (encoded.contains(',')) encoded = encoded.split(',').last;
      return MemoryImage(base64Decode(encoded));
    } catch (_) {
      return null;
    }
  }

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}
