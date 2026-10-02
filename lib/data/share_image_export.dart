import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ShareImageExport {
  static const channel = MethodChannel('com.pipiele.antkeep/share_image');

  static Future<String?> save(Uint8List png, {bool toFile = false}) async {
    final name = 'antkeep-${DateTime.now().microsecondsSinceEpoch}.png';
    if (!toFile &&
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      final result = await channel.invokeMethod<String>('saveImage', {
        'bytes': png,
        'name': name,
      });
      if (result != 'use_file_picker') return result;
    }
    final result = await FilePicker.saveFile(
      dialogTitle: '保存分享图片',
      fileName: name,
      type: FileType.custom,
      allowedExtensions: const ['png'],
      bytes: png,
    );
    return result == null ? null : '图片已保存';
  }
}
