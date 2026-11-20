import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../utils/call_service.dart';

class CallScreen extends StatefulWidget {
  final String callId;
  final String uid;
  final bool caller;
  final String type;
  const CallScreen({super.key, required this.callId, required this.uid, required this.caller, required this.type});
  @override State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _local = RTCVideoRenderer();
  final _remote = RTCVideoRenderer();
  RTCPeerConnection? _pc;
  MediaStream? _stream;
  StreamSubscription<DatabaseEvent>? _sub;
  bool _muted = false, _cameraOff = false, _remoteSet = false, _hasRemote = false, _closing = false;
  final Set<String> _candidates = {};
  bool get _video => widget.type == 'video';

  @override void initState() { super.initState(); _start(); }

  Future<void> _start() async {
    await _local.initialize();
    await _remote.initialize();
    _pc = await createPeerConnection({'iceServers': [{'urls': 'stun:stun.l.google.com:19302'}]});
    _stream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': _video ? {'facingMode': 'user'} : false});
    _local.srcObject = _stream;
    for (final track in _stream!.getTracks()) { await _pc!.addTrack(track, _stream!); }
    _pc!.onIceCandidate = (candidate) => CallService.addIceCandidate(widget.callId, widget.uid, candidate.toMap());
    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty && mounted) { _remote.srcObject = event.streams.first; setState(() => _hasRemote = true); }
    };
    _sub = CallService.watch(widget.callId).listen(_handleCall);
    if (widget.caller) {
      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      await CallService.saveOffer(widget.callId, offer.toMap());
    }
  }

  Future<void> _handleCall(DatabaseEvent event) async {
    final raw = event.snapshot.value;
    if (raw is! Map || _pc == null) return;
    final data = Map<String, dynamic>.from(raw);
    final status = data['status']?.toString();
    if ((status == 'declined' || status == 'ended') && mounted && !_closing) {
      _closing = true;
      Navigator.of(context).pop();
      return;
    }
    if (!widget.caller && !_remoteSet && data['offer'] is Map) {
      final offer = Map<String, dynamic>.from(data['offer']);
      await _pc!.setRemoteDescription(RTCSessionDescription(offer['sdp']?.toString(), offer['type']?.toString()));
      _remoteSet = true;
      final answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);
      await CallService.saveAnswer(widget.callId, answer.toMap());
    } else if (widget.caller && !_remoteSet && data['answer'] is Map) {
      final answer = Map<String, dynamic>.from(data['answer']);
      await _pc!.setRemoteDescription(RTCSessionDescription(answer['sdp']?.toString(), answer['type']?.toString()));
      _remoteSet = true;
    }
    final all = data['candidates'];
    if (all is Map && _remoteSet) {
      for (final user in all.entries) {
        if (user.key.toString() == widget.uid) continue;
        if (user.value is! Map) continue;
        for (final item in (user.value as Map).entries) {
          final id = '${user.key}:${item.key}';
          final candidate = item.value;
          if (_candidates.contains(id) || candidate is! Map) continue;
          _candidates.add(id);
          await _pc!.addCandidate(RTCIceCandidate(candidate['candidate']?.toString(), candidate['sdpMid']?.toString(), (candidate['sdpMLineIndex'] as num?)?.toInt()));
        }
      }
    }
  }

  Future<void> _finish() async {
    if (_closing) return;
    _closing = true;
    await CallService.endCall(widget.callId);
    if (mounted) Navigator.pop(context);
  }

  @override void dispose() {
    _sub?.cancel();
    for (final track in _stream?.getTracks() ?? <MediaStreamTrack>[]) { track.stop(); }
    _stream?.dispose(); _pc?.close(); _local.dispose(); _remote.dispose(); super.dispose();
  }

  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(title: Text(_video ? 'مكالمة فيديو' : 'مكالمة صوتية')),
    body: Stack(children: [
      if (_video && _hasRemote) Positioned.fill(child: RTCVideoView(_remote)) else const Center(child: Icon(Icons.person, color: Colors.white54, size: 100)),
      if (_video) Positioned(top: 18, right: 18, width: 110, height: 150, child: RTCVideoView(_local, mirror: true)),
      Align(alignment: Alignment.bottomCenter, child: SafeArea(child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        IconButton(onPressed: () { for (final track in _stream?.getAudioTracks() ?? <MediaStreamTrack>[]) { track.enabled = _muted; } setState(() => _muted = !_muted); }, icon: Icon(_muted ? Icons.mic_off : Icons.mic, color: Colors.white)),
        if (_video) IconButton(onPressed: () { for (final track in _stream?.getVideoTracks() ?? <MediaStreamTrack>[]) { track.enabled = _cameraOff; } setState(() => _cameraOff = !_cameraOff); }, icon: Icon(_cameraOff ? Icons.videocam_off : Icons.videocam, color: Colors.white)),
        FloatingActionButton(backgroundColor: Colors.red, onPressed: _finish, child: const Icon(Icons.call_end)),
      ]))),
    ]),
  );
}
