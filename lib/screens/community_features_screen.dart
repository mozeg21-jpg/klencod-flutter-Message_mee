import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'call_screen.dart';
import '../utils/call_service.dart';
import 'group_chat_screen.dart';
import '../widgets/video_message_widget.dart';

/// شاشة الجروبات والحالات داخل تطبيق المراسلة.
class CommunityFeaturesScreen extends StatefulWidget {
  const CommunityFeaturesScreen({super.key});

  @override
  State<CommunityFeaturesScreen> createState() => _CommunityFeaturesScreenState();
}

class _CommunityFeaturesScreenState extends State<CommunityFeaturesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _groupName = TextEditingController();
  final _statusText = TextEditingController();
  String _uid = '';
  String _name = '';
  String _statusPrivacy = 'all';
  XFile? _statusMedia;
  bool _statusVideo = false;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _uid = prefs.getString('uid') ?? '';
      _name = prefs.getString('name') ?? '';
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _groupName.dispose();
    _statusText.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    final name = _groupName.text.trim();
    if (name.isEmpty || _uid.isEmpty) return;
    await FirebaseDatabase.instance.ref('groups').push().set({
      'name': name,
      'ownerId': _uid,
      'ownerName': _name,
      'members': {_uid: true},
      'memberNames': {_uid: _name},
      'admins': {_uid: true},
      'privacy': 'members',
      'createdAt': ServerValue.timestamp,
    });
    _groupName.clear();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _createStatus() async {
    final text = _statusText.text.trim();
    if (text.isEmpty && _statusMedia == null || _uid.isEmpty) return;
    final data = <String, dynamic>{
      'text': text,
      'senderId': _uid,
      'senderName': _name,
      'privacy': _statusPrivacy,
      'createdAt': ServerValue.timestamp,
      'expiresAt': DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch,
    };
    if (_statusMedia != null) {
      final bytes = await _statusMedia!.readAsBytes();
      if (bytes.length > 6 * 1024 * 1024) return;
      data['mediaType'] = _statusVideo ? 'video' : 'image';
      data['mediaBase64'] = base64Encode(bytes);
    }
    await FirebaseDatabase.instance.ref('statuses').push().set(data);
    _statusText.clear();
    _statusMedia = null;
    _statusVideo = false;
    _statusPrivacy = 'all';
    if (mounted) Navigator.pop(context);
  }

  Future<void> _startGroupCall(String type, String groupId) async {
    if (_uid.isEmpty) return;
    final callId = await CallService.createCall(
      callerId: _uid,
      callerName: _name,
      type: type,
      groupId: groupId,
    );
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => CallScreen(
      callId: callId,
      uid: _uid,
      caller: true,
      type: type,
    )));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('الجروبات والحالات'),
          backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
          bottom: TabBar(
            controller: _tabs,
            tabs: const [Tab(text: 'الجروبات'), Tab(text: 'الحالة')],
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          children: [_groups(), _statuses()],
        ),
      );

  Widget _groups() => StreamBuilder<DatabaseEvent>(
        stream: FirebaseDatabase.instance.ref('groups').onValue,
        builder: (_, snapshot) {
          final values = <Map<String, dynamic>>[];
          final raw = snapshot.data?.snapshot.value;
          if (raw is Map) {
            raw.forEach((id, value) {
              if (value is Map) {
                final group = Map<String, dynamic>.from(value);
                group['id'] = id.toString();
                final members = group['members'];
                if (members is! Map || members.containsKey(_uid)) values.add(group);
              }
            });
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              FilledButton.icon(
                onPressed: _showCreateGroup,
                icon: const Icon(Icons.group_add),
                label: const Text('إنشاء جروب'),
              ),
              ...values.map((group) => Card(
                    child: ListTile(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GroupChatScreen(groupId: group['id'].toString(), groupName: group['name']?.toString() ?? 'جروب'))),
                      leading: const CircleAvatar(child: Icon(Icons.groups)),
                      title: Text(group['name']?.toString() ?? 'جروب'),
                      subtitle: Text('بواسطة ${group['ownerName'] ?? ''}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(onPressed: () => _startGroupCall('audio', group['id'].toString()), icon: const Icon(Icons.call, color: Color(0xFFE85C5C))),
                        IconButton(onPressed: () => _startGroupCall('video', group['id'].toString()), icon: const Icon(Icons.videocam, color: Color(0xFFE85C5C))),
                      ]),
                    ),
                  )),
            ],
          );
        },
      );

  Widget _statuses() => StreamBuilder<DatabaseEvent>(
        stream: FirebaseDatabase.instance.ref('statuses').onValue,
        builder: (_, snapshot) {
          final values = <Map<String, dynamic>>[];
          final raw = snapshot.data?.snapshot.value;
          if (raw is Map) {
            raw.forEach((_, value) {
              if (value is Map) {
                final status = Map<String, dynamic>.from(value);
                final expiresAt = (status['expiresAt'] as num?)?.toInt() ?? 0;
                final privacy = status['privacy']?.toString() ?? 'all';
                final visible = privacy != 'only_me' || status['senderId']?.toString() == _uid;
                if (visible && (expiresAt == 0 || expiresAt > DateTime.now().millisecondsSinceEpoch)) {
                  values.add(status);
                }
              }
            });
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              FilledButton.icon(
                onPressed: _showCreateStatus,
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('إضافة حالة'),
              ),
              ...values.reversed.map((status) => Card(
                    child: ListTile(
                      onTap: () {
                        final media = status['mediaBase64']?.toString() ?? '';
                        if (media.isEmpty) return;
                        showDialog<void>(context: context, builder: (_) => Dialog(
                          backgroundColor: Colors.black,
                          child: status['mediaType'] == 'video'
                              ? VideoMessageWidget(id: 'status_${status['createdAt']}', base64: media, mine: false)
                              : InteractiveViewer(child: Image.memory(base64Decode(media), fit: BoxFit.contain)),
                        ));
                      },
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(status['senderName']?.toString() ?? ''),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(status['text']?.toString() ?? ''),
                        if (status['mediaType'] == 'image' && status['mediaBase64'] != null)
                          Padding(padding: const EdgeInsets.only(top: 8), child: Image.memory(base64Decode(status['mediaBase64'].toString()), height: 140, width: double.infinity, fit: BoxFit.cover)),
                        if (status['mediaType'] == 'video') const Padding(padding: EdgeInsets.only(top: 8), child: Icon(Icons.videocam, color: Color(0xFFE85C5C))),
                      ]),
                    ),
                  )),
            ],
          );
        },
      );

  void _showCreateGroup() => showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('إنشاء جروب'),
          content: TextField(controller: _groupName, decoration: const InputDecoration(hintText: 'اسم الجروب')),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')), FilledButton(onPressed: _createGroup, child: const Text('إنشاء'))],
        ),
      );

  void _showCreateStatus() => showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('حالة جديدة'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: _statusText, maxLines: 4, decoration: const InputDecoration(hintText: 'اكتب حالتك')),
            Row(children: [
              IconButton(onPressed: () async { final f = await _picker.pickImage(source: ImageSource.gallery); if (f != null) setState(() { _statusMedia = f; _statusVideo = false; }); }, icon: const Icon(Icons.image_outlined)),
              IconButton(onPressed: () async { final f = await _picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 1)); if (f != null) setState(() { _statusMedia = f; _statusVideo = true; }); }, icon: const Icon(Icons.videocam_outlined)),
              if (_statusMedia != null) Expanded(child: Text(_statusMedia!.name, overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 12),
            StatefulBuilder(builder: (context, setDialogState) => DropdownButtonFormField<String>(
              value: _statusPrivacy,
              decoration: const InputDecoration(labelText: 'خصوصية الحالة'),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('الجميع')),
                DropdownMenuItem(value: 'contacts', child: Text('جهات الاتصال')),
                DropdownMenuItem(value: 'only_me', child: Text('أنا فقط')),
              ],
              onChanged: (value) {
                if (value != null) setDialogState(() => _statusPrivacy = value);
              },
            )),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')), FilledButton(onPressed: _createStatus, child: const Text('نشر'))],
        ),
      );
}
