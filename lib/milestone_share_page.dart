import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'data/share_image_export.dart';
import 'data/app_database.dart';
import 'data/local_media_store.dart';
import 'domain/milestone.dart';
import 'domain/models.dart';
import 'milestone_page.dart';

export 'domain/milestone.dart' show MilestoneArtwork;

const milestonePosterSize = Size(400, 500);
const milestonePhotoSize = Size(400, 300);

final _artworkFutures = <MilestoneArtwork, Future<ui.Image>>{};

Future<ui.Image> loadMilestoneArtwork(MilestoneArtwork artwork) =>
    _artworkFutures.putIfAbsent(artwork, () async {
      try {
        final data = await rootBundle.load(artwork.assetPath);
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
        _artworkFutures.remove(artwork);
        rethrow;
      }
    });

class MilestonePoster extends StatelessWidget {
  const MilestonePoster({
    super.key,
    this.colony,
    required this.milestone,
    required this.artwork,
    this.photoBytes,
  });

  final Colony? colony;
  final Milestone milestone;
  final MilestoneArtwork artwork;
  final Uint8List? photoBytes;

  @override
  Widget build(BuildContext context) {
    final stone = AspectRatio(
      aspectRatio: milestonePosterSize.aspectRatio,
      child: FutureBuilder<ui.Image>(
        future: loadMilestoneArtwork(artwork),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('石刻画面加载失败，请重新打开预览。'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return CustomPaint(
            painter: MilestonePosterPainter(colony, milestone, snapshot.data!),
          );
        },
      ),
    );
    return Semantics(
      image: true,
      label:
          '${colony == null ? '' : '${colony!.name}，'}${milestone.title}的里程碑分享图',
      child: photoBytes == null && milestone.photoPath == null
          ? stone
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                stone,
                AspectRatio(
                  aspectRatio: milestonePhotoSize.aspectRatio,
                  child: photoBytes != null
                      ? _photoImage(photoBytes!)
                      : _StoredMilestonePhoto(path: milestone.photoPath!),
                ),
              ],
            ),
    );
  }
}

Widget _photoImage(Uint8List bytes) => ColoredBox(
  color: const Color(0xff251508),
  child: SizedBox.expand(
    child: Image.memory(
      bytes,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => const Center(child: Text('照片加载失败')),
    ),
  ),
);

class _StoredMilestonePhoto extends StatefulWidget {
  const _StoredMilestonePhoto({required this.path});
  final String path;

  @override
  State<_StoredMilestonePhoto> createState() => _StoredMilestonePhotoState();
}

class _StoredMilestonePhotoState extends State<_StoredMilestonePhoto> {
  late Future<Uint8List> _bytes = LocalMediaStore.instance.readImage(
    widget.path,
  );

  @override
  void didUpdateWidget(covariant _StoredMilestonePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _bytes = LocalMediaStore.instance.readImage(widget.path);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _bytes,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Center(child: Text('照片加载失败'));
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return _photoImage(snapshot.data!);
    },
  );
}

class MilestonePosterPainter extends CustomPainter {
  const MilestonePosterPainter(this.colony, this.milestone, this.artwork);

