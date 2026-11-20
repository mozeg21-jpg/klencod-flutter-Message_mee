import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'audio_player_widget.dart';
import 'video_message_widget.dart';

class MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool mine;
  final String myUid;
  final VoidCallback onLongPress;
  final VoidCallback onSwipeLeft;
  final void Function(String emoji) onReact;
  final void Function(String option) onPollVote;

  const MessageBubble({
    super.key,
    required this.message,
    required this.mine,
    required this.myUid,
    required this.onLongPress,
    required this.onSwipeLeft,
    required this.onReact,
    required this.onPollVote,
  });

  @override
  Widget build(BuildContext context) {
    final audio = (message['audioBase64'] ?? '').toString();
    final mediaType = (message['mediaType'] ?? '').toString();
    final mediaBase64 = (message['mediaBase64'] ?? '').toString();
    // رسائلي شمال، ورسائل باقي أعضاء الجروب يمين.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = mine
        ? (isDark ? const Color(0xFF005C4B) : const Color(0xFFDCF8C6))
        : (isDark ? const Color(0xFF202C33) : Colors.white);
    final textColor = isDark || mine ? const Color(0xFFE9EDEF) : const Color(0xFF111B21);
    final time = DateTime.fromMillisecondsSinceEpoch(
        (message['time'] is num ? (message['time'] as num).toInt() : DateTime.now().millisecondsSinceEpoch));

    Widget content;
    if (message['deleted'] == true) {
      content = Text('تم حذف هذه الرسالة', textDirection: TextDirection.rtl, style: TextStyle(color: textColor, fontStyle: FontStyle.italic));
    } else if (message['type'] == 'location') {
      content = Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.location_on, color: textColor), const SizedBox(width: 8), Text('موقع جغرافي', style: TextStyle(color: textColor))]);
    } else if (message['type'] == 'contact') {
      content = Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.contact_page, color: textColor), const SizedBox(width: 8), Text(message['contactName']?.toString() ?? 'جهة اتصال', style: TextStyle(color: textColor))]);
    } else if (message['type'] == 'event') {
      final date = DateTime.fromMillisecondsSinceEpoch((message['eventDate'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch);
      content = Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.event, color: textColor), const SizedBox(width: 8), Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(message['eventTitle']?.toString() ?? 'حدث', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)), Text('${date.day}/${date.month}/${date.year}', style: TextStyle(color: textColor, fontSize: 12))])]);
    } else if (message['type'] == 'document') {
      content = Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.insert_drive_file, color: textColor), const SizedBox(width: 8), Flexible(child: Text(message['fileName']?.toString() ?? 'مستند', style: TextStyle(color: textColor)))]);
    } else if (message['type'] == 'poll') {
      content = _PollMessage(message: message, color: textColor, onVote: onPollVote);
    } else if (message['type'] == 'call') {
      final isVideo = message['callType']?.toString() == 'video';
      final seconds = (message['duration'] as num?)?.toInt() ?? 0;
      final minutes = seconds ~/ 60;
      final remaining = seconds % 60;
      content = Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(isVideo ? Icons.videocam : Icons.call, color: textColor),
        const SizedBox(width: 8),
        Text(
          '${isVideo ? 'مكالمة فيديو' : 'مكالمة صوتية'}\n${minutes}:${remaining.toString().padLeft(2, '0')}',
          textDirection: TextDirection.rtl,
          style: TextStyle(color: textColor),
        ),
      ]);
    } else if (audio.isNotEmpty) {
      content = AudioPlayerWidget(
        id: (message['id'] ?? '').toString(),
        base64Audio: audio,
        waveform: (message['waveform'] ?? '').toString(),
        duration: (message['audioDuration'] as num? ?? 0).toInt(),
        color: textColor,
      );
    } else if ((mediaType == 'image' || mediaType == 'sticker' || mediaType == 'gif') && mediaBase64.isNotEmpty) {
      content = _ImageMessage(base64: mediaBase64, mine: mine);
    } else if (mediaType == 'video' && mediaBase64.isNotEmpty) {
      content = VideoMessageWidget(id: (message['id'] ?? 'm').toString(), base64: mediaBase64, mine: mine);
    } else {
      content = Text((message['text'] ?? '').toString(),
          textDirection: TextDirection.rtl, style: TextStyle(color: textColor, fontSize: 15));
    }

    final reactions = (message['reactions'] as Map?) ?? {};
    final counts = <String, int>{};
    reactions.forEach((_, v) {
      final e = v.toString();
      counts[e] = (counts[e] ?? 0) + 1;
    });

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
          opacity: value,
          child: Transform.translate(
              offset: Offset(((mine ? -10 : 10) * (1 - value)).toDouble(), 0), child: child)),
      child: _SwipeToReply(
        onLongPress: onLongPress,
        onSwipeLeft: onSwipeLeft,
        child: Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            padding: content is _ImageMessage || content is VideoMessageWidget
                ? const EdgeInsets.all(5)
                : const EdgeInsets.fromLTRB(12, 8, 12, 6),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: mine
                  ? const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(5),
                      bottomRight: Radius.circular(16))
                  : const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(5)),
              border: mine || isDark ? null : Border.all(color: const Color(0xFFE5E7E9)),
              boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 5, offset: Offset(0, 2))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (!mine && (message['senderName'] ?? '').toString().isNotEmpty)
                Align(
                    alignment: Alignment.centerRight,
                    child: Text(message['senderName'],
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(color: Color(0xFFE85C5C), fontWeight: FontWeight.bold, fontSize: 12))),
              if ((message['replyTo'] as Map?) != null)
                Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: mine ? Colors.white24 : const Color(0xFFFFF1F1),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(((message['replyTo'] as Map)['text'] ?? '').toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.rtl,
                        style: TextStyle(color: textColor, fontSize: 12))),
              content,
              if (counts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _ReactionRow(
                    counts: counts,
                    reactions: reactions,
                    myUid: myUid,
                    mine: mine,
                    onReact: onReact,
                  ),
                ),
              if (message['starred'] == true)
                const Align(alignment: Alignment.centerLeft, child: Icon(Icons.star, color: Colors.amber, size: 14)),
              if (message['pinned'] == true)
                const Align(alignment: Alignment.centerLeft, child: Icon(Icons.push_pin, size: 14)),
              const SizedBox(height: 2),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text('${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(color: mine ? Colors.white70 : Colors.grey, fontSize: 10)),
                if (mine) ...[
                  const SizedBox(width: 4),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
                    child: Icon(
                      (message['status']?.toString() == 'read' || (message['readBy'] is Map && (message['readBy'] as Map).isNotEmpty))
                          ? Icons.done_all
                          : Icons.done,
                      key: ValueKey('${message['status']}_${message['readBy']}'),
                      size: 14,
                      color: (message['status']?.toString() == 'read' || (message['readBy'] is Map && (message['readBy'] as Map).isNotEmpty))
                          ? const Color(0xFF53BDEB)
                          : Colors.white70,
                    ),
                  ),
                ],
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// سحب رسالة ناحية الشمال مثل واتساب: الفقاعة تتحرك مع الإصبع،
/// ويظهر زر الرد قبل تأكيد الحركة.
class _SwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onLongPress;
  final VoidCallback onSwipeLeft;

  const _SwipeToReply({
    required this.child,
    required this.onLongPress,
    required this.onSwipeLeft,
  });

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> {
  static const _maxDrag = 82.0;
  static const _replyThreshold = 52.0;
  double _drag = 0;
  bool _dragging = false;

  void _update(DragUpdateDetails details) {
    final next = _drag + details.delta.dx;
    if (next <= 0) {
      setState(() => _drag = next.clamp(-_maxDrag, 0.0));
    }
  }

  void _finish() {
    final shouldReply = _drag <= -_replyThreshold;
    setState(() {
      _drag = 0;
      _dragging = false;
    });
    if (shouldReply) widget.onSwipeLeft();
  }

  @override
  Widget build(BuildContext context) => Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: _dragging ? Duration.zero : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(_drag, 0, 0),
            child: GestureDetector(
              onLongPress: widget.onLongPress,
              onHorizontalDragStart: (_) => setState(() => _dragging = true),
              onHorizontalDragUpdate: _update,
              onHorizontalDragEnd: (_) => _finish(),
              onHorizontalDragCancel: _finish,
              child: widget.child,
            ),
          ),
          Positioned(
            right: 2,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Center(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 80),
                  opacity: (-_drag / _replyThreshold).clamp(0.0, 1.0),
                  child: const CircleAvatar(
                    radius: 16,
                    backgroundColor: Color(0xFFE85C5C),
                    child: Icon(Icons.reply, color: Colors.white, size: 17),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
}

/// صف رموز التفاعل أسفل الفقاعة؛ الضغط على رمز يضيفه/يزيله للمرسل.
class _ReactionRow extends StatelessWidget {
  final Map<String, int> counts;
  final Map reactions;
  final String myUid;
  final bool mine;
  final void Function(String emoji) onReact;
  const _ReactionRow({
    required this.counts,
    required this.reactions,
    required this.myUid,
    required this.mine,
    required this.onReact,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: counts.entries.map((e) {
        final chosen = reactions[_reactionKey(myUid)] == e.key || reactions[myUid] == e.key;
        return GestureDetector(
          onTap: () => onReact(e.key),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: .72, end: 1),
            duration: const Duration(milliseconds: 320),
            curve: Curves.elasticOut,
            builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
            child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: mine ? Colors.white24 : const Color(0xFFFFECEC),
              borderRadius: BorderRadius.circular(10),
              border: chosen ? Border.all(color: const Color(0xFFE85C5C), width: 1) : null,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(e.key, style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 2),
              Text('${e.value}',
                  style: TextStyle(fontSize: 10, color: mine ? Colors.white70 : Colors.grey)),
            ]),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _PollMessage extends StatelessWidget {
  final Map<String, dynamic> message;
  final Color color;
  final void Function(String option) onVote;
  const _PollMessage({required this.message, required this.color, required this.onVote});

  @override
  Widget build(BuildContext context) {
    final options = message['options'] is List ? (message['options'] as List).map((e) => e.toString()).toList() : <String>[];
    final votes = message['votes'] is Map ? Map<String, dynamic>.from(message['votes']) : <String, dynamic>{};
    final counts = <String, int>{for (final option in options) option: 0};
    for (final vote in votes.values) { final option = vote.toString(); if (counts.containsKey(option)) counts[option] = counts[option]! + 1; }
    final total = counts.values.fold<int>(0, (sum, value) => sum + value);
    return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Text(message['question']?.toString() ?? 'استطلاع', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      ...options.map((option) { final ratio = total == 0 ? 0.0 : counts[option]! / total; return GestureDetector(onTap: () => onVote(option), child: Container(width: 220, margin: const EdgeInsets.only(top: 7), padding: const EdgeInsets.all(8), decoration: BoxDecoration(border: Border.all(color: color.withOpacity(.35)), borderRadius: BorderRadius.circular(10)), child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(option, textDirection: TextDirection.rtl, style: TextStyle(color: color)), const SizedBox(height: 4), TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: ratio), duration: const Duration(milliseconds: 280), builder: (_, value, __) => LinearProgressIndicator(value: value, color: const Color(0xFF25D366), backgroundColor: color.withOpacity(.15)),), Text('${(ratio * 100).round()}%', style: TextStyle(color: color, fontSize: 10))]))); }),
    ]);
  }
}

