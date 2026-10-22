import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'data/share_image_export.dart';
import 'domain/colony_qr.dart';
import 'domain/models.dart';

class ColonyLabelPage extends StatefulWidget {
  const ColonyLabelPage({super.key, required this.colony});
  final Colony colony;

  @override
  State<ColonyLabelPage> createState() => _ColonyLabelPageState();
}

class _ColonyLabelPageState extends State<ColonyLabelPage> {
  final _label = GlobalKey();
  bool _saving = false;
  String? _data;

  @override
  void initState() {
    super.initState();
    try {
      _data = ColonyQr.encode(widget.colony.id);
    } on FormatException {
      /* An imported legacy ID may not be label-compatible. */
    }
  }

  Future<void> _save(bool toFile) async {
    setState(() => _saving = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final boundary =
          _label.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 4);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) throw StateError('标签生成失败');
        final message = await ShareImageExport.save(
          bytes.buffer.asUint8List(),
          toFile: toFile,
        );
        if (mounted && message != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(message)));
        }
      } finally {
        image.dispose();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('标签保存失败，请重试或另存为文件。')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => _data == null
      ? Scaffold(
          appBar: AppBar(title: const Text('蚁群二维码标签')),
          body: const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('此档案的编号无法生成二维码标签，仍可从蚁群列表正常打开。'),
            ),
          ),
        )
      : Scaffold(
          appBar: AppBar(title: const Text('蚁群二维码标签')),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text('保存标签图片后可打印，贴在试管或巢盒上。在蚁记首页扫描，即可打开本机对应档案。'),
              const SizedBox(height: 20),
              Center(
                child: RepaintBoundary(
                  key: _label,
                  child: Container(
                    width: 280,
                    padding: const EdgeInsets.all(16),
                    color: Colors.white,
                    child: DefaultTextStyle(
                      style: Theme.of(context).textTheme.bodyMedium!
                          .copyWith(color: Colors.black, fontSize: 14),
                      textAlign: TextAlign.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.colony.name,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (widget.colony.species?.isNotEmpty == true)
                            Text(widget.colony.species!),
                          QrImageView(
                            data: _data!,
                            size: 216,
                            padding: const EdgeInsets.all(16),
                            backgroundColor: Colors.white,
                            errorCorrectionLevel: QrErrorCorrectLevel.M,
                          ),
                          const Text('蚁记 AntKeep · 扫码查看本机档案'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '二维码仅包含档案编号，不含日记或照片。换机后先恢复备份，原标签可继续使用。请保留白边、避免拉伸，并在粘贴前试扫。',
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _saving ? null : () => _save(false),
                icon: const Icon(Icons.save_alt),
                label: Text(_saving ? '正在保存…' : '保存标签图片'),
              ),
              TextButton(
                onPressed: _saving ? null : () => _save(true),
                child: const Text('另存为文件，用于打印'),
              ),
            ],
          ),
        );
}
