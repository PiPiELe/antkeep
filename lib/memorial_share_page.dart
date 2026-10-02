import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'domain/memorial.dart';

const memorialPosterSize = Size(400, 900);
const _gold = Color(0xffc9ad79);
final _memorialArtwork = <MemorialKind, Future<ui.Image>>{};

/// Bundled memorial artwork is shared by preview and PNG.
Future<ui.Image> loadMemorialArtwork(MemorialKind kind) =>
    _memorialArtwork.putIfAbsent(kind, () => _decodeMemorialArtwork(kind));

Future<ui.Image> _decodeMemorialArtwork(MemorialKind kind) async {
  try {
    final asset = switch (kind) {
      MemorialKind.queen => 'ant-monarch.png',
      MemorialKind.worker => 'ant-warrior.png',
      MemorialKind.brood => 'ant-brood-v3.png',
      MemorialKind.colony => 'ant-monument-v2.png',
    };
    final data = await rootBundle.load('assets/memorial/$asset');
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      targetWidth: 1200,
    );
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  } catch (_) {
    _memorialArtwork.remove(kind);
    rethrow;
  }
}

/// The preview and PNG use the same painter, independent of screen size/theme.
class MemorialPoster extends StatelessWidget {
  const MemorialPoster({super.key, required this.memorial});
  final Memorial memorial;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: '${memorial.kind.epitaph}，${memorial.name}的纪念分享图',
    child: AspectRatio(
      aspectRatio: memorialPosterSize.aspectRatio,
      child: FutureBuilder<ui.Image>(
        future: loadMemorialArtwork(memorial.kind),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('插画加载失败，请重新打开预览或重试保存。'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return CustomPaint(
            painter: MemorialPosterPainter(memorial, snapshot.data!),
          );
        },
      ),
    ),
  );
}

String _excerpt(String text, int limit) {
  final normalized = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  return normalized.characters.length <= limit
      ? normalized
      : '${normalized.characters.take(limit)}…';
}

class MemorialPosterPainter extends CustomPainter {
  const MemorialPosterPainter(this.memorial, this.artwork);
  final Memorial memorial;
  final ui.Image artwork;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 400, size.height / 900);
    const bounds = Rect.fromLTWH(0, 0, 400, 900);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff23272c), Color(0xff0b1016), Color(0xff1c1b1c)],
        ).createShader(bounds),
    );
    // Distant light behind the monument, with a quiet red horizon.
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -.18),
          radius: .7,
          colors: [
            const Color(0xffb79964).withValues(alpha: .18),
            Colors.transparent,
          ],
        ).createShader(bounds),
    );
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .7
      ..color = _gold.withValues(alpha: .35);
    canvas.drawRect(const Rect.fromLTWH(18, 18, 364, 864), stroke);
    canvas.drawLine(const Offset(34, 72), const Offset(366, 72), stroke);
    _text(
      canvas,
      '蚁 记  ·  英 灵 殿',
      const Rect.fromLTWH(40, 35, 320, 22),
      12,
      color: _gold,
      spacing: 3,
    );
    _text(
      canvas,
      '谨以此碑，铭记曾经的微光',
      const Rect.fromLTWH(40, 92, 320, 24),
      12,
      color: const Color(0xffb2aaa0),
      spacing: 2,
    );
    _text(
      canvas,
      memorial.kind.epitaph,
      const Rect.fromLTWH(28, 130, 344, 55),
      36,
      color: const Color(0xffeddbb8),
      spacing: 3,
    );
    final subtitle = switch (memorial.kind) {
      MemorialKind.queen => '一朝为后，一生守望',
      MemorialKind.worker => '身虽微小，亦曾守护山河',
      MemorialKind.brood => '尚未羽化，亦值得被铭记',
      MemorialKind.colony => '城邦归于寂静，文明长存于记忆',
    };
    _text(
      canvas,
      subtitle,
      const Rect.fromLTWH(40, 191, 320, 26),
      12,
      color: _gold,
      spacing: 1,
    );

    // Ant-eye-level artwork: keep the foreground ant and towering monument
    // together, with no cropping. Text remains native and fully personalized.
    const scene = Rect.fromLTWH(19, 218, 362, 362);
    canvas.saveLayer(scene, Paint());
    paintImage(
      canvas: canvas,
      rect: scene,
      image: artwork,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
    canvas.drawRect(
      scene,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: [0, .06, .90, 1],
        ).createShader(scene),
    );
    canvas.restore();
    canvas.drawLine(const Offset(58, 590), const Offset(342, 590), stroke);
    _text(
      canvas,
      memorial.name,
      const Rect.fromLTWH(45, 604, 310, 64),
      24,
      color: const Color(0xffefe9dd),
      spacing: 1,
    );
    if (memorial.species?.trim().isNotEmpty == true) {
      _text(
        canvas,
        _excerpt(memorial.species!, 45),
        const Rect.fromLTWH(45, 676, 310, 31),
        12,
        color: const Color(0xffa9a49b),
      );
    }
    final date = memorial.diedOn;
    final dateText = date == null
        ? '离别之日未记，思念长存'
        : '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}  ·  ${memorial.kind == MemorialKind.colony ? '文明落幕' : '长眠于此'}';
    _text(
      canvas,
      dateText,
      const Rect.fromLTWH(40, 717, 320, 24),
      12,
      color: _gold,
      spacing: 1,
    );
    final farewell = memorial.farewell?.trim();
    _text(
      canvas,
      farewell == null || farewell.isEmpty
          ? '曾以微小之躯，\n在这世间留下一个王国。'
          : '「${_excerpt(farewell, 80)}」',
      const Rect.fromLTWH(48, 754, 304, 66),
      14,
      color: const Color(0xffd2c9b9),
      spacing: .6,
    );
    _text(
      canvas,
      'ANTKEEP  /  微小生命，值得铭记',
      const Rect.fromLTWH(32, 851, 336, 18),
      9,
      color: const Color(0xff918574),
      spacing: 1,
    );
    canvas.restore();
  }

  void _text(
    Canvas canvas,
    String value,
    Rect area,
    double fontSize, {
    required Color color,
    double spacing = 0,
  }) {
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    try {
      do {
        painter.text = TextSpan(
          text: value,
          style: TextStyle(
            fontFamily: 'serif',
            fontSize: fontSize,
            color: color,
            letterSpacing: spacing,
            height: 1.45,
          ),
        );
        painter.layout(maxWidth: area.width);
        if (painter.height <= area.height || fontSize <= 6) break;
        fontSize -= .5;
      } while (true);
      painter.paint(
        canvas,
        Offset(
          area.left + (area.width - painter.width) / 2,
          area.top + (area.height - painter.height) / 2,
        ),
      );
    } finally {
      painter.dispose();
    }
  }

  @override
  bool shouldRepaint(MemorialPosterPainter oldDelegate) =>
      oldDelegate.memorial != memorial || oldDelegate.artwork != artwork;
}

