import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'domain/colony_qr.dart';

class ColonyScanPage extends StatefulWidget {
  const ColonyScanPage({super.key, required this.exists});
  final Future<bool> Function(String id) exists;

  @override
  State<ColonyScanPage> createState() => _ColonyScanPageState();
}

class _ColonyScanPageState extends State<ColonyScanPage> {
  final _controller = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool _checking = false;
  bool _done = false;
  String? _message;

  Future<void> _detect(BarcodeCapture capture) async {
    if (_checking || _done) return;
    final values = capture.barcodes.map((b) => b.rawValue).whereType<String>();
    if (values.isEmpty) return;
    final ids = values.map(ColonyQr.decode).whereType<String>();
    if (ids.isEmpty) {
      if (_message == null) setState(() => _message = '这不是蚁记蚁群标签，请对准蚁记生成的二维码。');
      return;
    }
    _checking = true;
    try {
      final id = ids.first;
      final found = await widget.exists(id);
      if (!mounted || _done) return;
      if (!found) {
        setState(() => _message = '本机没有此蚁群。若已换机，请先恢复原设备备份；已删除的档案无法打开。');
        return;
      }
      _done = true;
      try {
        await _controller.stop();
      } catch (_) {
        // Route disposal also releases the camera; a valid match can still open.
      }
      if (mounted) Navigator.of(context).pop(id);
    } catch (_) {
      if (mounted) setState(() => _message = '读取失败，请稍后重试。');
    } finally {
      _checking = false;
    }
  }

  @override
  void dispose() {
    _done = true;
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final supported =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    return Scaffold(
      appBar: AppBar(title: const Text('扫描蚁群标签')),
      body: supported
          ? Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('将标签放入画面中。识别与档案查询均在本机完成。'),
                ),
                Expanded(
                  child: MobileScanner(
                    controller: _controller,
                    onDetect: _detect,
                    errorBuilder: (context, error) => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('相机暂不可用。请检查系统设置中的相机权限，返回后重新进入扫码。'),
                      ),
                    ),
                  ),
                ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(_message!),
                  ),
              ],
            )
          : const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('请在 Android 或 iPhone App 中使用离线扫码。'),
              ),
            ),
    );
  }
}
