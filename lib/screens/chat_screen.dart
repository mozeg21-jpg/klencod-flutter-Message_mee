import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/notification_service.dart';
import 'community_features_screen.dart';
import 'contacts_screen.dart';
import 'call_screen.dart';
import '../utils/call_service.dart';
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
  final ImagePicker _picker = ImagePicker();
  final List<Map<String, dynamic>> _messages = [];
  StreamSubscription<DatabaseEvent>? _subscription;
  StreamSubscription<DatabaseEvent>? _incomingCallSubscription;
  final Set<String> _shownCalls = {};
  StreamSubscription<RecordingDisposition>? _recordingSubscription;
  Map<String, dynamic>? _reply;
  String _uid = '', _name = '', _username = '';
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
  // حدود حجم الوسائط (Base64 يزيد الحجم ~33% فلذلك نحافظ على ملفات صغيرة)
  static const int _maxImageBytes = 4 * 1024 * 1024; // 4 ميجا للصورة
  // Base64 يزيد الحجم تقريبًا 33%، وRealtime Database لا يناسب ملفات كبيرة.
  // 6MB خام ≈ 8MB Base64 حتى لا يفشل الحفظ أو التشغيل.
  static const int _maxVideoBytes = 6 * 1024 * 1024;
  static const List<String> kReactionEmojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
  final Set<String> _notified = {};
  bool _initialLoad = true;

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
    _username = p.getString('username') ?? '';
    try {
      await _recorder.openRecorder();
      await _recorder.setSubscriptionDuration(const Duration(milliseconds: 100));
      _recorderReady = true;
    } catch (_) {}
    try {
      await NotificationService.init();
      // أندرويد 13+ يعرض نافذة إذن الإشعارات عند دخول المحادثة.
      // لا نكتم النتيجة حتى يظل سلوك الإذن واضحًا للمستخدم.
      final notificationsAllowed = await NotificationService.requestPermission();
      if (!notificationsAllowed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فعّل إذن الإشعارات من إعدادات التطبيق لاستقبال التنبيهات')),
        );
      }
    } catch (_) {}
    try {
      _subscription = FirebaseDatabase.instance.ref('messages').limitToLast(100).onValue.listen(_readMessages);
      _incomingCallSubscription = FirebaseDatabase.instance.ref('calls')
          .orderByChild('targetId').equalTo(_uid).onChildAdded.listen(_incomingCall);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _incomingCall(DatabaseEvent event) async {
    final id = event.snapshot.key;
    final raw = event.snapshot.value;
    if (id == null || raw is! Map || _shownCalls.contains(id)) return;
    final data = Map<String, dynamic>.from(raw);
    if (data['status'] != 'ringing') return;
    _shownCalls.add(id);
    if (!mounted) return;
    final accept = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(data['type'] == 'video' ? 'مكالمة فيديو واردة' : 'مكالمة صوتية واردة'),
        content: Text('من ${data['callerName'] ?? 'مستخدم'}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('رفض')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('قبول')),
        ],
      ),
    );
    if (!mounted) return;
    if (accept == true) {
      await CallService.updateStatus(id, 'accepted');
      Navigator.push(context, MaterialPageRoute(builder: (_) => CallScreen(callId: id, uid: _uid, caller: false, type: data['type']?.toString() ?? 'audio')));
    } else {
      await CallService.updateStatus(id, 'declined');
    }
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
    // أول تحميل: نسجل الرسالة القديمة كلها من غير إشعارات؛ الجديد بعدها بس يُنوّه عنه
    if (_initialLoad) {
      _initialLoad = false;
      for (final m in list) {
        _notified.add(m['id'].toString());
      }
    } else {
      for (final m in list) {
        final id = m['id'].toString();
        if (_notified.contains(id)) continue;
        _notified.add(id);
        if (m['senderId'] != _uid) _notifyIncoming(m);
      }
    }
    if (mounted) {
      setState(() {
        _messages
          ..clear()
          ..addAll(list);
      });
    }
  }

  /// إشعار محلي برسالة واردة (نص/صوت/صورة/فيديو) مع تمييز الردود.
  Future<void> _notifyIncoming(Map<String, dynamic> m) async {
    final name = (m['senderName'] ?? 'مستخدم').toString();
    final reply = m['replyTo'] as Map?;
    final prefix = reply != null ? 'رد على ${reply['name'] ?? ''}: ' : '';
    final type = (m['mediaType'] ?? '').toString();
    String body;
    if (type == 'image') {
      body = '${prefix}صورة';
    } else if (type == 'video') {
      body = '${prefix}فيديو';
    } else if ((m['audioBase64'] ?? '').toString().isNotEmpty) {
      body = '${prefix}تسجيل صوتي';
    } else {
      body = '$prefix${(m['text'] ?? '').toString()}';
    }
    await NotificationService.show(title: name, body: body, id: m['id'].toString().hashCode);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _incomingCallSubscription?.cancel();
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

  /// نص معاينة مختصر للرسالة التي يتم الرد عليها (نص/صوت/صورة/فيديو).
  String _replyPreview(Map<String, dynamic> m) {
    final type = (m['mediaType'] ?? '').toString();
    if (type == 'image') return 'صورة';
    if (type == 'video') return 'فيديو';
    if ((m['audioBase64'] ?? '').toString().isNotEmpty) return 'تسجيل صوتي';
    final t = (m['text'] ?? '').toString();
    return t.isEmpty ? 'رسالة' : t;
  }

  Map<String, dynamic> _replyPayload() {
    final r = _reply!;
    return {
      'id': r['id'] ?? '',
      'name': r['senderName'] ?? '',
      'text': _replyPreview(r),
    };
  }

  /// إضافة/إزالة تفاعل رمز تعبيري على رسالة (مخزن في messages/$id/reactions/$uid).
  Future<void> _react(Map<String, dynamic> m, String emoji) async {
    final id = m['id'].toString();
    final key = _reactionKey(_uid);
    final ref = FirebaseDatabase.instance.ref('messages/$id/reactions');
    try {
      // اقرأ القيمة الحالية من Firebase بدل الاعتماد على نسخة الرسالة
      // القديمة الموجودة في الواجهة.
      final safeSnapshot = await ref.child(key).get();
      final legacySnapshot = key == _uid ? null : await ref.child(_uid).get();
      final current = safeSnapshot.exists
          ? safeSnapshot.value?.toString()
          : legacySnapshot?.exists == true
              ? legacySnapshot?.value?.toString()
              : null;
      if (current == emoji) {
        await ref.child(key).remove();
        if (key != _uid) await ref.child(_uid).remove();
      } else {
        await ref.child(key).set(emoji);
      }
    } catch (e) {
      _toast('تعذر تعديل التفاعل: ${_shortError(e)}');
    }
  }

  // Realtime Database يمنع هذه الرموز داخل أسماء العقد.
  String _reactionKey(String value) => value
      .replaceAll('.', '_dot_')
      .replaceAll('#', '_hash_')
      .replaceAll('\$', '_dollar_')
      .replaceAll('[', '_left_')
      .replaceAll(']', '_right_')
      .replaceAll('/', '_slash_');

  /// Sheet يظهر بالضغط المطول: صف رموز التفاعل + رد + نسخ النص.
  Future<void> _openMessageActions(Map<String, dynamic> m) async {
    final hasText = (m['text'] ?? '').toString().trim().isNotEmpty;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            for (final e in kReactionEmojis)
              GestureDetector(
                onTap: () {
                  _react(m, e);
                  Navigator.pop(sheetCtx);
                },
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text(e, style: const TextStyle(fontSize: 28)),
                ),
              ),
          ]),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.reply, color: Color(0xFFE85C5C)),
            title: const Text('رد على الرسالة', textDirection: TextDirection.rtl),
            onTap: () {
              Navigator.pop(sheetCtx);
              _replyTo(m);
            },
          ),
          if (hasText)
            ListTile(
              leading: const Icon(Icons.copy, color: Color(0xFFE85C5C)),
              title: const Text('نسخ النص', textDirection: TextDirection.rtl),
              onTap: () {
                Clipboard.setData(ClipboardData(text: m['text'].toString()));
                Navigator.pop(sheetCtx);
                _toast('تم نسخ الرسالة');
              },
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
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
    if (_reply != null) data['replyTo'] = _replyPayload();
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

  /// اختيار صورة أو فيديو من المعرض ثم إرسالهما بنفس فكرة الصوت:
  /// الملف يُقرأ بايتات → يحوَّل Base64 → يُحفظ نصًا في Realtime Database (بدون Firebase Storage).
  Future<void> _pickMedia({required bool isVideo}) async {
    if (_uid.trim().isEmpty || _name.trim().isEmpty) {
      _toast('بيانات الحساب غير جاهزة، أعد تسجيل الدخول');
      return;
    }
    if (_sending) return;
    try {
      final XFile? file = isVideo
          ? await _picker.pickVideo(
              source: ImageSource.gallery,
              maxDuration: const Duration(minutes: 3),
            )
          : await _picker.pickImage(
              source: ImageSource.gallery,
              maxWidth: 1280,
              imageQuality: 70,
            );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final limit = isVideo ? _maxVideoBytes : _maxImageBytes;
      if (bytes.lengthInBytes > limit) {
        _toast(isVideo
            ? 'الفيديو كبير جدًا، اختر فيديو أقل من 6 ميجا'
            : 'الصورة كبيرة جدًا، اختر صورة أقل من 4 ميجا');
        return;
      }
      setState(() => _sending = true);
      final data = <String, dynamic>{
        'mediaType': isVideo ? 'video' : 'image',
        'mediaBase64': base64Encode(bytes),
        'mediaName': file.name,
        'mediaSize': bytes.lengthInBytes,
        'senderId': _uid,
        'senderName': _name.trim(),
        'time': ServerValue.timestamp,
      };
      if (_reply != null) data['replyTo'] = _replyPayload();
      await FirebaseDatabase.instance.ref('messages').push().set(data);
      if (mounted) setState(() => _reply = null);
    } catch (e) {
      _toast('تعذر إرسال الوسائط: ${_shortError(e)}');
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
      await _recorder.startRecorder(
        toFile: path,
        codec: Codec.aacMP4,
        audioSource: AudioSource.microphone,
        sampleRate: 44100,
        bitRate: 128000,
      );
      _levels.clear();
      _seconds = 0;
      _recording = true;
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _seconds++);
      });
      _recordingSubscription = _recorder.onProgress?.listen((d) {
        // القيم الأقل من هذا الحد تعتبر صمتًا ولا ترسم موجة وهمية.
        final db = d.decibels ?? -60;
        final raw = db <= -42 ? 0.02 : ((db + 42) / 42).clamp(0.02, 1.0).toDouble();
        final previous = _levels.isEmpty ? raw : _levels.last;
        final v = previous * 0.55 + raw * 0.45;
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
    if (raw.isEmpty) return List.filled(count, '0.02').join(',');
    if (raw.length <= count) {
      return raw.map((x) => x.toStringAsFixed(2)).join(',') +
          (raw.length < count ? ',${List.filled(count - raw.length, '0.02').join(',')}' : '');
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
      out.add(avg.clamp(.02, 1.0).toStringAsFixed(2));
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
      if (_reply != null) data['replyTo'] = _replyPayload();
      await FirebaseDatabase.instance.ref('messages').push().set(data);
      if (mounted) setState(() => _reply = null);
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
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
          title: const Text('المحادثات', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          actions: [
            IconButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactsScreen())),
              icon: const Icon(Icons.contacts_outlined),
              tooltip: 'جهات الاتصال',
            ),
            IconButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CommunityFeaturesScreen())),
              icon: const Icon(Icons.groups_2_outlined),
              tooltip: 'الجروبات والحالات',
            ),
            IconButton(onPressed: _editProfile, icon: const Icon(Icons.account_circle)),
          ],
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
                      myUid: _uid,
                      onLongPress: () => _openMessageActions(m),
                      onSwipeLeft: () => _replyTo(m),
                      onReact: (e) => _react(m, e),
                    );
                  },
                ),
              ),
              if (_reply != null)
                ListTile(
                  dense: true,
                  title: Text('الرد على ${_reply!['senderName']}', textDirection: TextDirection.rtl),
                  subtitle: Text(
                    _replyPreview(_reply!),
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
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)]),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            _circleAction(Icons.image_outlined, _sending ? null : () => _pickMedia(isVideo: false)),
            _circleAction(Icons.videocam_outlined, _sending ? null : () => _pickMedia(isVideo: true)),
            _micOrSend(),
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

  /// زر دائري بخلفية وردية فاتحة (صورة / فيديو).
  Widget _circleAction(IconData icon, VoidCallback? onTap) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: const Color(0xFFFFECEC),
          shape: const CircleBorder(),
          child: IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
            icon: Icon(icon, color: const Color(0xFFE85C5C), size: 22),
            onPressed: onTap,
          ),
        ),
      );

  /// زر الميكروفون / الإرسال الدائري الأحمر.
  Widget _micOrSend() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: const Color(0xFFE85C5C),
          shape: const CircleBorder(),
          child: IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            icon: _sending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                : Icon(_input.text.trim().isEmpty ? Icons.mic : Icons.send,
                    color: Colors.white, size: 22),
            onPressed: _sending ? null : (_input.text.trim().isEmpty ? _startRecording : _sendText),
          ),
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
    final nameController = TextEditingController(text: _name);
    final usernameController = TextEditingController(text: _username);
    final save = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تعديل الملف الشخصي'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: usernameController, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'Username (@name)')),
          TextField(controller: nameController, textDirection: TextDirection.rtl, decoration: const InputDecoration(labelText: 'اسم الظهور')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (save != true) return;
    final value = nameController.text.trim();
    final username = usernameController.text.trim().toLowerCase();
    if (value.length < 2 || !RegExp(r'^@[a-z0-9_]{3,20}$').hasMatch(username)) {
      _toast('تحقق من اسم الظهور والـ Username');
      return;
    }
    final normalized = username.substring(1);
    final usernameRef = FirebaseDatabase.instance.ref('usernames/$normalized');
    final reserved = await usernameRef.runTransaction((current) {
      if (current == null || current.toString() == _uid) return Transaction.success(_uid);
      return Transaction.abort();
    });
    if (!reserved.committed) {
      _toast('هذا الـ Username مستخدم بالفعل');
      return;
    }
    final p = await SharedPreferences.getInstance();
    await p.setString('name', value);
    await p.setString('username', username);
    setState(() {
      _name = value;
      _username = username;
    });
    try {
      await FirebaseDatabase.instance.ref('users/$_uid').update({'name': value, 'username': username});
    } catch (_) {}
    if (mounted) {
      _toast('تم تحديث الملف الشخصي');
    }
  }
}

/// Live recording waveform: fixed number of rounded bars, newest on the right,
/// idle (small) bars pad the left side until real data fills them.
class _LiveWavePainter extends CustomPainter {
  final List<double> values;
  static const int _bars = 38;
  _LiveWavePainter(this.values);

  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = const Color(0xFFE85C5C)
      ..strokeWidth = 2.5
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
  }

  @override
  bool shouldRepaint(covariant _LiveWavePainter old) => true;
}
