import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/device_uid.dart';
import '../utils/firebase_paths.dart';
import 'whatsapp_home_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _phone = TextEditingController();
  final _displayName = TextEditingController();
  final _username = TextEditingController();
  final _picker = ImagePicker();
  String _uid = '...';
  String _phoneValue = '';
  String? _photoBase64;
  int _step = 0;
  bool _busy = false;

  @override
  void initState() { super.initState(); _loadUid(); }
  Future<void> _loadUid() async { try { final id = await DeviceUid.get(); if (mounted) setState(() => _uid = id); } catch (_) {} }
  @override
  void dispose() { _phone.dispose(); _displayName.dispose(); _username.dispose(); super.dispose(); }

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
    final phone = _phone.text.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    if (!RegExp(r'^\+?[0-9]{7,15}$').hasMatch(phone)) {
      _toast('اكتب رقم هاتف صحيحًا من 7 إلى 15 رقمًا');
      return;
    }
    if (_uid == '...' || _uid.trim().isEmpty) {
      _toast('انتظر لحظة حتى يجهز معرف الجهاز');
      return;
    }
    if (_step == 0) {
      setState(() {
        _phoneValue = phone;
        _step = 1;
      });
      return;
    }
    final displayName = _displayName.text.trim();
    if (displayName.length < 2) {
      _toast('اكتب اسمك، الاسم إجباري');
      return;
    }
    final username = _username.text.trim().toLowerCase();
    if (!RegExp(r'^@[a-z0-9_]{3,24}$').hasMatch(username)) {
      _toast('اكتب يوزر يبدأ بـ @ ويحتوي حروفًا وأرقامًا و _ فقط');
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final usernameRef = FirebaseDatabase.instance.ref('usernames/${FirebasePaths.safeSegment(username)}');
      final usernameSnapshot = await usernameRef.get();
      if (usernameSnapshot.exists && usernameSnapshot.value.toString() != _uid) {
        _toast('اسم المستخدم مستخدم بالفعل');
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('uid', _uid);
      await prefs.setString('name', displayName);
      await prefs.setString('username', username);
      await prefs.setString('phone', phone);
      if (_photoBase64 != null) await prefs.setString('photoBase64', _photoBase64!);
      await prefs.setBool('show_id', false);
      await FirebaseDatabase.instance.ref(FirebasePaths.user(_uid)).update({
        'name': displayName,
        'username': username,
        'phone': phone,
        'showId': false,
        'createdAt': ServerValue.timestamp,
        if (_photoBase64 != null) 'photoBase64': _photoBase64,
      });
      await usernameRef.set(_uid);
    } catch (e) {
      _toast('تعذر حفظ بيانات الحساب: $e');
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const WhatsappHomeScreen()));
  }

  void _toast(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text, textDirection: TextDirection.rtl)));

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 35, 24, 72),
                  decoration: const BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF128C7E), Color(0xFF075E54)]),
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
                      Text(
                        _step == 0 ? 'Welcome to Ahmed Messenger' : 'جهّز ملفك الشخصي',
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
                          if (_step == 1) ...[
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
                            const Text('صورة الملف الشخصي (اختياري)', textDirection: TextDirection.rtl),
                            const SizedBox(height: 16),
                            _label('اسمك'),
                            TextField(
                              controller: _displayName,
                              textDirection: TextDirection.rtl,
                              textCapitalization: TextCapitalization.words,
                              maxLength: 50,
                              decoration: _decoration('اكتب اسمك'),
                            ),
                            const SizedBox(height: 8),
                            _label('اسم المستخدم'),
                            TextField(
                              controller: _username,
                              textDirection: TextDirection.ltr,
                              maxLength: 25,
                              decoration: _decoration('@username'),
                            ),
                            const Align(
                              alignment: Alignment.centerRight,
                              child: Text('يبدأ بـ @ ومسموح بالحروف والأرقام و _ فقط', textDirection: TextDirection.rtl, style: TextStyle(color: Color(0xFF667781), fontSize: 12)),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text('رقم الهاتف: $_phoneValue', textDirection: TextDirection.ltr, style: const TextStyle(color: Color(0xFF667781))),
                            ),
                          ] else ...[
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
                              'اكتب رقم الهاتف فقط، بدون OTP أو رسالة SMS',
                              textDirection: TextDirection.rtl,
                              style: TextStyle(color: Color(0xFF9A8A8A), fontSize: 12),
                            ),
                            ),
                          ],
                          const SizedBox(height: 22),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _busy ? null : _continue,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(context).colorScheme.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                              ),
                              child: Text(_busy ? 'جاري الحفظ...' : (_step == 0 ? 'التالي' : 'بدء استخدام Messenger')),
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
