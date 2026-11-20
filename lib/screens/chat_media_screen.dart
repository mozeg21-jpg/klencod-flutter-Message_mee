import 'dart:convert';
import 'dart:io';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/firebase_paths.dart';
import '../widgets/audio_player_widget.dart';
import '../widgets/video_message_widget.dart';

class ChatMediaScreen extends StatelessWidget {
  final String conversationId;
  const ChatMediaScreen({super.key, required this.conversationId});

  Future<List<Map<String, dynamic>>> _load() async {
    final snapshot = await FirebaseDatabase.instance
        .ref(FirebasePaths.conversationMessages(conversationId))
        .get();
    final result = <Map<String, dynamic>>[];
    final value = snapshot.value;
    if (value is Map) {
      value.forEach((key, raw) {
        if (raw is Map) {
          final item = Map<String, dynamic>.from(raw);
          item['id'] = key.toString();
          result.add(item);
        }
      });
    }
    result.sort((a, b) => ((b['time'] as num?) ?? 0).compareTo((a['time'] as num?) ?? 0));
    return result;
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 5,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('الوسائط والروابط والمستندات'),
            bottom: const TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'الكل'),
                Tab(text: 'صور وفيديو'),
                Tab(text: 'صوت'),
                Tab(text: 'مستندات'),
                Tab(text: 'روابط'),
              ],
            ),
          ),
          body: FutureBuilder<List<Map<String, dynamic>>>(
            future: _load(),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              if (snapshot.hasError) return Center(child: Text('تعذر تحميل الوسائط: ${snapshot.error}'));
              final messages = snapshot.data ?? const <Map<String, dynamic>>[];
              return TabBarView(children: [
                _MediaList(messages: messages, filter: _MediaFilter.all),
                _MediaList(messages: messages, filter: _MediaFilter.media),
                _MediaList(messages: messages, filter: _MediaFilter.audio),
                _MediaList(messages: messages, filter: _MediaFilter.documents),
                _MediaList(messages: messages, filter: _MediaFilter.links),
              ]);
            },
          ),
        ),
      );
}

enum _MediaFilter { all, media, audio, documents, links }

class _MediaList extends StatelessWidget {
  final List<Map<String, dynamic>> messages;
  final _MediaFilter filter;
  const _MediaList({required this.messages, required this.filter});

  List<Map<String, dynamic>> get _items => messages.where((message) {
        final mediaType = message['mediaType']?.toString() ?? '';
        final hasAudio = (message['audioBase64']?.toString() ?? '').isNotEmpty;
        final isDocument = message['type'] == 'document';
        final text = message['text']?.toString() ?? '';
        final hasLink = RegExp(r'https?://[^\s]+', caseSensitive: false).hasMatch(text);
        switch (filter) {
          case _MediaFilter.all:
            return mediaType.isNotEmpty || hasAudio || isDocument || hasLink;
          case _MediaFilter.media:
            return mediaType == 'image' || mediaType == 'video' || mediaType == 'sticker' || mediaType == 'gif';
          case _MediaFilter.audio:
            return hasAudio;
          case _MediaFilter.documents:
            return isDocument;
          case _MediaFilter.links:
            return hasLink;
        }
      }).toList();

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items.isEmpty) return const Center(child: Text('لا توجد عناصر بعد'));
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _item(context, items[index]),
    );
  }

  Widget _item(BuildContext context, Map<String, dynamic> message) {
    final mediaType = message['mediaType']?.toString() ?? '';
    final encoded = message['mediaBase64']?.toString() ?? '';
    if ((mediaType == 'image' || mediaType == 'sticker' || mediaType == 'gif') && encoded.isNotEmpty) {
      return GestureDetector(
        onTap: () => showDialog<void>(context: context, builder: (_) => Dialog(child: InteractiveViewer(child: Image.memory(base64Decode(encoded), fit: BoxFit.contain)))),
        child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(base64Decode(encoded), height: 180, width: double.infinity, fit: BoxFit.cover)),
      );
    }
    if (mediaType == 'video' && encoded.isNotEmpty) {
      return SizedBox(height: 220, child: VideoMessageWidget(id: message['id'].toString(), base64: encoded, mine: false));
    }
    if ((message['audioBase64']?.toString() ?? '').isNotEmpty) {
      return Card(child: Padding(padding: const EdgeInsets.all(8), child: AudioPlayerWidget(
        id: message['id'].toString(),
        base64Audio: message['audioBase64'].toString(),
        waveform: message['waveform']?.toString() ?? '',
        duration: (message['audioDuration'] as num?)?.toInt() ?? 0,
        color: Theme.of(context).colorScheme.primary,
      )));
    }
    if (message['type'] == 'document') {
      final fileName = message['fileName']?.toString() ?? 'مستند';
      final encodedFile = message['fileBase64']?.toString() ?? '';
      return ListTile(
        leading: const Icon(Icons.insert_drive_file),
        title: Text(fileName),
        subtitle: Text('${message['fileSize'] ?? 0} بايت'),
        trailing: encodedFile.isEmpty ? null : const Icon(Icons.open_in_new),
        onTap: encodedFile.isEmpty ? null : () => _openDocument(context, fileName, encodedFile),
      );
    }
    final text = message['text']?.toString() ?? '';
    final match = RegExp(r'https?://[^\s]+', caseSensitive: false).firstMatch(text);
    final link = match?.group(0);
    return ListTile(
      leading: const Icon(Icons.link),
      title: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: link == null ? null : Text(link, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: link == null ? null : () => _openLink(context, link),
    );
  }

  Future<void> _openLink(BuildContext context, String value) async {
    final uri = Uri.tryParse(value);
    if (uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر فتح الرابط')));
  }

  Future<void> _openDocument(BuildContext context, String fileName, String encoded) async {
    try {
      final bytes = base64Decode(encoded);
      final directory = await getTemporaryDirectory();
      final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final file = File('${directory.path}/message_mee_$safeName');
      await file.writeAsBytes(bytes, flush: true);
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
      }
    } catch (_) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر فتح المستند')));
    }
  }
}
