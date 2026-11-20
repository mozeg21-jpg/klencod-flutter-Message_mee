import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import '../utils/firebase_paths.dart';

class ChannelsScreen extends StatelessWidget {
  final String uid;
  final String name;
  const ChannelsScreen({super.key, required this.uid, required this.name});

  Future<void> _createChannel(BuildContext context) async {
    final controller = TextEditingController();
    final created = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('قناة جديدة'),
        content: TextField(controller: controller, autofocus: true, maxLength: 80, decoration: const InputDecoration(hintText: 'اسم القناة')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('إنشاء')),
        ],
      ),
    );
    controller.dispose();
    if (created == null || created.isEmpty || uid.isEmpty) return;
    final ref = FirebaseDatabase.instance.ref('channels').push();
    await ref.set({
      'name': created,
      'ownerId': uid,
      'ownerName': name,
      'followers': {uid: true},
      'followersCount': 1,
      'createdAt': ServerValue.timestamp,
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: StreamBuilder<DatabaseEvent>(
          stream: FirebaseDatabase.instance.ref('channels').onValue,
          builder: (context, snapshot) {
            final channels = <Map<String, dynamic>>[];
            final raw = snapshot.data?.snapshot.value;
            if (raw is Map) {
              raw.forEach((id, value) {
                if (value is Map) channels.add({...Map<String, dynamic>.from(value), 'id': id.toString()});
              });
            }
            if (channels.isEmpty) {
              return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.campaign_outlined, size: 64),
                const SizedBox(height: 12),
                const Text('لا توجد قنوات بعد'),
                const SizedBox(height: 16),
                FilledButton.icon(onPressed: () => _createChannel(context), icon: const Icon(Icons.add), label: const Text('إنشاء قناة')),
              ]));
            }
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Align(alignment: AlignmentDirectional.centerStart, child: FilledButton.icon(onPressed: () => _createChannel(context), icon: const Icon(Icons.add), label: const Text('قناة جديدة'))),
                const SizedBox(height: 8),
                ...channels.map((channel) => Card(child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.campaign)),
                  title: Text(channel['name']?.toString() ?? 'قناة'),
                  subtitle: Text('${channel['followersCount'] ?? 0} متابع • ${channel['ownerName'] ?? ''}'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChannelDetailsScreen(channel: channel, uid: uid, name: name))),
                ))),
              ],
            );
          },
        ),
      );
}

class ChannelDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> channel;
  final String uid;
  final String name;
  const ChannelDetailsScreen({super.key, required this.channel, required this.uid, required this.name});

  @override
  State<ChannelDetailsScreen> createState() => _ChannelDetailsScreenState();
}

class _ChannelDetailsScreenState extends State<ChannelDetailsScreen> {
  final _postController = TextEditingController();
  String get _channelId => FirebasePaths.safeSegment(widget.channel['id']?.toString() ?? '');
  bool get _owner => widget.channel['ownerId']?.toString() == widget.uid;

  @override
  void dispose() { _postController.dispose(); super.dispose(); }

  Future<void> _toggleFollow() async {
    if (widget.uid.isEmpty) return;
    final ref = FirebaseDatabase.instance.ref('channels/$_channelId/followers/${FirebasePaths.safeSegment(widget.uid)}');
    final current = await ref.get();
    if (current.exists) {
      await ref.remove();
      await FirebaseDatabase.instance.ref('channels/$_channelId/followersCount').runTransaction((value) => Transaction.success(((value as num?)?.toInt() ?? 1) - 1));
    } else {
      await ref.set(true);
      await FirebaseDatabase.instance.ref('channels/$_channelId/followersCount').runTransaction((value) => Transaction.success(((value as num?)?.toInt() ?? 0) + 1));
    }
    if (mounted) setState(() {});
  }

  Future<void> _publish() async {
    final text = _postController.text.trim();
    if (text.isEmpty || !_owner) return;
    await FirebaseDatabase.instance.ref('channelPosts/$_channelId').push().set({
      'text': text,
      'senderId': widget.uid,
      'senderName': widget.name,
      'createdAt': ServerValue.timestamp,
    });
    _postController.clear();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.channel['name']?.toString() ?? 'القناة')),
        body: Column(children: [
          ListTile(
            leading: const CircleAvatar(radius: 28, child: Icon(Icons.campaign)),
            title: Text(widget.channel['name']?.toString() ?? 'قناة', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${widget.channel['followersCount'] ?? 0} متابع'),
            trailing: OutlinedButton(onPressed: _toggleFollow, child: const Text('متابعة')),
          ),
          const Divider(height: 1),
          Expanded(child: StreamBuilder<DatabaseEvent>(
            stream: FirebaseDatabase.instance.ref('channelPosts/$_channelId').onValue,
            builder: (_, snapshot) {
              final posts = <Map<String, dynamic>>[];
              final raw = snapshot.data?.snapshot.value;
              if (raw is Map) raw.forEach((id, value) { if (value is Map) posts.add({...Map<String, dynamic>.from(value), 'id': id.toString()}); });
              posts.sort((a, b) => ((b['createdAt'] as num?) ?? 0).compareTo((a['createdAt'] as num?) ?? 0));
              if (posts.isEmpty) return const Center(child: Text('لا توجد منشورات بعد'));
              return ListView.builder(padding: const EdgeInsets.all(12), itemCount: posts.length, itemBuilder: (_, index) => Card(child: ListTile(title: Text(posts[index]['text']?.toString() ?? ''), subtitle: Text(posts[index]['senderName']?.toString() ?? ''))));
            },
          )),
          if (_owner) SafeArea(child: Padding(padding: const EdgeInsets.all(8), child: Row(children: [Expanded(child: TextField(controller: _postController, decoration: const InputDecoration(hintText: 'منشور جديد', border: OutlineInputBorder()))), IconButton(onPressed: _publish, icon: const Icon(Icons.send))]))),
        ]),
      );
}
