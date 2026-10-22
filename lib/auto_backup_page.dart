import 'dart:async';

import 'package:flutter/material.dart';

import 'busy_task.dart';
import 'data/auto_backup_controller.dart';
import 'data/auto_backup_model.dart';

const autoBackupExplanation =
    '开启后，每天首次使用 App 时自动保存一份包含记录和照片的完整备份，保留最近 3 份。连续使用时也会检查是否跨日。\n\n备份仅保存在本机应用内部，不上传。卸载 App、手机丢失或损坏后无法取回，请定期将重要备份导出到应用外。';

Future<void> showAutoBackupConsent(
  BuildContext context,
  AutoBackupController controller,
) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _BackupConsent(controller: controller),
);

class _BackupConsent extends StatefulWidget {
  const _BackupConsent({required this.controller});
  final AutoBackupController controller;
  @override
  State<_BackupConsent> createState() => _BackupConsentState();
}

class _BackupConsentState extends State<_BackupConsent> {
  bool _saving = false;
  String? _error;
  Future<void> _choose(bool enabled) async {
    setState(() => _saving = true);
    try {
      await widget.controller.setEnabled(enabled);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '选择未保存，请重试。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: AlertDialog(
      scrollable: true,
      title: const Text('开启自动本地备份？'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(autoBackupExplanation),
          const SizedBox(height: 12),
          const Text('可随时在「设置 → 数据管理 → 自动本地备份」中调整。'),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => _choose(false),
          child: const Text('暂不开启'),
        ),
        FilledButton(
          onPressed: _saving ? null : () => _choose(true),
          child: const Text('开启自动备份'),
        ),
      ],
    ),
  );
}

class AutoBackupPage extends StatefulWidget {
  const AutoBackupPage({super.key, required this.controller});
  final AutoBackupController controller;
  @override
  State<AutoBackupPage> createState() => _AutoBackupPageState();
}

class _AutoBackupPageState extends State<AutoBackupPage> {
  List<LocalBackupEntry> _entries = [];
  String? _error;
  bool _loading = true;
  int _readGeneration = 0;
  AutoBackupController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_changed);
    _refresh(loadSettings: true);
  }

  @override
  void dispose() {
    controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    // Invalidate reads started before a backup or rotation changed the files.
    _readGeneration++;
    setState(() {});
    if (!controller.busy) unawaited(_refresh());
  }

  Future<void> _refresh({bool loadSettings = false}) async {
    if (!mounted || controller.busy) return;
    final generation = ++_readGeneration;
    try {
      if (loadSettings || !controller.loaded) await controller.load();
      if (!mounted || generation != _readGeneration) return;
      final entries = await controller.storage.list();
      if (mounted && generation == _readGeneration) {
        setState(() {
          _entries = entries;
          _error = null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && generation == _readGeneration) {
        setState(() {
          _error = '无法读取本地备份，请重试。';
          _loading = false;
        });
      }
    }
  }

  Future<void> _act(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('操作未完成，请检查存储空间或稍后重试。')));
      }
    }
    await _refresh();
  }

  String _time(DateTime time) =>
      '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  Future<void> _restore(LocalBackupEntry entry) async {
    final incremental = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('恢复此自动备份？'),
        content: Text(
          '${_time(entry.createdAt)}\n\n增量恢复保留本机已有记录，只补入缺失数据；覆盖恢复会替换本机现有养殖数据。照片一起恢复。\n\n恢复前会保存回退副本，可在数据管理中撤销上一次恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('覆盖恢复'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('增量恢复'),
          ),
        ],
      ),
    );
    if (incremental == null || !mounted) return;
    await _act(
      () => controller.withBackup(() async {
        await runBusyTask(
          context,
          () => controller.storage.restore(entry, incremental: incremental),
          message: '正在恢复备份，请稍候…',
        );
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('恢复完成，可在数据管理中撤销。')));
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('自动本地备份')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(autoBackupExplanation),
        const SizedBox(height: 12),
        if (!controller.storage.supported)
          const Text('网页版不支持自动本地备份，请在手机 App 中使用。'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('自动备份'),
          subtitle: const Text('关闭后保留已有备份'),
          value: controller.enabled,
          onChanged:
              _loading || controller.busy || !controller.storage.supported
              ? null
              : (value) => _act(() async {
                  await controller.setEnabled(value);
                  if (value) await controller.run(force: true);
                }),
        ),
        if (controller.lastSuccess != null)
          Text('最近完成：${_time(controller.lastSuccess!)}'),
        if (controller.error != null)
          Text(
            controller.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (_error != null)
          TextButton(onPressed: _refresh, child: const Text('重新读取')),
        if (_loading || controller.busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          ),
        FilledButton.icon(
          onPressed: !controller.enabled || controller.busy || _loading
              ? null
              : () => _act(() => controller.run(force: true)),
          icon: const Icon(Icons.backup_outlined),
          label: const Text('立即备份'),
        ),
        const SizedBox(height: 24),
        Text('本机备份', style: Theme.of(context).textTheme.titleMedium),
        if (!_loading && _entries.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text('还没有自动备份。开启后将生成第一份。'),
          ),
        for (final entry in _entries)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _time(entry.createdAt),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    '${(entry.bytes / 1024 / 1024).toStringAsFixed(2)} MB · 记录与照片',
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: controller.busy
                            ? null
                            : () => _act(
                                () => controller.withBackup(() async {
                                  final saved = await controller.storage.export(
                                    entry,
                                  );
                                  if (context.mounted && saved) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('备份已导出。')),
                                    );
                                  }
                                }),
                              ),
                        icon: const Icon(Icons.save_alt),
                        label: const Text('导出到应用外'),
                      ),
                      TextButton(
                        onPressed: controller.busy
                            ? null
                            : () => _restore(entry),
                        child: const Text('恢复'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
