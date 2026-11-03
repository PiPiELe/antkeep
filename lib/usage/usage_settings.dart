import 'package:flutter/material.dart';

import 'usage_controller.dart';

const usageExplanation =
    '帮助我们了解有多少人在使用蚁记。开启后，在线版和离线版都会在联网使用时发送一个随机安装标识，服务端仅保留其哈希及首次、最近使用日期。不关联账号，不发送设备信息、养殖记录或照片。完全断网时不发送，历史使用不补报。可随时在「设置 → 帮助与反馈」关闭。';

Future<void> showUsageConsent(
  BuildContext context,
  UsageController controller,
) async {
  final allowed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: const Text('参与匿名使用统计？'),
      content: const Text(usageExplanation),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('不参与'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('同意参与'),
        ),
      ],
    ),
  );
  await controller.setConsent(allowed == true);
}

class UsageSettings extends StatelessWidget {
  const UsageSettings({super.key, required this.controller});
  final UsageController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => SwitchListTile(
      secondary: const Icon(Icons.bar_chart_outlined),
      title: const Text('匿名使用统计'),
      subtitle: Text(
        controller.configured
            ? '仅统计使用设备数量；在线版与离线版均适用。关闭后停止发送，已收到的匿名计数会保留。'
            : '当前版本未配置统计服务。',
      ),
      value: controller.enabled,
      onChanged: controller.saving || !controller.configured
          ? null
          : (value) async {
              try {
                if (value) {
                  await showUsageConsent(context, controller);
                } else {
                  await controller.setConsent(false);
                }
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('设置未能保存，请重试。')));
                }
              }
            },
    ),
  );
}
