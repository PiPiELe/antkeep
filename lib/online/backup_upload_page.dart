import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../data/backup_service.dart';
import '../data/local_media_store.dart';
import 'online_api.dart';
import 'online_controller.dart';

class BackupUploadPage extends StatefulWidget {
  const BackupUploadPage({super.key, required this.controller});
  final OnlineController controller;

  @override
  State<BackupUploadPage> createState() => _BackupUploadPageState();
}

class _BackupUploadPageState extends State<BackupUploadPage> {
  bool _loading = false, _uploading = false;
  String? _message, _loadedUser;
  List<Map<String, dynamic>> _uploads = [];
  int _totalBytes = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sessionChanged);
    _sessionChanged();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sessionChanged);
    super.dispose();
  }

  void _sessionChanged() {
    final user = widget.controller.enabled ? widget.controller.user?.id : null;
    if (user == _loadedUser) return;
    _loadedUser = user;
    if (user == null) {
      setState(() {
        _uploads = [];
        _totalBytes = 0;
      });
    } else {
      _reload();
    }
  }

  Future<bool> _reload() async {
    if (_loadedUser == null) return false;
    final userId = _loadedUser;
    setState(() => _loading = true);
    try {
      final response = await widget.controller.backupUploads();
      if (!mounted || userId != _loadedUser) return false;
      setState(() {
        _uploads = (response['items'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        _totalBytes = response['totalBytes'] as int;
      });
      return true;
    } catch (error) {
      if (mounted && userId == _loadedUser) {
        setState(
          () => _message = error is ApiFailure ? error.message : '暂时无法读取上传记录。',
        );
      }
      return false;
    } finally {
      if (mounted && userId == _loadedUser) setState(() => _loading = false);
    }
  }

  Future<void> _upload() async {
    if (_uploading || _loadedUser == null) return;
    final confirmedUserId = _loadedUser!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('上传当前备份？'),
        content: const Text(
          '将把本机蚁群、日记、物品和照片打包上传到当前账号。'
          '服务端会保存原始 ZIP；管理员只可查看上传时间、容量并删除。'
          '目前不支持从服务端下载或恢复，请继续保留本地导出的备份。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认上传'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (widget.controller.user?.id != confirmedUserId) {
      setState(() => _message = '账号状态已变化，请重新确认备份上传。');
      return;
    }
    setState(() {
      _uploading = true;
      _message = null;
    });
    try {
      await BackupService(
        AppDatabase.instance,
        LocalMediaStore.instance,
      ).uploadBackup(widget.controller, expectedUserId: confirmedUserId);
      if (!mounted) return;
      final refreshed = await _reload();
      if (mounted) {
        setState(
          () => _message = refreshed
              ? '账号存档上传成功；目前不能从账号恢复，请保留本地备份。'
              : '账号存档上传成功，列表暂时无法刷新；请继续保留本地备份。',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = error is ApiFailure
              ? error.message.startsWith('账号状态已变化')
                    ? error.message
                    : '${error.message} 如连接中断，请刷新记录确认是否已保存。'
              : '上传结果未确认：$error。请刷新记录确认是否已保存。',
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> upload) async {
    if (_uploading || _loadedUser == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除云端备份？'),
        content: const Text('删除后无法从服务端恢复。已导出到本机的 ZIP 文件不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _uploading = true;
      _message = null;
    });
    try {
      await widget.controller.deleteBackup(upload['id'] as String);
      final refreshed = await _reload();
      if (mounted) {
        setState(
          () => _message = refreshed ? '云端备份已删除。' : '备份已删除，列表暂时无法刷新，请稍后重试。',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = error is ApiFailure ? error.message : '删除未完成：$error',
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  static String _size(num bytes) {
    if (bytes < 1024) return '${bytes.toInt()} B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _time(String value) {
    final date = DateTime.parse(value).toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.controller.user;
    return Scaffold(
      appBar: AppBar(title: const Text('账号备份存档')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '上传到蚁记账号',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    account == null
                        ? '请先开启在线模式并登录账号。'
                        : '当前账号：${account.username}',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '仅在你点击确认后上传账号存档。目前不支持从账号下载或恢复，换机请使用本地导出与恢复。单份最多 512 MB；账号最多保存 10 份、合计 2 GB。本机备份不会被删除。',
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: account == null || _uploading ? null : _upload,
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: Text(_uploading ? '正在生成并上传…' : '上传当前备份'),
                  ),
                ],
              ),
            ),
          ),
          if (_message != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(_message!)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  '上传记录',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                onPressed: _loading || account == null ? null : _reload,
                tooltip: '刷新上传记录',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (account != null)
            Text('共 ${_uploads.length} 份 · ${_size(_totalBytes)}'),
          if (_loading) const LinearProgressIndicator(),
          if (!_loading && _uploads.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('暂无上传记录。'),
            ),
          for (final upload in _uploads)
            Card(
              child: ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text(_size(upload['sizeBytes'] as num)),
                subtitle: Text(_time(upload['createdAt'] as String)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '删除云端备份',
                  onPressed: _uploading ? null : () => _delete(upload),
                ),
              ),
            ),
          const SizedBox(height: 12),
          const Text('上传记录仅供查看；目前不能从服务端下载或恢复备份。'),
        ],
      ),
    );
  }
}
