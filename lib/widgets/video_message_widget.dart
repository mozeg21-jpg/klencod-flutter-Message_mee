import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

/// رسالة فيديو بنفس فكرة الصوت والصورة:
/// البيانات مخزنة Base64 نصيًا في Realtime Database (بدون Firebase Storage)،
/// تُفك إلى ملف مؤقت على الجهاز أول تشغيل ثم يُعرض داخل فقاعة المحادثة.
class VideoMessageWidget extends StatefulWidget {
  final String id;
  final String base64;
  final bool mine;
  const VideoMessageWidget({super.key, required this.id, required this.base64, required this.mine});

  @override
  State<VideoMessageWidget> createState() => _VideoMessageWidgetState();
}

class _VideoMessageWidgetState extends State<VideoMessageWidget> {
  VideoPlayerController? _controller;
  bool _initializing = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/chat_video_${widget.id}.mp4');
      if (!await file.exists() || await file.length() < 512) {
        var encoded = widget.base64.trim();
        if (encoded.contains(',')) encoded = encoded.split(',').last;
        final bytes = base64Decode(encoded);
        await file.writeAsBytes(bytes, flush: true);
      }
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(false);
      controller.addListener(_onProgress);
      _controller = controller;
      setState(() => _initializing = false);
    } catch (_) {
      if (mounted) setState(() {
        _initializing = false;
        _failed = true;
      });
    }
  }

  void _onProgress() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.removeListener(_onProgress);
    _controller?.pause();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final c = _controller;
    if (c == null) return;
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      await c.play();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.mine ? Colors.white : const Color(0xFFE85C5C);
    if (_failed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.videocam_off_outlined, size: 22, color: accent.withOpacity(0.8)),
          const SizedBox(width: 6),
          Text('تعذر تشغيل الفيديو',
              textDirection: TextDirection.rtl,
              style: TextStyle(fontSize: 13, color: accent.withOpacity(0.8))),
        ]),
      );
    }
    if (_initializing || _controller == null) {
      return SizedBox(
        width: 220,
        height: 140,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: accent)),
      );
    }
    final c = _controller!;
    return GestureDetector(
      onTap: () => _openViewer(c),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Container(
          color: Colors.black,
          constraints: const BoxConstraints(maxWidth: 240, maxHeight: 200),
          child: Stack(alignment: Alignment.center, children: [
            AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)),
            if (!c.value.isPlaying)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow, color: Colors.white, size: 30),
              ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: VideoProgressIndicator(
                c,
                allowScrubbing: false,
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                colors: const VideoProgressColors(
                  playedColor: Color(0xFFE85C5C),
                  bufferedColor: Colors.white24,
                  backgroundColor: Colors.white12,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _openViewer(VideoPlayerController source) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _VideoViewer(controller: source),
    ));
    if (mounted) setState(() {});
  }
}

class _VideoViewer extends StatefulWidget {
  final VideoPlayerController controller;
  const _VideoViewer({required this.controller});

  @override
  State<_VideoViewer> createState() => _VideoViewerState();
}

class _VideoViewerState extends State<_VideoViewer> {
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Center(
        child: GestureDetector(
          onTap: () async {
            if (c.value.isPlaying) {
              await c.pause();
            } else {
              await c.play();
            }
            if (mounted) setState(() {});
          },
          child: Stack(alignment: Alignment.center, children: [
            AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)),
            if (!c.value.isPlaying)
              const DecoratedBox(
                decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: Padding(padding: EdgeInsets.all(14), child: Icon(Icons.play_arrow, color: Colors.white, size: 44)),
              ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: VideoProgressIndicator(c, allowScrubbing: true, colors: const VideoProgressColors(playedColor: Color(0xFFE85C5C))),
            ),
          ]),
        ),
      ),
    );
  }
}