  final Colony? colony;
  final Milestone milestone;
  final ui.Image artwork;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 400, size.height / 500);
    const bounds = Rect.fromLTWH(0, 0, 400, 500);
    paintImage(
      canvas: canvas,
      rect: bounds,
      image: artwork,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
    );
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 400, 95),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xcc201208), Color(0x00201208)],
        ).createShader(const Rect.fromLTWH(0, 0, 400, 95)),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(21, 330, 358, 149),
        const Radius.circular(5),
      ),
      Paint()..color = const Color(0xaa251508),
    );
    final border = Paint()
      ..color = const Color(0xbdbd9760)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(21, 330, 358, 149),
        const Radius.circular(5),
      ),
      border,
    );
    canvas.drawLine(const Offset(48, 448), const Offset(352, 448), border);
    _text(
      canvas,
      '蚁 记  ·  里 程 碑',
      const Rect.fromLTWH(35, 19, 330, 22),
      13,
      const Color(0xfff6e5bf),
      maxLines: 1,
      letterSpacing: 2,
      fontWeight: FontWeight.w600,
    );
    if (colony != null) {
      _text(
        canvas,
        colony!.name,
        const Rect.fromLTWH(45, 46, 310, 25),
        15,
        const Color(0xffe7d0a1),
        maxLines: 1,
        letterSpacing: 1,
        fontWeight: FontWeight.w600,
      );
    }
    _text(
      canvas,
      milestone.title.trim(),
      const Rect.fromLTWH(40, 339, 320, 55),
      24,
      const Color(0xffffe9b9),
      maxLines: 2,
      minimumSize: 15,
      letterSpacing: 1.2,
      fontWeight: FontWeight.w700,
    );
    final note = milestone.note?.trim();
    if (note != null && note.isNotEmpty) {
      _text(
        canvas,
        note.replaceAll(RegExp(r'\s+'), ' '),
        const Rect.fromLTWH(43, 396, 314, 45),
        12,
        const Color(0xffeee0c4),
        maxLines: 3,
        minimumSize: 10,
        letterSpacing: .4,
      );
    }
    final date = milestone.occurredAt;
    final dateText =
        '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}'
        '${date.hour == 0 && date.minute == 0 ? '' : '  ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'}';
    _text(
      canvas,
      dateText,
      const Rect.fromLTWH(45, 452, 310, 19),
      11,
      const Color(0xffe0b977),
      maxLines: 1,
      letterSpacing: 1,
      fontWeight: FontWeight.w600,
    );
    _text(
      canvas,
      'ANTKEEP  ·  微小生命的编年史',
      const Rect.fromLTWH(40, 481, 320, 14),
      8,
      const Color(0xffdac398),
      maxLines: 1,
      letterSpacing: .6,
    );
    canvas.restore();
  }

  void _text(
    Canvas canvas,
    String value,
    Rect area,
    double fontSize,
    Color color, {
    required int maxLines,
    double minimumSize = 10,
    double letterSpacing = 0,
    FontWeight fontWeight = FontWeight.w400,
  }) {
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: maxLines,
      ellipsis: '…',
    );
    try {
      do {
        painter.text = TextSpan(
          text: value,
          style: TextStyle(
            fontFamily: 'StoneSerif',
            fontWeight: fontWeight,
            fontSize: fontSize,
            color: color,
            height: 1.32,
            letterSpacing: letterSpacing,
            shadows: const [
              Shadow(color: Color(0xcc1a0e05), offset: Offset(0, 1)),
              Shadow(color: Color(0x88967447), offset: Offset(0, -0.5)),
            ],
          ),
        );
        painter.layout(maxWidth: area.width);
        if (painter.height <= area.height || fontSize <= minimumSize) break;
        fontSize -= .5;
      } while (true);
      canvas.save();
      canvas.clipRect(area);
      painter.paint(
        canvas,
        Offset(
          area.left + (area.width - painter.width) / 2,
          area.top + (area.height - painter.height) / 2,
        ),
      );
      canvas.restore();
    } finally {
      painter.dispose();
    }
  }

  @override
  bool shouldRepaint(covariant MilestonePosterPainter oldDelegate) =>
      oldDelegate.colony != colony ||
      oldDelegate.milestone != milestone ||
      oldDelegate.artwork != artwork;
}

