import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceUid {
  static const _key = 'device_uid';

  static Future<String> get() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null && saved.isNotEmpty) {
      final safe = _safeKey(saved);
      if (safe != saved) await prefs.setString(_key, safe);
      return safe;
    }
    final info = DeviceInfoPlugin();
    String value;
    try {
      final android = await info.androidInfo;
      value = 'u_${android.id.isEmpty ? android.fingerprint : android.id}';
    } catch (_) {
      value = 'u_${DateTime.now().microsecondsSinceEpoch}';
    }
    value = _safeKey(value);
    await prefs.setString(_key, value);
    return value;
  }

  // Firebase يمنع . # $ [ ] / داخل أسماء العقد.
  static String _safeKey(String value) => value
      .replaceAll('.', '_dot_')
      .replaceAll('#', '_hash_')
      .replaceAll('\$', '_dollar_')
      .replaceAll('[', '_left_')
      .replaceAll(']', '_right_')
      .replaceAll('/', '_slash_');
}
