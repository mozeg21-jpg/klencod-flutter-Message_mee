import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _recorder = FlutterSoundRecorder();
  final List<Map<String, dynamic>> _messages = [];
  StreamSubscription<DatabaseEvent>? _subscription;
  StreamSubscription<RecordingDisposition>? _recordingSubscription;
  Map<String, dynamic>? _reply;
  String _uid = '', _name = '';
  bool _recording = false, _recorderReady = false, _sending = false;
  int _seconds = 0;
  final List<double> _levels = [];
  Timer? _timer;
  Timer? _toastTimer;
  OverlayEntry? _toastEntry;
  late final AnimationController _entryController;
  late final AnimationController _pulseController;

  static const int _maxLiveLevels = 80;
  static const int _storedWaveBars = 40;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _entryController.forward();
    _init();
  }

  Future<void> _init() async {
    final p = await SharedPreferences.getInstance();
    _uid = p.getString('uid') ?? '';
    _name = p.getString('name') ?? '';
    try {
      await _recorder.openRecorder();
      await _recorder.setSubscriptionDuration(const Duration(milliseconds: 100));
      _recorderReady = true;
    } catch (_) {}
    try {
      _subscription = FirebaseDatabase.instance.ref('messages').limitToLast(100).onValue.listen(_readMessages);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  void _readMessages(DatabaseEvent event) {
    final value = event.snapshot.value;
    if (value is! Map) return;
    final list = <Map<String, dynamic>>[];
    value.forEach((key, val) {
      if (val is Map) {
        final m = Map<String, dynamic>.from(val);
        m['id'] = key.toString();
        list.add(m);
      }
    });
    list.sort((a, b) => ((a['time'] as num?) ?? 0).compareTo((b['time'] as num?) ?? 0));
    if (mounted) {
      setState(() {
        _messages
          ..clear()
          ..addAll(list);
      });
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _recordingSubscription?.cancel();
    _timer?.cancel();
    _toastTimer?.cancel();
    _toastEntry?.remove();
    _entryController.dispose();
    _pulseController.dispose();
    _recorder.closeRecorder();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _shortError(Object e) {
    final s = e.toString();
    return s.length > 70 ? '${s.substring(0, 70)}…' : s;
  }

  Future<void> _sendText() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    if (_uid.trim().isEmpty || _name.trim().isEmpty) {
      _toast('بيانات الحساب غير جاهزة، أعد تسجيل الدخول');
      return;
    }
    setState(() => _sending = true);
    final data = <String, dynamic>{
      'text': text,
      'senderId': _uid,
      'senderName': _name.trim(),
      'time': ServerValue.timestamp,
    };
    if (_reply != null) {
      data['replyTo'] = {
        'id': _reply!['id'] ?? '',
        'name': _reply!['senderName'] ?? '',
        'text': _reply!['text'] ?? 'تسجيل صوتي',
      };
    }
    try {
      await FirebaseDatabase.instance.ref('messages').push().set(data);
      _input.clear();
      if (mounted) setState(() => _reply = null);
    } catch (e) {
      _toast('تعذر الإرسال: ${_shortError(e)}');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _startRecording() async {
    if (_uid.trim().isEmpty || _name.trim().isEmpty) {
      _toast('بيانات الحساب غير جاهزة، أعد تسجيل الدخول');
      return;
    }
    if (!_recorderReady || _recording) return;
    try {
      final permission = await Permission.microphone.request();
      if (!permission.isGranted) {
        _toast('اسمح للتطبيق باستخدام الميكروفون أولًا');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/record_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.startRecorder(toFile: path, codec: Codec.aacMP4);
      _levels.clear();
      _seconds = 0;
      _recording = true;
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _seconds++);
      });
      _recordingSubscription = _recorder.onProgress?.listen((d) {
        final db = d.decibels ?? -45;
        final v = ((db + 45) / 45).clamp(.08, 1.0).toDouble();
        if (mounted) {
          setState(() {
            _levels.add(v);
            if (_levels.length > _maxLiveLevels) {
              _levels.removeRange(0, _levels.length - _maxLiveLevels);
            }
          });
        }
      });
      setState(() {});
    } catch (e) {
      _timer?.cancel();
      await _recordingSubscription?.cancel();
      _recordingSubscription = null;
      if (mounted) setState(() => _recording = false);
      _toast('لا يمكن تشغيل الميكروفون: ${_shortError(e)}');
    }
  }

  Future<void> _cancelRecording() async {
    if (!_recording) return;
    try {
      await _recorder.stopRecorder();
    } catch (_) {}
    _timer?.cancel();
    await _recordingSubscription?.cancel();
    _recordingSubscription = null;
    if (mounted) setState(() => _recording = false);
  }

  /// Downsample raw levels into [count] averaged buckets, returned as CSV string.
  String _downsampleWaveform(List<double> raw, int count) {
    if (raw.isEmpty) return List.filled(count, '0.25').join(',');
    if (raw.length <= count) {
      return raw.map((x) => x.toStringAsFixed(2)).join(',') +
          (raw.length < count ? ',${List.filled(count - raw.length, '0.2').join(',')}' : '');
    }
    final bucket = raw.length / count;
    final out = <String>[];
    for (var i = 0; i < count; i++) {
      final start = (i * bucket).floor();
      final end = ((i + 1) * bucket).floor().clamp(start + 1, raw.length);
      var sum = 0.0;
      for (var j = start; j < end; j++) {
        sum += raw[j];
      }
      final avg = sum / (end - start);
      out.add(avg.clamp(.08, 1.0).toStringAsFixed(2));
    }
    return out.join(',');
  }

  Future<void> _stopRecording() async {
    if (!_recording) return;
    try {
      final path = await _recorder.stopRecorder();
      if (path == null) {
        _toast('فشل التسجيل');
        return;
      }
      final file = File(path);
      if (!await file.exists()) {
        _toast('ملف التسجيل غير موجود');
        return;
      }
      final bytes = await file.readAsBytes();
      if (bytes.length < 512) {
        _toast('التسجيل قصير جدًا، حاول مرة أخرى');
        return;
      }
      final data = <String, dynamic>{
        'audioBase64': base64Encode(bytes),
        'audioDuration': _seconds,
        'waveform': _downsampleWaveform(_levels, _storedWaveBars),
        'senderId': _uid,
        'senderName': _name.trim(),
        'time': ServerValue.timestamp,
      };
      await FirebaseDatabase.instance.ref('messages').push().set(data);
    } catch (e) {
      _toast('تعذر إرسال التسجيل: ${_shortError(e)}');
    } finally {
      _timer?.cancel();
      await _recordingSubscription?.cancel();
      _recordingSubscription = null;
      if (mounted) setState(() => _recording = false);
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    _toastTimer?.cancel();
    _toastEntry?.remove();
    final entry = OverlayEntry(
      builder: (overlayContext) => Positioned(
        top: MediaQuery.of(overlayContext).padding.top + 12,
        left: 18,
        right: 18,
        child: SafeArea(
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF292929),
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, 4))],
              ),
              child: Text(
                text,
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
        ),
      ),
    );
    _toastEntry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
    _toastTimer = Timer(const Duration(seconds: 3), () {
      entry.remove();
      if (_toastEntry == entry) _toastEntry = null;
    });
  }

  void _replyTo(Map<String, dynamic> m) => setState(() => _reply = m);

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFFFF8F8),
        appBar: AppBar(
          backgroundColor: const Color(0xFFE85C5C),
          title: const Text('Ahmed Saad Community', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          actions: [IconButton(onPressed: _editProfile, icon: const Icon(Icons.account_circle))],
        ),
        body: FadeTransition(
          opacity: CurvedAnimation(parent: _entryController, curve: Curves.easeOut),
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, .04), end: Offset.zero)
                .animate(CurvedAnimation(parent: _entryController, curve: Curves.easeOutCubic)),
            child: Column(children: [
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  reverse: false,
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) {
                    final m = _messages[i];
                    return MessageBubble(
                      message: m,
                      mine: m['senderId'] == _uid,
                      onReply: () => _replyTo(m),
                    );
                  },
                ),
              ),
              if (_reply != null)
                ListTile(
                  dense: true,
                  title: Text('الرد على ${_reply!['senderName']}', textDirection: TextDirection.rtl),
                  subtitle: Text(
                    '${_reply!['text'] ?? 'تسجيل صوتي'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.rtl,
                  ),
                  trailing: IconButton(
                    onPressed: () => setState(() => _reply = null),
                    icon: const Icon(Icons.close),
                  ),
                ),
              if (_recording) _recordingBar() else _inputBar(),
            ]),
          ),
        ),
      );

  Widget _inputBar() => SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)]),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              icon: Icon(
                _input.text.trim().isEmpty ? Icons.mic : Icons.send,
                color: const Color(0xFFE85C5C),
                size: 26,
              ),
              onPressed: _input.text.trim().isEmpty ? _startRecording : _sendText,
            ),
            Expanded(
              child: TextField(
                controller: _input,
                maxLines: 4,
                minLines: 1,
                textDirection: TextDirection.rtl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'اكتب رسالتك...',
                  hintTextDirection: TextDirection.rtl,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  filled: true,
                  fillColor: const Color(0xFFF5F5F5),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                ),
              ),
            ),
          ]),
        ),
      );

  Widget _recordingBar() => SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)]),
          height: 64,
          child: Row(children: [
            // Cancel button
            GestureDetector(
              onTap: _cancelRecording,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: const Color(0xFFF0F0F0), shape: BoxShape.circle),
                child: const Icon(Icons.delete_outline, color: Color(0xFF777777), size: 20),
              ),
            ),
            const SizedBox(width: 8),
            // Timer badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFFFFEEEE), borderRadius: BorderRadius.circular(10)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (_, __) => Opacity(
                    opacity: .35 + (_pulseController.value * .65),
                    child: const Icon(Icons.circle, color: Color(0xFFE85C5C), size: 10),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${_seconds ~/ 60}:${(_seconds % 60).toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFE85C5C)),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: CustomPaint(
                painter: _LiveWavePainter(_levels),
                size: const Size(double.infinity, 40),
              ),
            ),
            const SizedBox(width: 8),
            // Send (stop & send) button
            GestureDetector(
              onTap: _stopRecording,
              child: Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(color: Color(0xFFE85C5C), shape: BoxShape.circle),
                child: const Icon(Icons.send, color: Colors.white, size: 20),
              ),
            ),
          ]),
        ),
      );

  Future<void> _editProfile() async {
    final c = TextEditingController(text: _name);
    final value = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit name'),
        content: TextField(controller: c, textDirection: TextDirection.rtl),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (value == null || value.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.setString('name', value);
    setState(() => _name = value);
    try {
      await FirebaseDatabase.instance.ref('users/$_uid/name').set(value);
    } catch (_) {}
  }
}