Future<Uint8List> renderMilestonePng(
  Colony? colony,
  Milestone milestone,
  MilestoneArtwork artwork,
) async {
  final image = await loadMilestoneArtwork(artwork);
  ui.Image? photo;
  if (milestone.photoPath != null) {
    final bytes = await LocalMediaStore.instance.readImage(
      milestone.photoPath!,
    );
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 1200);
    try {
      photo = (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  MilestonePosterPainter(
    colony,
    milestone,
    image,
  ).paint(canvas, milestonePosterSize);
  if (photo != null) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 500, 400, 300),
      Paint()..color = const Color(0xff251508),
    );
    paintImage(
      canvas: canvas,
      rect: const Rect.fromLTWH(0, 500, 400, 300),
      image: photo,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }
  final picture = recorder.endRecording();
  final scaledRecorder = ui.PictureRecorder();
  Canvas(scaledRecorder)
    ..scale(3)
    ..drawPicture(picture);
  final scaled = scaledRecorder.endRecording();
  ui.Image? output;
  try {
    output = await scaled.toImage(1200, photo == null ? 1500 : 2400);
    final data = await output.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('分享图生成失败');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    output?.dispose();
    photo?.dispose();
    scaled.dispose();
    picture.dispose();
  }
}

typedef ShareMilestoneImage = Future<void> Function(
  Uint8List bytes,
  String name,
  Rect origin,
);
typedef SaveMilestoneImage = Future<String?> Function(Uint8List bytes);

class MilestoneSharePage extends StatefulWidget {
  const MilestoneSharePage({
    super.key,
    this.colony,
    required this.milestone,
    this.shareImage,
    this.saveImage,
  });

  final Colony? colony;
  final Milestone milestone;
  final ShareMilestoneImage? shareImage;
  final SaveMilestoneImage? saveImage;

  @override
  State<MilestoneSharePage> createState() => _MilestoneSharePageState();
}

class _MilestoneSharePageState extends State<MilestoneSharePage> {
  late Milestone _milestone = widget.milestone;
  late Colony? _colony = widget.colony;
  bool _busy = false;

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            MilestoneFormPage(colony: widget.colony, milestone: _milestone),
      ),
    );
    if (saved != true || !mounted) return;
    try {
      final updated = await AppDatabase.instance.findMilestone(_milestone.id);
      if (updated == null || !mounted) return;
      final colony = updated.colonyId == null
          ? null
          : await AppDatabase.instance.findColony(updated.colonyId!);
      if (mounted) {
        setState(() {
          _milestone = updated;
          _colony = colony;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('刷新里程碑失败：$error')));
      }
    }
  }

  Future<void> _export(
    BuildContext buttonContext, {
    required bool share,
  }) async {
    if (_busy) return;
    final box = buttonContext.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    setState(() => _busy = true);
    try {
      final bytes = await renderMilestonePng(
        _colony,
        _milestone,
        _milestone.artwork,
      );
      if (!mounted) return;
      final name =
          'antkeep-milestone-${DateTime.now().millisecondsSinceEpoch}.png';
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
        final result = widget.saveImage != null
            ? await widget.saveImage!(bytes)
            : await ShareImageExport.save(bytes);
        if (mounted && result != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(result)));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(share ? '分享失败，请重试或先保存图片' : '图片保存失败，请重试')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('石刻预览'),
      actions: [
        if (_colony?.archived != true)
          IconButton(
            tooltip: '编辑里程碑',
            onPressed: _busy ? null : _edit,
            icon: const Icon(Icons.edit_outlined),
          ),
      ],
    ),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            Expanded(
              child: Builder(
                builder: (buttonContext) => FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _export(buttonContext, share: true),
                  icon: const Icon(Icons.share_outlined),
                  label: Text(_busy ? '生成中…' : '转发分享'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Builder(
              builder: (buttonContext) => OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _export(buttonContext, share: false),
                icon: const Icon(Icons.download_outlined),
                label: const Text('保存图片'),
              ),
            ),
          ],
        ),
      ),
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: MilestonePoster(
                colony: _colony,
                milestone: _milestone,
                artwork: _milestone.artwork,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text('说明较长时，分享图显示摘要；里程碑原文仍完整保留。'),
        ],
      ),
    ),
  );
}
