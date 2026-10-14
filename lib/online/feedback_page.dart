import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'online_api.dart';
import 'online_controller.dart';
import 'online_widgets.dart';

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key, required this.controller});
  final OnlineController controller;

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final _content = TextEditingController();
  String _category = 'ISSUE';
  String? _pendingPayload, _pendingOperationId, _message;
  bool _submitting = false;

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || widget.controller.busy) return;
    final content = _content.text.trim();
    if (content.isEmpty || content.length > 2000) {
      setState(() => _message = '请填写 1–2000 字的反馈内容。');
      return;
    }
    final userId = widget.controller.user?.id;
    final payload = '$userId\u0000$_category\u0000$content';
    if (_pendingPayload != payload) {
      _pendingPayload = payload;
      _pendingOperationId = const Uuid().v4();
    }
    setState(() {
      _submitting = true;
      _message = null;
    });
    try {
      await widget.controller.submitFeedback(
        category: _category,
        content: content,
        operationId: _pendingOperationId!,
      );
      if (!mounted || widget.controller.user?.id != userId) return;
      setState(() {
        _content.clear();
        _pendingPayload = null;
        _pendingOperationId = null;
        _message = '已提交，感谢你的反馈。';
      });
    } catch (error) {
      if (!mounted || widget.controller.user?.id != userId) return;
      setState(
        () => _message = error is ApiFailure ? error.message : '提交失败，请稍后重试。',
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final online = widget.controller.enabled;
      final user = widget.controller.user;
      final locked = _submitting || widget.controller.busy;
      return Scaffold(
        appBar: AppBar(title: const Text('我想说')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  '使用时遇到了问题，或有更好的想法，都可以告诉我们。',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                if (!online)
                  const Text('「我想说」仅在线版可用。请先在设置 → 在线服务中切换到在线版。')
                else if (user == null) ...[
                  const Text('登录后可以提交反馈，反馈会关联到你的账号。'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: locked
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  LoginPage(controller: widget.controller),
                            ),
                          ),
                    child: const Text('登录 / 注册'),
                  ),
                ] else ...[
                  Text('提交账号：${user.username}'),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('使用问题'),
                        selected: _category == 'ISSUE',
                        onSelected: locked
                            ? null
                            : (_) => setState(() => _category = 'ISSUE'),
                      ),
                      ChoiceChip(
                        label: const Text('更好的想法'),
                        selected: _category == 'IDEA',
                        onSelected: locked
                            ? null
                            : (_) => setState(() => _category = 'IDEA'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _content,
                    enabled: !locked,
                    minLines: 6,
                    maxLines: 12,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      labelText: '想说的内容',
                      hintText: '请描述遇到的问题，或希望增加的功能。',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('只提交你填写的文字，不会附带蚁群、日记、照片或备份。'),
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Text(_message!, key: const Key('feedback-message')),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: locked ? null : _submit,
                    child: Text(_submitting ? '提交中…' : '提交反馈'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}