Future<Uint8List> renderMemorialPng(Memorial memorial) async {
  final artwork = await loadMemorialArtwork(memorial.kind);
  final recorder = ui.PictureRecorder();
  MemorialPosterPainter(
    memorial,
    artwork,
  ).paint(Canvas(recorder), memorialPosterSize);
  final picture = recorder.endRecording();
  // Render at 3x without depending on the device's pixel ratio.
  final scaledRecorder = ui.PictureRecorder();
  Canvas(scaledRecorder)
    ..scale(3)
    ..drawPicture(picture);
  final scaled = scaledRecorder.endRecording();
  ui.Image? image;
  try {
    image = await scaled.toImage(
      (memorialPosterSize.width * 3).round(),
      (memorialPosterSize.height * 3).round(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('分享图生成失败');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image?.dispose();
    scaled.dispose();
    picture.dispose();
  }
}

typedef SaveMemorialImage = Future<bool> Function(Uint8List, String);
typedef ShareMemorialImage = Future<void> Function(Uint8List, String, Rect);

class MemorialSharePage extends StatefulWidget {
  const MemorialSharePage({
    super.key,
    required this.memorial,
    this.saveImage,
    this.shareImage,
  });
  final Memorial memorial;
  final SaveMemorialImage? saveImage;
  final ShareMemorialImage? shareImage;

  @override
  State<MemorialSharePage> createState() => _MemorialSharePageState();
}

class _MemorialSharePageState extends State<MemorialSharePage> {
  bool _busy = false;
  Uint8List? _png;

  Future<void> _export(
    BuildContext buttonContext, {
    required bool share,
  }) async {
    if (_busy) return;
    final box = buttonContext.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    setState(() => _busy = true);
    try {
      final bytes = _png ??= await renderMemorialPng(widget.memorial);
      if (!mounted) return;
      final name =
          'antkeep-memorial-${DateTime.now().millisecondsSinceEpoch}.png';
      if (share) {
        if (widget.shareImage != null) {
          await widget.shareImage!(bytes, name, origin);
        } else {
          await SharePlus.instance.share(
            ShareParams(
              files: [XFile.fromData(bytes, mimeType: 'image/png')],
              fileNameOverrides: [name],
              sharePositionOrigin: origin,
            ),
          );
        }
      } else {
        final saved = widget.saveImage != null
            ? await widget.saveImage!(bytes, name)
            : await FilePicker.saveFile(
                    dialogTitle: '保存纪念分享图',
                    fileName: name,
                    type: FileType.custom,
                    allowedExtensions: ['png'],
                    bytes: bytes,
                  ) !=
                  null;
        if (saved && mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('分享图已保存')));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(share ? '分享失败，请重试或保存图片后分享' : '图片保存失败，请重试')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('纪念分享图')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: MemorialPoster(memorial: widget.memorial),
            ),
          ),
          const SizedBox(height: 12),
          const Text('预览即分享内容 · 图片在本机生成', textAlign: TextAlign.center),
          if (_excerpt(widget.memorial.farewell ?? '', 80).endsWith('…') ||
              _excerpt(widget.memorial.species ?? '', 45).endsWith('…'))
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '长留言或品种名称在图中展示节选，完整内容仍保留在纪念中。',
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Builder(
          builder: (buttonContext) => Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _export(buttonContext, share: false),
                icon: const Icon(Icons.download_outlined),
                label: const Text('保存图片'),
              ),
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _export(buttonContext, share: true),
                icon: const Icon(Icons.ios_share),
                label: Text(_busy ? '处理中…' : '分享图片'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
