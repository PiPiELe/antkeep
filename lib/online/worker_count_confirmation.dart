import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The model only sees photographed workers. The user must supply the colony total.
Future<int?> confirmWorkerTotal(
  BuildContext context, {
  required int visibleCount,
  required bool uncertain,
}) => showDialog<int>(
  context: context,
  builder: (_) => _WorkerCountConfirmation(
    visibleCount: visibleCount,
    uncertain: uncertain,
  ),
);

class _WorkerCountConfirmation extends StatefulWidget {
  const _WorkerCountConfirmation({
    required this.visibleCount,
    required this.uncertain,
  });

  final int visibleCount;
  final bool uncertain;

  @override
  State<_WorkerCountConfirmation> createState() =>
      _WorkerCountConfirmationState();
}

class _WorkerCountConfirmationState extends State<_WorkerCountConfirmation> {
  final _form = GlobalKey<FormState>();
  final _total = TextEditingController();

  @override
  void dispose() {
    _total.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('AI 识别结果'),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('照片中可见工蚁约 ${widget.visibleCount} 只。'),
            if (widget.uncertain) const Text('画面有遮挡或模糊，识别结果可能不准确。'),
            const SizedBox(height: 12),
            const Text('可见数量不等于整群总数。请把未拍到的工蚁也计入；无法确认时可只查看结果，不填写日记数量。'),
            const SizedBox(height: 8),
            const Text('填写后本次表单使用“当前总数”模式，后续日记的默认录入模式不变。'),
            const SizedBox(height: 16),
            TextFormField(
              controller: _total,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '你确认的当前工蚁总数',
                helperText: '留空不会修改日记数量',
              ),
              validator: (value) {
                final number = int.tryParse(value?.trim() ?? '');
                if (number == null || number < 0 || number > 1000000) {
                  return '请输入 0～1000000 的整数';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('仅查看结果'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState?.validate() != true) return;
          Navigator.pop(context, int.parse(_total.text.trim()));
        },
        child: const Text('填入我确认的总数'),
      ),
    ],
  );
}
