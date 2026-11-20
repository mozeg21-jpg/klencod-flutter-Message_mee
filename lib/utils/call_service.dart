import 'package:firebase_database/firebase_database.dart';

/// طبقة إشارات المكالمات؛ Firebase ينسق WebRTC ولا يحمل الصوت أو الفيديو.
class CallService {
  static final DatabaseReference _root = FirebaseDatabase.instance.ref('calls');

  static Future<String> createCall({
    required String callerId,
    required String callerName,
    required String type,
    String? targetId,
    String? groupId,
    String? conversationId,
  }) async {
    final ref = _root.push();
    await ref.set({
      'callerId': callerId,
      'callerName': callerName,
      'targetId': targetId,
      'groupId': groupId,
      'conversationId': conversationId,
      'type': type,
      'status': 'ringing',
      'participants': {callerId: true},
      'createdAt': ServerValue.timestamp,
    });
    return ref.key!;
  }

  static Future<void> updateStatus(String callId, String status) =>
      _root.child(callId).update({'status': status, 'updatedAt': ServerValue.timestamp});

  static Future<void> addParticipant(String callId, String uid) =>
      _root.child(callId).child('participants').child(uid).set(true);

  static Future<void> saveOffer(String callId, Map<String, dynamic> offer) =>
      _root.child(callId).child('offer').set(offer);

  static Future<void> saveAnswer(String callId, Map<String, dynamic> answer) =>
      _root.child(callId).child('answer').set(answer);

  static Future<void> addIceCandidate(String callId, String uid, Map<String, dynamic> candidate) =>
      _root.child(callId).child('candidates').child(uid).push().set(candidate);

  static Stream<DatabaseEvent> watch(String callId) => _root.child(callId).onValue;

  static Future<void> endCall(String callId) => updateStatus(callId, 'ended');
}
