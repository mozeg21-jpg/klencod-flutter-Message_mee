import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/device_uid.dart';
import 'chat_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _phone = TextEditingController();
  final _picker = ImagePicker();
  String _uid = '...';
  String? _photoBase64;
  bool _busy = false;

  @override
  void initState() { super.initState(); _loadUid(); }
  Future<void> _loadUid() async { try { final id = await DeviceUid.get(); if (mounted) setState(() => _uid = id); } catch (_) {} }
  @override
  void dispose() { _username.dispose(); _displayName.dispose(); _phone.dispose(); super.dispose(); }

  Future<void> _pickProfilePhoto() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 75,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (bytes.length > 700 * 1024) {
        _toast('اختر صورة أصغر من 700 كيلوبايت');
        return;
      }
      if (mounted) setState(() => _photoBase64 = base64Encode(bytes));
    } catch (e) {
      _toast('تعذر اختيار صورة الملف الشخصي');
    }
  }

  Future<void> _continue() async {
    final username = _username.text.trim().toLowerCase();
    final displayName = _displayName.text.trim();
    final phone = _phone.text.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    final valid = RegExp(r'^@[a-z0-9_]{3,20}$').hasMatch(username);
    if (!valid) {
      _toast('اكتب يوزر صحيح مثل @ajdd1 (حروف إنجليزية وأرقام فقط)');
      return;
    }
    if (displayName.length < 2 || displayName.length > 30) {
      _toast('اكتب اسم الظهور من حرفين إلى 30 حرفًا');
      return;
    }
    if (!RegExp(r'^\+?[0-9]{7,15}$').hasMatch(phone)) {
      _toast('اكتب رقم هاتف صحيحًا من 7 إلى 15 رقمًا');
      return;
    }
    if (_uid == '...' || _uid.trim().isEmpty) {
      _toast('انتظر لحظة حتى يجهز معرف الجهاز');
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final normalized = username.substring(1);
      final usernameRef = FirebaseDatabase.instance.ref('usernames/$normalized');
      final result = await usernameRef.runTransaction((current) {
        if (current == null) return Transaction.success(_uid);
        if (current.toString() == _uid) return Transaction.success(_uid);
        return Transaction.abort();
      });
      if (!result.committed) {
        _toast('هذا اليوزر مستخدم بالفعل');
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('uid', _uid);
      await prefs.setString('name', displayName);
      await prefs.setString('username', username);
      await prefs.setString('phone', phone);
      if (_photoBase64 != null) await prefs.setString('photoBase64', _photoBase64!);
      await prefs.setBool('show_id', false);
      await FirebaseDatabase.instance.ref('users/$_uid').update({
        'name': displayName,
        'username': username,
        'phone': phone,
        'showId': false,
        'createdAt': ServerValue.timestamp,
        if (_photoBase64 != null) 'photoBase64': _photoBase64,
      });
    } catch (e) {
      _toast('تعذر حفظ اليوزر: $e');
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ChatScreen()));
  }

  void _toast(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text, textDirection: TextDirection.rtl)));

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFFFF8F8),
        body: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 35, 24, 72),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [Color(0xFFF27878), Color(0xFFE85C5C)]),
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(40)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 82,
                        height: 82,
                        decoration: BoxDecoration(
                          color: const Color(0xFF111111),
                          borderRadius: BorderRadius.circular(23),
                        ),
                        child: const Center(
                          child: Text('A', style: TextStyle(color: Color(0xFFFF7B7B), fontSize: 46, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Welcome to Ahmed Saad Community',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF111111), fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                Transform.translate(
                  offset: const Offset(0, -36),
                  child: Card(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    elevation: 8,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          GestureDetector(
                            onTap: _pickProfilePhoto,
                            child: CircleAvatar(
                              radius: 42,
                              backgroundColor: const Color(0xFF111111),
                              backgroundImage: _photoBase64 == null
                                  ? null
                                  : MemoryImage(base64Decode(_photoBase64!)),
                              child: _photoBase64 == null
                                  ? const Icon(Icons.add_a_photo, color: Colors.white, size: 28)
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text('صورة الملف الشخصي', textDirection: TextDirection.rtl),
                          const SizedBox(height: 16),
                          _label('Username'),
                          TextField(
                            controller: _username,
                            maxLength: 21,
                            textDirection: TextDirection.ltr,
                            decoration: _decoration('@ajdd1'),
                          ),
                          const SizedBox(height: 16),
                          _label('اسم الظهور'),
                          TextField(
                            controller: _displayName,
                            maxLength: 30,
                            textDirection: TextDirection.rtl,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _continue(),
                            decoration: _decoration('اكتب اسمك الذي سيظهر للناس'),
                          ),
                          const SizedBox(height: 16),
                          _label('رقم الهاتف'),
                          TextField(
                            controller: _phone,
                            keyboardType: TextInputType.phone,
                            textDirection: TextDirection.ltr,
                            maxLength: 16,
                            decoration: _decoration('+201xxxxxxxxx'),
                          ),
                          const Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              'استخدم @ ثم حروف إنجليزية أو أرقام أو _ فقط',
                              textDirection: TextDirection.rtl,
                              style: TextStyle(color: Color(0xFF9A8A8A), fontSize: 12),
                            ),
                          ),
                          const SizedBox(height: 22),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _busy ? null : _continue,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF111111),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                              ),
                              child: Text(_busy ? 'جاري الحفظ...' : 'Continue'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _label(String text) => Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            text,
            textDirection: TextDirection.rtl,
            style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5A4A4A)),
          ),
        ),
      );

  InputDecoration _decoration([String? hint]) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFFFF1F1),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFF3C9C9)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFF3C9C9)),
        ),
      );
}
