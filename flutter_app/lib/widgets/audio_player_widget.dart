import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

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
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false, _loading = false;
  List<double> _levels = const [];

  @override
  void initState() {
    super.initState();
    _levels = widget.waveform
        .split(',')
        .where((x) => x.isNotEmpty)
        .map((x) => double.tryParse(x) ?? .2)
        .toList();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_loading) return;
    if (_playing) {
      await _player.pause();
      if (mounted) setState(() => _playing = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/audio-cache-${widget.id}.m4a');
      if (!await file.exists()) {
        await file.writeAsBytes(base64Decode(widget.base64Audio), flush: true);
      }
      await _player.play(DeviceFileSource(file.path));
      if (mounted) setState(() => _playing = true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر تشغيل التسجيل')));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          onPressed: _toggle,
          icon: _loading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(
                  _playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
                  color: widget.color,
                  size: 30,
                ),
        ),
        SizedBox(
          width: 150,
          height: 42,
          child: CustomPaint(painter: _WavePainter(_levels, widget.color)),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Text(
            '${widget.duration ~/ 60}:${(widget.duration % 60).toString().padLeft(2, '0')}',
            style: TextStyle(color: widget.color, fontSize: 11),
          ),
        ),
      ]);
}

/// Static waveform for a stored voice message: always draws a fixed number of
/// rounded bars, sampling/smoothing the stored levels so it never looks crowded.
class _WavePainter extends CustomPainter {
  final List<double> levels;
  final Color color;
  static const int _bars = 28;

  _WavePainter(this.levels, this.color);

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
    final p = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final step = size.width / _bars;
    for (var i = 0; i < _bars; i++) {
      final h = sampled[i] * size.height * 0.8;
      final x = i * step + step / 2;
      canvas.drawLine(Offset(x, size.height / 2 - h / 2), Offset(x, size.height / 2 + h / 2), p);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => old.levels != levels || old.color != color;
}