/// Live recording waveform: fixed number of rounded bars, newest on the right,
/// idle (small) bars pad the left side until real data fills them.
class _LiveWavePainter extends CustomPainter {
  final List<double> values;
  static const int _bars = 32;

  _LiveWavePainter(this.values);

  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = const Color(0xFFE85C5C)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final step = s.width / _bars;
    final barW = step * 0.55;

    // Take last up-to-_bars values (newest on right).
    final tail = values.length > _bars ? values.sublist(values.length - _bars) : values;
    final pad = _bars - tail.length;

    for (var i = 0; i < _bars; i++) {
      final double v;
      if (i < pad) {
        // idle placeholder: small gentle wave
        v = 0.12 + 0.05 * ((i * 7) % 5) / 5;
      } else {
        final raw = tail[i - pad];
        // simple 3-point smoothing
        final idx = i - pad;
        var sum = raw;
        var n = 1;
        if (idx > 0) {
          sum += tail[idx - 1];
          n++;
        }
        if (idx < tail.length - 1) {
          sum += tail[idx + 1];
          n++;
        }
        v = (sum / n).clamp(.08, 1.0);
      }
      final h = v * s.height * 0.9;
      final x = i * step + step / 2;
      // fade older bars slightly for depth
      final age = (_bars - 1 - i) / _bars; // 0 = newest
      p.color = Color.lerp(const Color(0xFFE85C5C), const Color(0xFFF5B5B5), age * 0.7)!;
      c.drawLine(Offset(x, s.height / 2 - h / 2), Offset(x, s.height / 2 + h / 2), p);
    }
    // keep strokeWidth for next call
    p.strokeWidth = 3;
  }

  @override
  bool shouldRepaint(covariant _LiveWavePainter old) => true;
}
