import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'call_screen.dart';
import '../utils/call_service.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});
  @override State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  String _uid = '', _name = '';
  List<Contact> _phoneContacts = [];
  bool _contactsLoading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) setState(() { _uid = p.getString('uid') ?? ''; _name = p.getString('name') ?? ''; });
    try {
      if (await FlutterContacts.requestPermission()) {
        final contacts = await FlutterContacts.getContacts(withProperties: true);
        if (mounted) setState(() => _phoneContacts = contacts);
      }
    } finally {
      if (mounted) setState(() => _contactsLoading = false);
    }
  }

  String _phoneKey(String value) => value.replaceAll(RegExp(r'[^0-9+]'), '').replaceFirst(RegExp(r'^00'), '+');

  Future<void> _call(Map<String, dynamic> user, String type) async {
    final id = user['id']?.toString() ?? '';
    if (id.isEmpty || id == _uid) return;
    final callId = await CallService.createCall(
      callerId: _uid, callerName: _name, targetId: id, type: type,
    );
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => CallScreen(callId: callId, uid: _uid, caller: true, type: type)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('جهات الاتصال'), backgroundColor: const Color(0xFFE85C5C)),
    body: StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance.ref('users').onValue,
      builder: (_, snapshot) {
        final users = <Map<String, dynamic>>[];
        final registeredPhones = <String, Map<String, dynamic>>{};
        final raw = snapshot.data?.snapshot.value;
        if (raw is Map) {
          raw.forEach((id, value) {
            if (value is Map && id.toString() != _uid) {
              final user = Map<String, dynamic>.from(value); user['id'] = id.toString(); users.add(user);
              final phone = user['phone']?.toString() ?? '';
              if (phone.isNotEmpty) registeredPhones[_phoneKey(phone)] = user;
            }
          });
        }
        if (_contactsLoading) return const Center(child: CircularProgressIndicator());
        final phoneRows = <Map<String, dynamic>>[];
        for (final contact in _phoneContacts) {
          for (final phone in contact.phones) {
            final key = _phoneKey(phone.number);
            final registered = registeredPhones[key];
            phoneRows.add({
              'displayName': contact.displayName,
              'phone': phone.number,
              'registered': registered != null,
              'user': registered,
            });
          }
        }
        if (phoneRows.isNotEmpty) return ListView.builder(
          itemCount: phoneRows.length,
          itemBuilder: (_, index) {
            final row = phoneRows[index];
            final user = row['user'] as Map<String, dynamic>?;
            return ListTile(
              leading: CircleAvatar(child: Icon(row['registered'] == true ? Icons.person : Icons.person_outline)),
              title: Text(row['displayName']?.toString() ?? 'بدون اسم'),
              subtitle: Text(row['registered'] == true ? (user?['username']?.toString() ?? 'مسجل') : 'غير مسجل'),
              trailing: user == null ? const Text('غير مسجل') : Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(onPressed: () => _call(user, 'audio'), icon: const Icon(Icons.call, color: Color(0xFFE85C5C))),
                IconButton(onPressed: () => _call(user, 'video'), icon: const Icon(Icons.videocam, color: Color(0xFFE85C5C))),
              ]),
            );
          },
        );
        if (users.isEmpty) return const Center(child: Text('لا يوجد مستخدمون مسجلون بعد'));
        return ListView.builder(
          itemCount: users.length,
          itemBuilder: (_, index) {
            final user = users[index];
            final photo = user['photoBase64']?.toString();
            return ListTile(
              leading: CircleAvatar(
                backgroundImage: photo == null || photo.isEmpty ? null : MemoryImage(base64Decode(photo)),
                child: photo == null || photo.isEmpty ? const Icon(Icons.person) : null,
              ),
              title: Text(user['name']?.toString() ?? 'مستخدم'),
              subtitle: Text(user['username']?.toString() ?? ''),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(onPressed: () => _call(user, 'audio'), icon: const Icon(Icons.call, color: Color(0xFFE85C5C))),
                IconButton(onPressed: () => _call(user, 'video'), icon: const Icon(Icons.videocam, color: Color(0xFFE85C5C))),
              ]),
            );
          },
        );
      },
    ),
  );
}
