/// Centralized Firebase paths. Never interpolate raw user input into a path.
class FirebasePaths {
  static String safeSegment(String value) {
    final cleaned = value.trim().replaceAll(RegExp(r'[.#$\[\]/]'), '_');
    return cleaned.isEmpty ? 'unknown' : cleaned;
  }

  static String conversationId(String firstUid, String secondUid) {
    final ids = [safeSegment(firstUid), safeSegment(secondUid)]..sort();
    return '${ids[0]}__${ids[1]}';
  }

  static String user(String uid) => 'users/${safeSegment(uid)}';
  static String userChats(String uid) => 'userChats/${safeSegment(uid)}';
  static String conversation(String id) => 'conversations/${safeSegment(id)}';
  static String conversationMessages(String id) => '${conversation(id)}/messages';
  static String group(String id) => 'groups/${safeSegment(id)}';
  static String groupMessages(String id) => 'groupMessages/${safeSegment(id)}';
  static String status(String id) => 'statuses/${safeSegment(id)}';
  static String call(String id) => 'calls/${safeSegment(id)}';
}
