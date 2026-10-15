import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/share_image_export.dart';

Future<void> showPhotoSavePreview(
  BuildContext context, {
  required Uint8List bytes,
  required String title,
}) => showDialog<void>(
  context: context,
  builder: (dialogContext) => Dialog.fullscreen(
    child: Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: const CloseButton(),
        actions: [
          IconButton(
            tooltip: '保存到本地',
            icon: const Icon(Icons.download_outlined),
            onPressed: () async {
              try {
                final message = await ShareImageExport.save(bytes);
                if (dialogContext.mounted && message != null) {
                  ScaffoldMessenger.of(dialogContext)
                      .showSnackBar(SnackBar(content: Text(message)));
                }
              } catch (_) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(
                    dialogContext,
                  ).showSnackBar(const SnackBar(content: Text('图片保存失败，请重试')));
                }
              }
            },
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
      ),
    ),
  ),
);
