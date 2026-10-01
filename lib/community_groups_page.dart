import 'package:flutter/material.dart';

class CommunityGroupsPage extends StatelessWidget {
  const CommunityGroupsPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('交流群二维码')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('欢迎加入交流群，分享养蚁经验、反馈使用问题。'),
                const SizedBox(height: 8),
                Text(
                  '点击图片可放大，截图后在微信或抖音的扫一扫中从相册识别。'
                  '\n本页二维码标注有效期至 2026 年 10 月 8 日，请在到期前加入。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                const _GroupCard(
                  title: '微信交流群',
                  name: '蚂蚁 app-测试群',
                  asset: 'assets/community/wechat-group.jpg',
                ),
                const SizedBox(height: 16),
                const _GroupCard(
                  title: '抖音交流群',
                  name: '蚁记 测试沟通群',
                  asset: 'assets/community/douyin-group.jpg',
                  groupNumber: '816962303299',
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.title,
    required this.name,
    required this.asset,
    this.groupNumber,
  });

  final String title;
  final String name;
  final String asset;
  final String? groupNumber;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(name),
          if (groupNumber != null) SelectableText('群号：$groupNumber'),
          const SizedBox(height: 12),
          Semantics(
            button: true,
            label: '放大$title二维码',
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => Scaffold(
                    appBar: AppBar(title: Text(title)),
                    body: SafeArea(
                      child: InteractiveViewer(
                        minScale: 1,
                        maxScale: 4,
                        child: SizedBox.expand(
                          child: Image.asset(
                            asset,
                            fit: BoxFit.contain,
                            semanticLabel: '$title二维码，可双指缩放',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              child: Image.asset(
                asset,
                fit: BoxFit.contain,
                semanticLabel: '$title二维码',
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击放大 · 截图扫码入群',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}
