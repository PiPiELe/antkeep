import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ShareImageExport {
  static const channel = MethodChannel('com.pipiele.antkeep/share_image');

  static Future<String?> save(Uint8List bytes, {bool toFile = false}) async {
    var extension =
        bytes.length >= 3 &&
            bytes[0] == 0xff &&
            bytes[1] == 0xd8 &&
            bytes[2] == 0xff
        ? 'jpg'
        : bytes.length >= 4 &&
              bytes[0] == 0x89 &&
              bytes[1] == 0x50 &&
              bytes[2] == 0x4e &&
              bytes[3] == 0x47
        ? 'png'
        : null;
    if (extension == null) {
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        try {
          final png = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (png == null) throw const FormatException('图片无法保存');
          bytes = png.buffer.asUint8List();
          extension = 'png';
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    }
    final name = 'antkeep-${DateTime.now().microsecondsSinceEpoch}.$extension';
    if (!toFile &&
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      final result = await channel.invokeMethod<String>('saveImage', {
        'bytes': bytes,
        'name': name,
      });
      if (result != 'use_file_picker') return result;
    }
    final result = await FilePicker.saveFile(
      dialogTitle: '保存分享图片',
      fileName: name,
      type: FileType.custom,
      allowedExtensions: [extension],
      bytes: bytes,
    );
    return result == null ? null : '图片已保存';
  }
}