String _reactionKey(String value) => value
    .replaceAll('.', '_dot_')
    .replaceAll('#', '_hash_')
    .replaceAll('\$', '_dollar_')
    .replaceAll('[', '_left_')
    .replaceAll(']', '_right_')
    .replaceAll('/', '_slash_');

/// صورة داخل فقاعة المحادثة: تفك Base64 مرة واحدة وتخزن النتيجة،
/// وتفتح ملء الشاشة عند الضغط مع إمكانية التكبير.
class _ImageMessage extends StatefulWidget {
  final String base64;
  final bool mine;
  const _ImageMessage({required this.base64, required this.mine});

  @override
  State<_ImageMessage> createState() => _ImageMessageState();
}

class _ImageMessageState extends State<_ImageMessage> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    try {
      var encoded = widget.base64.trim();
      if (encoded.contains(',')) encoded = encoded.split(',').last;
      _bytes = base64Decode(encoded);
    } catch (_) {
      _failed = true;
    }
  }

  void _openFullScreen() {
    final bytes = _bytes;
    if (bytes == null) return;
    Navigator.of(context).push(PageRouteBuilder(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 300),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
      pageBuilder: (_, __, ___) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: Center(
          child: InteractiveViewer(
            minScale: 0.8,
            maxScale: 4,
          child: Hero(tag: 'image_${widget.hashCode}', child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true)),
          ),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_failed || _bytes == null) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Text('تعذر عرض الصورة',
            textDirection: TextDirection.rtl,
            style: TextStyle(fontSize: 13, color: widget.mine ? Colors.white70 : Colors.grey)),
      );
    }
    return GestureDetector(
      onTap: _openFullScreen,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240, maxHeight: 220),
          child: Hero(tag: 'image_${widget.hashCode}', child: Image.memory(_bytes!, fit: BoxFit.cover, gaplessPlayback: true)),
        ),
      ),
    );
  }
}
