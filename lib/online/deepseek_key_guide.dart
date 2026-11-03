import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Local illustrations stay available offline; only explicit taps open a site.
class DeepSeekKeyGuide extends StatelessWidget {
  const DeepSeekKeyGuide({super.key});

  Future<void> _open(BuildContext context, String url) async {
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Keep the guide and the user's input available on launch failure.
    }
    if (!opened && context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('无法打开浏览器'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('可以长按复制下方官方链接，在浏览器中打开：'),
              const SizedBox(height: 12),
              SelectableText(url),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    }
  }

  Widget _link(BuildContext context, String label, String url) =>
      TextButton.icon(
        onPressed: () => _open(context, url),
        icon: const Icon(Icons.open_in_new, size: 18),
        label: Text(label),
      );

  @override
  Widget build(BuildContext context) => Card.outlined(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      leading: Icon(
        Icons.menu_book_outlined,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: const Text('如何获取个人 API Key？'),
      subtitle: const Text('充值与创建密钥 · 四步图文教程'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '在 DeepSeek 官方平台创建自己的 API Key，并为账号充值调用额度。'
          '费用按实际 API 用量从余额扣除，无需向第三方购买密钥。',
        ),
        const SizedBox(height: 8),
        Text(
          '以下为操作示意图，并非官网截图；页面名称、认证要求和支付方式以官网实际显示为准。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const _GuideStep(
          number: 1,
          title: '登录官网，完成个人认证',
          icon: Icons.person_outline,
          route: ['开放平台', '注册 / 登录', '个人认证'],
          description:
              '打开 DeepSeek 开放平台，注册或登录自己的账号。'
              '按页面提示完成个人实名认证；认证信息只在官方页面填写。',
        ),
        _link(context, '打开 DeepSeek 开放平台', 'https://platform.deepseek.com/'),
        const _GuideStep(
          number: 2,
          title: '充值 API 调用额度',
          icon: Icons.account_balance_wallet_outlined,
          route: ['充值入口', '选择金额', '确认到账'],
          description:
              '在平台内找到充值入口，按需选择金额，使用页面支持的支付方式完成付款。'
              '建议先小额试用，付款后确认账户余额到账。充值金额和当前价格以官网为准。',
        ),
        _link(
          context,
          '查看官方价格与计费说明',
          'https://api-docs.deepseek.com/zh-cn/quick_start/pricing/',
        ),
        const _GuideStep(
          number: 3,
          title: '创建并复制 API Key',
          icon: Icons.key_outlined,
          route: ['API keys', '创建密钥', '复制并保存'],
          description:
              '打开 API keys 页面，选择创建密钥；如需填写名称，可命名为“蚁记”。'
              '创建后及时复制完整密钥并妥善保管，不要分享密钥或含密钥的截图。',
        ),
        _link(context, '打开官方密钥管理', 'https://platform.deepseek.com/api_keys'),
        const _GuideStep(
          number: 4,
          title: '回到蚁记，粘贴并保存',
          icon: Icons.phonelink_lock_outlined,
          route: ['个人密钥输入框', '粘贴 Key', '保存密钥'],
          description:
              '回到本页，将完整 API Key 粘贴到下方输入框，点击“保存密钥”'
              '（已配置时为“替换密钥”），阅读并确认使用风险。'
              '保存只代表已存入本机；实际能否调用，还取决于密钥有效性和账户可用余额。',
        ),
        const SizedBox(height: 8),
        const Text('遇到余额不足时，到官方平台检查充值结果；密钥无效时，核对是否复制完整或已被撤销。'),
        _link(context, '查看官方常见问题', 'https://api-docs.deepseek.com/zh-cn/faq/'),
      ],
    ),
  );
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({
    required this.number,
    required this.title,
    required this.icon,
    required this.route,
    required this.description,
  });

  final int number;
  final String title;
  final IconData icon;
  final List<String> route;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$number. $title', style: theme.textTheme.titleSmall),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 32, color: colors.primary),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (var i = 0; i < route.length; i++) ...[
                      if (i > 0)
                        Icon(
                          Icons.arrow_forward,
                          size: 16,
                          color: colors.primary,
                        ),
                      Text(route[i], style: theme.textTheme.labelLarge),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(description),
        ],
      ),
    );
  }
}
