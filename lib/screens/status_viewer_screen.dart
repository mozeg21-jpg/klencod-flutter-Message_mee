import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/video_message_widget.dart';
import '../utils/firebase_paths.dart';

class StatusViewerScreen extends StatefulWidget {
  final List<Map<String, dynamic>> statuses;
  final int initialIndex;
  const StatusViewerScreen({super.key, required this.statuses, required this.initialIndex});
  @override State<StatusViewerScreen> createState() => _StatusViewerScreenState();
}

class _StatusViewerScreenState extends State<StatusViewerScreen> {
  late int _index;
  Timer? _timer;
  double _progress = 0;
  bool _paused = false;
  bool _liked = false;
  final _replyController = TextEditingController();
  @override void initState() { super.initState(); _index = widget.initialIndex; _start(); _markViewed(); _loadLike(); }
  void _start() { _timer?.cancel(); _progress = 0; _timer = Timer.periodic(const Duration(milliseconds: 100), (_) { if (!_paused && mounted) { setState(() => _progress += .1 / 5); if (_progress >= 1) _next(); } }); }
  void _next() { if (_index >= widget.statuses.length - 1) { Navigator.pop(context); return; } setState(() { _index++; _liked = false; }); _start(); _markViewed(); _loadLike(); }
  void _previous() { if (_index == 0) return; setState(() { _index--; _liked = false; }); _start(); _markViewed(); _loadLike(); }
  @override void dispose() { _timer?.cancel(); _replyController.dispose(); super.dispose(); }
  Future<void> _markViewed() async {
    final id = widget.statuses[_index]['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('uid') ?? '';
    final name = prefs.getString('name') ?? '';
    if (uid.isNotEmpty) {
      await FirebaseDatabase.instance.ref('statusViews/${FirebasePaths.safeSegment(id)}/${FirebasePaths.safeSegment(uid)}').set({'name': name, 'time': ServerValue.timestamp});
    }
  }

  Future<void> _loadLike() async {
    final id = widget.statuses[_index]['id']?.toString() ?? '';
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('uid') ?? '';
    if (id.isEmpty || uid.isEmpty) return;
    final snapshot = await FirebaseDatabase.instance.ref('statusLikes/${FirebasePaths.safeSegment(id)}/${FirebasePaths.safeSegment(uid)}').get();
    if (mounted) setState(() => _liked = snapshot.exists);
  }

  Future<void> _toggleLike() async {
    final id = widget.statuses[_index]['id']?.toString() ?? '';
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('uid') ?? '';
    if (id.isEmpty || uid.isEmpty) return;
    final next = !_liked;
    setState(() => _liked = next);
    final ref = FirebaseDatabase.instance.ref('statusLikes/${FirebasePaths.safeSegment(id)}/${FirebasePaths.safeSegment(uid)}');
    if (next) {
      await ref.set({'time': ServerValue.timestamp});
    } else {
      await ref.remove();
    }
  }
  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    final target = widget.statuses[_index]['senderId']?.toString() ?? '';
    if (text.isEmpty || target.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('uid') ?? '';
    final name = prefs.getString('name') ?? '';
    if (uid.isEmpty) return;
    final conversationId = FirebasePaths.conversationId(uid, target);
    await FirebaseDatabase.instance.ref(FirebasePaths.conversation(conversationId)).update({
      'conversationId': conversationId,
      'members': {uid: true, target: true},
      'createdAt': ServerValue.timestamp,
    });
    await FirebaseDatabase.instance.ref(FirebasePaths.conversationMessages(conversationId)).push().set({
      'text': text,
      'senderId': uid,
      'senderName': name,
      'targetId': target,
      'replyToStatus': widget.statuses[_index]['id'],
      'time': ServerValue.timestamp,
      'status': 'sent',
    });
    final preview = 'رد على الحالة';
    await FirebaseDatabase.instance.ref().update({
      '${FirebasePaths.userChats(uid)}/$conversationId/lastMessage': preview,
      '${FirebasePaths.userChats(uid)}/$conversationId/updatedAt': ServerValue.timestamp,
      '${FirebasePaths.userChats(uid)}/$conversationId/peerId': target,
      '${FirebasePaths.userChats(uid)}/$conversationId/name': widget.statuses[_index]['senderName']?.toString() ?? 'مستخدم',
      '${FirebasePaths.userChats(target)}/$conversationId/lastMessage': preview,
      '${FirebasePaths.userChats(target)}/$conversationId/updatedAt': ServerValue.timestamp,
      '${FirebasePaths.userChats(target)}/$conversationId/unread': ServerValue.increment(1),
      '${FirebasePaths.userChats(target)}/$conversationId/peerId': uid,
      '${FirebasePaths.userChats(target)}/$conversationId/name': name,
    });
    _replyController.clear();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال الرد')));
  }
  Future<void> _showViewers() async {
    final id = widget.statuses[_index]['id']?.toString() ?? '';
    final snapshot = id.isEmpty ? null : await FirebaseDatabase.instance.ref('statusViews/${FirebasePaths.safeSegment(id)}').get();
    final names = <String>[];
    if (snapshot?.value is Map) {
      (snapshot!.value as Map).forEach((_, value) { if (value is Map) names.add(value['name']?.toString() ?? 'مستخدم'); });
    }
    if (!mounted) return;
    showModalBottomSheet<void>(context: context, builder: (_) => SafeArea(child: SizedBox(height: 260, child: ListView(children: [const ListTile(title: Text('المشاهدون'), leading: Icon(Icons.visibility)), ...names.map((name) => ListTile(leading: const CircleAvatar(child: Icon(Icons.person)), title: Text(name)))]))));
  }
  @override Widget build(BuildContext context) {
    final status = widget.statuses[_index];
    final media = status['mediaBase64']?.toString() ?? '';
    return Scaffold(backgroundColor: Colors.black, body: SafeArea(child: GestureDetector(
      onLongPress: () => setState(() => _paused = true), onLongPressUp: () => setState(() => _paused = false),
      onTapUp: (details) => details.localPosition.dx < MediaQuery.of(context).size.width / 2 ? _previous() : _next(),
      child: Stack(children: [
        Center(child: media.isEmpty ? Text(status['text']?.toString() ?? '', style: const TextStyle(color: Colors.white, fontSize: 24), textAlign: TextAlign.center) : status['mediaType'] == 'video' ? VideoMessageWidget(id: 'status_${status['createdAt']}', base64: media, mine: false) : Image.memory(base64Decode(media), fit: BoxFit.contain)),
        Positioned(top: 8, left: 8, right: 8, child: LinearProgressIndicator(value: _progress, backgroundColor: Colors.white30, color: Colors.white)),
        Positioned(top: 24, left: 14, right: 14, child: Row(children: [const CircleAvatar(radius: 18, child: Icon(Icons.person)), const SizedBox(width: 8), Expanded(child: Text(status['senderName']?.toString() ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))), IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white))])),
        Positioned(bottom: 18, left: 14, right: 14, child: Row(children: [Expanded(child: TextField(controller: _replyController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'رد على الحالة...', hintStyle: TextStyle(color: Colors.white70), enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white70)), focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white))))), IconButton(onPressed: _sendReply, icon: const Icon(Icons.send, color: Colors.white)), IconButton(onPressed: _showViewers, icon: const Icon(Icons.visibility, color: Colors.white)), FloatingActionButton.small(backgroundColor: _liked ? Colors.red : Colors.white24, onPressed: _toggleLike, child: Icon(_liked ? Icons.favorite : Icons.favorite_border, color: Colors.white))])),
      ]),
    )));
  }
}
