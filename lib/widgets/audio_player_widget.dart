import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';

/// Voice-message player.
/// - Uses the SAME flutter_sound library that recorded the audio (Codec.aacMP4)
///   → guaranteed format compatibility, no "no sound" bug.
/// - Caches the decoded audio file on device after first play → offline playback,
///   no re-download from Firebase.
/// - Live progress: waveform bars fill with color as playback advances,
///   WhatsApp-style.
class AudioPlayerWidget extends StatefulWidget {
  final String id, base64Audio, waveform;
  final int duration;
  final Color color;
  const AudioPlayerWidget({
    super.key,
    required this.id,
    required this.base64Audio,
    required this.waveform,
    required this.duration,
    required this.color,
  });
  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  StreamSubscription<PlaybackDisposition>? _progressSub;
  bool _playing = false, _paused = false, _loading = false, _opening = false;
  double _progress = 0.0; // 0.0 .. 1.0
  String? _cachedPath;
  List<double> _levels = const [];

  @override
  void initState() {
    super.initState();
    _levels = widget.waveform
        .split(',')
        .where((x) => x.isNotEmpty)
        .map((x) => double.tryParse(x) ?? .2)
        .toList();
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _try(() async {
      await _player.stopPlayer();
      await _player.closePlayer();
    });
    super.dispose();
  }

  Future<void> _try(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (_) {}
  }

  Future<bool> _ensureOpen() async {
    if (_player.isOpen()) return true;
    if (_opening) return false;
    _opening = true;
    try {
      await _player.openPlayer();
      await _player.setSubscriptionDuration(const Duration(milliseconds: 150));
      _progressSub = _player.onProgress?.listen((d) {
        final total = d.duration.inMilliseconds;
        if (total > 0 && mounted) {
          setState(() => _progress = (d.position.inMilliseconds / total).clamp(0.0, 1.0));
        }
      });
      return true;
    } catch (_) {
      return false;
    } finally {
      _opening = false;
    }
  }

  Future<String> _ensureFile() async {
    if (_cachedPath != null && await File(_cachedPath!).exists()) return _cachedPath!;
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/audio-cache-${widget.id}.m4a');
    if (!await file.exists()) {
      await file.writeAsBytes(base64Decode(widget.base64Audio), flush: true);
    }
    _cachedPath = file.path;
    return file.path;
  }

  Future<void> _toggle() async {
    if (_loading) return;
    if (_playing) {
      await _try(() => _player.pausePlayer());
      if (mounted) {
        setState(() {
          _playing = false;
          _paused = true;
        });
      }
      return;
    }
    setState(() => _loading = true);
    try {
      final ok = await _ensureOpen();
      if (!ok) throw 'player-open-failed';
      final path = await _ensureFile();
      if (_paused) {
        await _player.resumePlayer();
      } else {
        if (mounted) setState(() => _progress = 0.0);
        await _player.startPlayer(
          fromURI: path,
          codec: Codec.aacMP4,
          whenFinished: () {
            if (mounted) {
              setState(() {
                _playing = false;
                _paused = false;
                _progress = 0.0;
              });
            }
          },
        );
      }
      if (mounted) {
        setState(() {
          _playing = true;
          _paused = false;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تشغيل التسجيل')),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        GestureDetector(
          onTap: _toggle,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE85C5C).withOpacity(0.45), width: 1),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 3, offset: const Offset(0, 1))
              ],
            ),
            child: _loading
                ? const Center(
                    child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE85C5C))))
                : Icon(
                    _playing ? Icons.pause : Icons.play_arrow,
                    color: const Color(0xFFE85C5C),
                    size: 20,
                  ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 140,
          height: 36,
          child: CustomPaint(painter: _WavePainter(_levels, widget.color, _progress)),
        ),
        const SizedBox(width: 6),
        Text(
          '${widget.duration ~/ 60}:${(widget.duration % 60).toString().padLeft(2, '0')}',
          style: TextStyle(color: widget.color, fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ]);
}

/// Static waveform with playback progress: bars before the playhead are full
/// color, bars after are faded — WhatsApp style. Fixed bar count with
/// sampling/smoothing so it never looks crowded.
class _WavePainter extends CustomPainter {
  final List<double> levels;
  final Color color;
  final double progress;
  static const int _bars = 30;

  _WavePainter(this.levels, this.color, this.progress);

  List<double> _sample() {
    if (levels.isEmpty) return List.filled(_bars, 0.25);
    if (levels.length <= _bars) {
      final out = levels.map((x) => x.clamp(.08, 1.0).toDouble()).toList();
      while (out.length < _bars) {
        out.add(0.2);
      }
      return out;
    }
    final bucket = levels.length / _bars;
    final out = <double>[];
    for (var i = 0; i < _bars; i++) {
      final start = (i * bucket).floor();
      final end = ((i + 1) * bucket).floor().clamp(start + 1, levels.length);
      var sum = 0.0;
      for (var j = start; j < end; j++) {
        sum += levels[j];
      }
      out.add((sum / (end - start)).clamp(.08, 1.0));
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final sampled = _sample();
    final playedPaint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final pendingPaint = Paint()
      ..color = color.withOpacity(0.35)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final step = size.width / _bars;
    final playhead = progress * _bars;
    for (var i = 0; i < _bars; i++) {
      final h = sampled[i] * size.height * 0.85;
      final x = i * step + step / 2;
      final p = (i + 0.5) <= playhead ? playedPaint : pendingPaint;
      canvas.drawLine(Offset(x, size.height / 2 - h / 2), Offset(x, size.height / 2 + h / 2), p);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) =>
      old.levels != levels || old.color != color || old.progress != progress;
}
