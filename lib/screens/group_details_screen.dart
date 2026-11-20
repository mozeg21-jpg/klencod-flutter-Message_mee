import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/firebase_paths.dart';

class GroupDetailsScreen extends StatefulWidget {
  final String groupId;
  const GroupDetailsScreen({super.key, required this.groupId});
  @override State<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends State<GroupDetailsScreen> {
  final _memberController = TextEditingController();
  final _picker = ImagePicker();
  String _uid = '';
  bool _canSend = true;
  bool _canChangePhoto = true;
  @override void initState() { super.initState(); _loadUid(); }
  Future<void> _loadUid() async { final p = await SharedPreferences.getInstance(); if (mounted) setState(() => _uid = p.getString('uid') ?? ''); }
  @override void dispose() { _memberController.dispose(); super.dispose(); }
  Future<void> _addMember() async { final id = _memberController.text.trim(); if (id.isEmpty) return; final safeId = FirebasePaths.safeSegment(id); await FirebaseDatabase.instance.ref(FirebasePaths.group(widget.groupId)).update({'members/$safeId': true, 'memberNames/$safeId': id}); _memberController.clear(); if (mounted) setState(() {}); }
  Future<void> _removeMember(String id) async { final safeId = FirebasePaths.safeSegment(id); await FirebaseDatabase.instance.ref(FirebasePaths.group(widget.groupId)).update({'members/$safeId': null, 'memberNames/$safeId': null, 'admins/$safeId': null}); if (mounted) setState(() {}); }
  Future<void> _changePhoto() async { final file = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 75); if (file == null) return; final bytes = await file.readAsBytes(); if (bytes.length > 700 * 1024) return; await FirebaseDatabase.instance.ref(FirebasePaths.group(widget.groupId)).update({'photoBase64': base64Encode(bytes)}); if (mounted) setState(() {}); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('تفاصيل الجروب')),
    body: FutureBuilder<DataSnapshot>(
      future: FirebaseDatabase.instance.ref(FirebasePaths.group(widget.groupId)).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final value = snapshot.data?.value;
        final group = value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
        final members = group['memberNames'] is Map ? Map<String, dynamic>.from(group['memberNames']) : <String, dynamic>{};
        final admins = group['admins'] is Map ? Map<String, dynamic>.from(group['admins']) : <String, dynamic>{};
        final owner = group['ownerId']?.toString() == _uid || admins[_uid] == true;
        final invite = 'message-mee://group/${widget.groupId}';
        return ListView(padding: const EdgeInsets.all(16), children: [
          GestureDetector(onTap: owner && _canChangePhoto ? _changePhoto : null, child: CircleAvatar(radius: 42, backgroundImage: group['photoBase64'] == null ? null : MemoryImage(base64Decode(group['photoBase64'].toString())), child: group['photoBase64'] == null ? Text((group['name']?.toString() ?? 'ج').characters.first) : null)),
          const SizedBox(height: 12),
          Center(child: Text(group['name']?.toString() ?? 'جروب', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
          const SizedBox(height: 20),
          if (owner) ...[
            SwitchListTile(title: const Text('السماح بإرسال الرسائل'), value: _canSend, onChanged: (v) async { setState(() => _canSend = v); await FirebaseDatabase.instance.ref(FirebasePaths.group(widget.groupId)).update({'settings/canSend': v}); }),
            SwitchListTile(title: const Text('السماح بتغيير صورة الجروب'), value: _canChangePhoto, onChanged: (v) async { setState(() => _canChangePhoto = v); await FirebaseDatabase.instance.ref(FirebasePaths.group(widget.groupId)).update({'settings/canChangePhoto': v}); }),
            TextField(controller: _memberController, decoration: InputDecoration(labelText: 'UID العضو لإضافته', suffixIcon: IconButton(onPressed: _addMember, icon: const Icon(Icons.person_add)))),
            const SizedBox(height: 16),
          ],
          ListTile(leading: const Icon(Icons.link), title: const Text('رابط دعوة الجروب'), subtitle: Text(invite), trailing: IconButton(onPressed: () { Clipboard.setData(ClipboardData(text: invite)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ الرابط'))); }, icon: const Icon(Icons.copy))),
          Text('الأعضاء (${members.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ...members.entries.map((entry) => ListTile(leading: const CircleAvatar(child: Icon(Icons.person)), title: Text(entry.value.toString()), subtitle: admins[entry.key] == true ? const Text('مشرف') : null, trailing: owner && entry.key != _uid ? IconButton(onPressed: () => _removeMember(entry.key.toString()), icon: const Icon(Icons.remove_circle_outline, color: Colors.red)) : null)),
        ]);
      },
    ),
  );
}
