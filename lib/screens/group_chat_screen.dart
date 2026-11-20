import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'group_details_screen.dart';
import 'call_screen.dart';
import '../utils/call_service.dart';
import '../widgets/video_message_widget.dart';
import '../widgets/audio_player_widget.dart';

class GroupChatScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  const GroupChatScreen({super.key, required this.groupId, required this.groupName});
  @override State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _picker = ImagePicker();
  final _recorder = FlutterSoundRecorder();
  StreamSubscription<DatabaseEvent>? _subscription;
  StreamSubscription<DatabaseEvent>? _callSubscription;
  final _messages = <Map<String, dynamic>>[];
  final Set<String> _shownCalls = {};
  String _uid = '', _name = '';
  bool _recording = false, _recorderReady = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    _uid = p.getString('uid') ?? '';
    _name = p.getString('name') ?? '';
    try { await _recorder.openRecorder(); _recorderReady = true; } catch (_) {}
    final group = await FirebaseDatabase.instance.ref('groups/${widget.groupId}').get();
    final rawGroup = group.value;
    final members = rawGroup is Map ? rawGroup['members'] : null;
    if (members is Map && !members.containsKey(_uid)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أنت لست عضوًا في هذا الجروب')));
        Navigator.pop(context);
      }
      return;
    }
    _subscription = FirebaseDatabase.instance.ref('groupMessages/${widget.groupId}').limitToLast(100).onValue.listen(_read);
    _callSubscription = FirebaseDatabase.instance.ref('calls').orderByChild('groupId').equalTo(widget.groupId).onChildAdded.listen(_incomingGroupCall);
    if (mounted) setState(() {});
  }

  Future<void> _startGroupCall(String type) async {
    if (_uid.isEmpty) return;
    final callId = await CallService.createCall(callerId: _uid, callerName: _name, type: type, groupId: widget.groupId);
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => CallScreen(callId: callId, uid: _uid, caller: true, type: type, groupId: widget.groupId)));
  }

  Future<void> _incomingGroupCall(DatabaseEvent event) async {
    final id = event.snapshot.key;
    final raw = event.snapshot.value;
    if (id == null || raw is! Map || _shownCalls.contains(id)) return;
    final data = Map<String, dynamic>.from(raw);
    if (data['callerId']?.toString() == _uid || data['status'] != 'ringing') return;
    _shownCalls.add(id);
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(data['type'] == 'video' ? 'مكالمة فيديو جماعية' : 'مكالمة صوتية جماعية'),
        content: Text('من ${data['callerName'] ?? 'عضو في الجروب'}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('رفض')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('قبول')),
        ],
      ),
    );
    if (!mounted) return;
    if (accepted == true) {
      await CallService.addParticipant(id, _uid);
      await CallService.updateStatus(id, 'accepted');
      Navigator.push(context, MaterialPageRoute(builder: (_) => CallScreen(callId: id, uid: _uid, caller: false, type: data['type']?.toString() ?? 'audio')));
    } else {
      await CallService.updateStatus(id, 'declined');
    }
  }

  void _read(DatabaseEvent event) {
    final raw = event.snapshot.value;
    if (raw is! Map) return;
    final next = <Map<String, dynamic>>[];
    raw.forEach((id, value) {
      if (value is Map) { final message = Map<String, dynamic>.from(value); message['id'] = id.toString(); next.add(message); }
    });
    next.sort((a, b) => ((a['time'] as num?) ?? 0).compareTo((b['time'] as num?) ?? 0));
    if (mounted) setState(() { _messages..clear()..addAll(next); });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _uid.isEmpty) return;
    await FirebaseDatabase.instance.ref('groupMessages/${widget.groupId}').push().set({
      'text': text, 'senderId': _uid, 'senderName': _name, 'time': ServerValue.timestamp,
    });
    _input.clear();
  }

  Future<void> _pickMedia(bool video) async {
    final file = video
        ? await _picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 3))
        : await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1280, imageQuality: 70);
    if (file == null || _uid.isEmpty) return;
    final bytes = await file.readAsBytes();
    final max = video ? 6 * 1024 * 1024 : 4 * 1024 * 1024;
    if (bytes.length > max) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(video ? 'الفيديو أكبر من 6 ميجا' : 'الصورة أكبر من 4 ميجا')));
      return;
    }
    await FirebaseDatabase.instance.ref('groupMessages/${widget.groupId}').push().set({
      'mediaType': video ? 'video' : 'image',
      'mediaBase64': base64Encode(bytes),
      'mediaName': file.name,
      'senderId': _uid,
      'senderName': _name,
      'time': ServerValue.timestamp,
    });
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      final path = await _recorder.stopRecorder();
      setState(() => _recording = false);
      if (path == null) return;
      final file = File(path);
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();
      await FirebaseDatabase.instance.ref('groupMessages/${widget.groupId}').push().set({
        'audioBase64': base64Encode(bytes),
        'audioDuration': 0,
        'senderId': _uid,
        'senderName': _name,
        'time': ServerValue.timestamp,
      });
      return;
    }
    final permission = await Permission.microphone.request();
    if (!permission.isGranted) return;
    final dir = await getTemporaryDirectory();
    if (!_recorderReady) {
      try { await _recorder.openRecorder(); _recorderReady = true; } catch (_) { return; }
    }
    await _recorder.startRecorder(toFile: '${dir.path}/group_${DateTime.now().millisecondsSinceEpoch}.m4a', codec: Codec.aacMP4);
    if (mounted) setState(() => _recording = true);
  }

  @override
  void dispose() { _subscription?.cancel(); _callSubscription?.cancel(); _input.dispose(); _scroll.dispose(); _recorder.closeRecorder(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.groupName),
      backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
      actions: [
        IconButton(onPressed: () => _startGroupCall('audio'), icon: const Icon(Icons.call)),
        IconButton(onPressed: () => _startGroupCall('video'), icon: const Icon(Icons.videocam)),
        IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GroupDetailsScreen(groupId: widget.groupId))), icon: const Icon(Icons.info_outline)),
      ],
    ),
    body: Column(children: [
      Expanded(child: ListView.builder(controller: _scroll, padding: const EdgeInsets.all(10), itemCount: _messages.length, itemBuilder: (_, i) {
        final message = _messages[i];
        final mine = message['senderId'] == _uid;
        final type = message['mediaType']?.toString() ?? '';
        final encoded = message['mediaBase64']?.toString() ?? '';
        Widget body = Text(message['text']?.toString() ?? '', style: TextStyle(color: mine ? Colors.white : Theme.of(context).colorScheme.onSurface));
        if (message['type'] == 'call') {
          final videoCall = message['callType']?.toString() == 'video';
          final duration = (message['duration'] as num?)?.toInt() ?? 0;
          body = Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(videoCall ? Icons.videocam : Icons.call, color: mine ? Colors.white : Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text('${videoCall ? 'مكالمة فيديو' : 'مكالمة صوتية'}\n${duration ~/ 60}:${(duration % 60).toString().padLeft(2, '0')}', style: TextStyle(color: mine ? Colors.white : Theme.of(context).colorScheme.onSurface)),
          ]);
        } else if (type == 'image' && encoded.isNotEmpty) {
          body = ConstrainedBox(constraints: const BoxConstraints(maxWidth: 240, maxHeight: 220), child: Image.memory(base64Decode(encoded), fit: BoxFit.cover));
        } else if (type == 'video' && encoded.isNotEmpty) {
          body = VideoMessageWidget(id: message['id']?.toString() ?? 'group', base64: encoded, mine: mine);
        } else if ((message['audioBase64'] ?? '').toString().isNotEmpty) {
          body = AudioPlayerWidget(id: message['id']?.toString() ?? 'group', base64Audio: message['audioBase64'].toString(), waveform: '', duration: 0, color: mine ? Colors.white : const Color(0xFFE85C5C));
        }
        return Align(alignment: mine ? Alignment.centerLeft : Alignment.centerRight, child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4), padding: const EdgeInsets.all(10),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .78),
          decoration: BoxDecoration(color: mine ? Theme.of(context).colorScheme.primary : Theme.of(context).cardColor, borderRadius: BorderRadius.circular(14), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (!mine) Text(message['senderName']?.toString() ?? '', style: const TextStyle(color: Color(0xFFE85C5C), fontSize: 11)),
            body,
          ]),
        ));
      })),
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Row(
            children: [
              IconButton(onPressed: () => _pickMedia(false), icon: const Icon(Icons.image_outlined, color: Color(0xFFE85C5C))),
              IconButton(onPressed: () => _pickMedia(true), icon: const Icon(Icons.videocam_outlined, color: Color(0xFFE85C5C))),
              IconButton(onPressed: _toggleRecording, icon: Icon(_recording ? Icons.stop_circle : Icons.mic, color: const Color(0xFFE85C5C))),
              Expanded(child: TextField(controller: _input, textDirection: TextDirection.rtl, decoration: const InputDecoration(hintText: 'اكتب رسالة...', border: OutlineInputBorder()))),
              IconButton(onPressed: _send, icon: const Icon(Icons.send, color: Color(0xFFE85C5C))),
            ],
          ),
        ),
      ),
    ]),
  );
}
