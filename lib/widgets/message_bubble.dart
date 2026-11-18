import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'audio_player_widget.dart';
import 'video_message_widget.dart';

class MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool mine;
  final String myUid;
  final VoidCallback onLongPress;
  final VoidCallback onSwipeLeft;
  final void Function(String emoji) onReact;

  const MessageBubble({
    super.key,
    required this.message,
    required this.mine,
    required this.myUid,
    required this.onLongPress,
    required this.onSwipeLeft,
    required this.onReact,
  });

  @override
  Widget build(BuildContext context) {
    final audio = (message['audioBase64'] ?? '').toString();
    final mediaType = (message['mediaType'] ?? '').toString();
    final mediaBase64 = (message['mediaBase64'] ?? '').toString();
    // رسائلي شمال، ورسائل باقي أعضاء الجروب يمين.
    final bg = mine ? const Color(0xFFE85C5C) : Colors.white;
    final textColor = mine ? Colors.white : const Color(0xFF111111);
    final time = DateTime.fromMillisecondsSinceEpoch(
        (message['time'] is num ? (message['time'] as num).toInt() : DateTime.now().millisecondsSinceEpoch));

    Widget content;
    if (audio.isNotEmpty) {
      content = AudioPlayerWidget(
        id: (message['id'] ?? '').toString(),
        base64Audio: audio,
        waveform: (message['waveform'] ?? '').toString(),
        duration: (message['audioDuration'] as num? ?? 0).toInt(),
        color: textColor,
      );
    } else if (mediaType == 'image' && mediaBase64.isNotEmpty) {
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
          alignment: mine ? Alignment.centerLeft : Alignment.centerRight,
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
              border: mine ? null : Border.all(color: const Color(0xFFF3C9C9)),
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
              const SizedBox(height: 2),
              Text('${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(color: mine ? Colors.white70 : Colors.grey, fontSize: 10)),
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
        );
      }).toList(),
    );
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
      _bytes = base64Decode(widget.base64);
    } catch (_) {
      _failed = true;
    }
  }

  void _openFullScreen() {
    final bytes = _bytes;
    if (bytes == null) return;
    Navigator.of(context).push(PageRouteBuilder(
      opaque: true,
      pageBuilder: (_, __, ___) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: Center(
          child: InteractiveViewer(
            minScale: 0.8,
            maxScale: 4,
            child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true),
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
          child: Image.memory(_bytes!, fit: BoxFit.cover, gaplessPlayback: true),
        ),
      ),
    );
  }
}
