import 'package:flutter/material.dart';

import 'deepseek_key_guide.dart';
import 'online_api.dart';
import 'online_controller.dart';

class DeepSeekKeyPage extends StatefulWidget {
  const DeepSeekKeyPage({super.key, required this.controller});

  final OnlineController controller;

  @override
  State<DeepSeekKeyPage> createState() => _DeepSeekKeyPageState();
}

class _DeepSeekKeyPageState extends State<DeepSeekKeyPage> {
  final _input = TextEditingController();
  late final String? _userId = widget.controller.user?.id;
  bool? _configured;
  bool _busy = false;
  bool _revealed = false;
  bool _sessionChanged = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onSessionChanged);
    _load();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onSessionChanged);
    _input.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (_sessionChanged || widget.controller.user?.id == _userId) return;
    _input.clear();
    setState(() {
      _sessionChanged = true;
      _configured = null;
      _message = '账号已变化，请返回后重新打开密钥设置。';
    });
  }

  Future<void> _load() async {
    try {
      final configured = await widget.controller.hasPersonalDeepSeekKey();
      if (mounted && !_sessionChanged) setState(() => _configured = configured);
    } catch (error) {
      if (mounted && !_sessionChanged) setState(() => _message = _error(error));
    }
  }

  String _error(Object error) =>
      error is ApiFailure ? error.message : '无法操作本机密钥，请稍后重试。';

  Future<void> _save() async {
    if (_busy || _sessionChanged) return;
    if (_input.text.trim().isEmpty) {
      setState(() => _message = '请先输入 DeepSeek API Key。');
      return;
    }
    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认使用个人密钥？'),
          content: const SingleChildScrollView(
            child: Text(
              '请确认以下风险：\n\n'
              '• 每次识别会使用你的 DeepSeek 账号额度，可能产生由你承担的费用，请留意官方平台的用量和余额。\n\n'
              '• 识别时，个人密钥和所选照片会经蚁记在线服务转交 DeepSeek。请勿上传含有不愿交给第三方处理的内容。\n\n'
              '• 密钥属于敏感凭据。设备或在线服务若被攻破，密钥可能泄露；发现异常时应到 DeepSeek 平台撤销并更换密钥。仅在 App 中删除密钥不会使原密钥失效。',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('已了解风险，保存密钥'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted || _sessionChanged) return;
      setState(() => _busy = true);
      await widget.controller.savePersonalDeepSeekKey(_input.text);
      if (!mounted || _sessionChanged) return;
      _input.clear();
      setState(() {
        _configured = true;
        _message = '密钥已安全保存在本机，下次 AI 识别将优先使用。';
      });
    } catch (error) {
      if (mounted && !_sessionChanged) setState(() => _message = _error(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    if (_busy || _sessionChanged) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除个人密钥？'),
        content: const Text('删除后，AI 识别将使用在线服务提供的密钥（如已配置）。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _sessionChanged) return;
    setState(() => _busy = true);
    try {
      await widget.controller.deletePersonalDeepSeekKey();
      if (!mounted || _sessionChanged) return;
      setState(() {
        _configured = false;
        _message = '个人密钥已从本机删除。';
      });
    } catch (error) {
      if (mounted && !_sessionChanged) setState(() => _message = _error(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('DeepSeek API Key')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _sessionChanged
                    ? '账号已变化'
                    : _configured == null
                    ? '正在读取本机密钥状态…'
                    : _configured!
                    ? '当前账号已配置个人密钥'
                    : '当前账号未配置个人密钥',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Theme.of(context)
                                .colorScheme
                                .onErrorContainer,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '个人密钥使用风险',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onErrorContainer,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '识别将消耗你自己的 DeepSeek 额度，可能产生费用；密钥与所选照片会经蚁记服务转交 DeepSeek。密钥泄露时需到 DeepSeek 平台撤销，仅在本机删除不能使其失效。',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '密钥仅保存在本设备的安全存储中，按当前账号和在线服务地址区分。识别时会随所选照片发送到蚁记在线服务，由服务端转交 DeepSeek；服务端不保存个人密钥。未配置个人密钥时使用服务端密钥（如已提供）。',
              ),
              const SizedBox(height: 20),
              const DeepSeekKeyGuide(),
              const SizedBox(height: 16),
              TextField(
                controller: _input,
                enabled: !_busy && !_sessionChanged,
                obscureText: !_revealed,
                enableSuggestions: false,
                autocorrect: false,
                keyboardType: TextInputType.visiblePassword,
                maxLength: 256,
                decoration: InputDecoration(
                  labelText: _configured == true ? '替换个人密钥' : '输入个人密钥',
                  hintText: 'DeepSeek API Key',
                  suffixIcon: IconButton(
                    tooltip: _revealed ? '隐藏密钥' : '显示密钥',
                    onPressed: () => setState(() => _revealed = !_revealed),
                    icon: Icon(
                      _revealed
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: _busy || _sessionChanged ? null : _save,
                    child: Text(_configured == true ? '替换密钥' : '保存密钥'),
                  ),
                  if (_configured == true)
                    OutlinedButton(
                      onPressed: _busy || _sessionChanged ? null : _remove,
                      child: const Text('删除本机密钥'),
                    ),
                ],
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: LinearProgressIndicator(),
                ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(_message!),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
