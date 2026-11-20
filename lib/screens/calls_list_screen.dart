import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CallsListScreen extends StatefulWidget {
  const CallsListScreen({super.key});
  @override State<CallsListScreen> createState() => _CallsListScreenState();
}

class _CallsListScreenState extends State<CallsListScreen> {
  String _uid = '';
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { final p = await SharedPreferences.getInstance(); if (mounted) setState(() => _uid = p.getString('uid') ?? ''); }
  Future<int> _duration(String callId) async {
    final snapshot = await FirebaseDatabase.instance.ref('callSummaries/$callId').get();
    final value = snapshot.value;
    if (value is Map && value['duration'] is num) return (value['duration'] as num).toInt();
    return 0;
  }

  String _durationText(int seconds) => '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('المكالمات')),
    body: _uid.isEmpty ? const Center(child: CircularProgressIndicator()) : StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance.ref('calls').onValue,
      builder: (_, snapshot) {
        final calls = <Map<String, dynamic>>[];
        final raw = snapshot.data?.snapshot.value;
        if (raw is Map) raw.forEach((id, value) { if (value is Map) { final call = Map<String, dynamic>.from(value); final participants = call['participants']; if (call['callerId'] == _uid || call['targetId'] == _uid || participants is Map && participants.containsKey(_uid)) { call['id'] = id.toString(); calls.add(call); } } });
        calls.sort((a, b) => ((b['createdAt'] as num?) ?? 0).compareTo((a['createdAt'] as num?) ?? 0));
        if (calls.isEmpty) return const Center(child: Text('لا يوجد سجل مكالمات'));
        return ListView.builder(itemCount: calls.length, itemBuilder: (_, i) {
          final call = calls[i];
          final outgoing = call['callerId'] == _uid;
          final missed = call['status'] == 'declined' || call['status'] == 'missed';
          final video = call['type'] == 'video';
          return ListTile(
            leading: CircleAvatar(child: Icon(video ? Icons.videocam : Icons.call)),
            title: Text(outgoing ? 'مكالمة صادرة' : 'مكالمة واردة'),
            subtitle: FutureBuilder<int>(
              future: _duration(call['id'].toString()),
              builder: (_, duration) {
                final state = missed ? 'لم يتم الرد' : (call['status']?.toString() ?? 'جارية');
                if (duration.connectionState != ConnectionState.done || (duration.data ?? 0) <= 0) return Text(state);
                return Text('$state • ${_durationText(duration.data!)}');
              },
            ),
            trailing: Icon(missed ? Icons.call_missed : (outgoing ? Icons.call_made : Icons.call_received), color: missed ? Colors.red : Theme.of(context).colorScheme.primary),
          );
        });
      },
    ),
  );
}
