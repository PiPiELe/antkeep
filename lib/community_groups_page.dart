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
                const Text('欢迎加入交流群，分享养蚁经验、反馈使用问题，也可以通过抖音联系我。'),
                const SizedBox(height: 8),
                Text(
                  '点击图片可放大，截图后在微信或抖音的扫一扫中从相册识别。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                const _QrCodeCard(
                  title: '微信交流群',
                  name: '蚂蚁 app-测试群',
                  asset: 'assets/community/wechat-group.jpg',
                  hint: '二维码已过期，待更新',
                ),
                const SizedBox(height: 16),
                const _QrCodeCard(
                  title: '抖音交流群',
                  name: '蚁记 测试沟通群',
                  asset: 'assets/community/douyin-group.jpg',
                  visibleImageSize: Size(840, 920),
                  accountLabel: '群号：816962303299',
                  hint: '有效期至 2026 年 10 月 25 日 · 点击放大扫码入群',
                ),
                const SizedBox(height: 16),
                const _QrCodeCard(
                  title: '蚁记抖音',
                  name: '蚁记',
                  asset: 'assets/community/douyin-antkeep.jpg',
                  visibleImageSize: Size(1125, 1370),
                  accountLabel: '抖音号：PiPi_Ele',
                  hint: '点击放大 · 截图后用抖音扫码关注',
                ),
                const SizedBox(height: 16),
                const _QrCodeCard(
                  title: '联系我（抖音）',
                  name: '皮皮吃不饱',
                  asset: 'assets/community/douyin-personal.jpg',
                  visibleImageSize: Size(1125, 1370),
                  accountLabel: '抖音号：PiPiELe',
                  hint: '点击放大 · 截图后用抖音扫码联系',
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _QrCodeCard extends StatelessWidget {
  const _QrCodeCard({
    required this.title,
    required this.name,
    required this.asset,
    this.accountLabel,
    this.visibleImageSize,
    required this.hint,
  });

  final String title;
  final String name;
  final String asset;
  final String? accountLabel;
  final Size? visibleImageSize;
  final String hint;

  Widget _image(String semanticLabel) {
    final size = visibleImageSize;
    if (size == null) {
      return Image.asset(
        asset,
        fit: BoxFit.contain,
        semanticLabel: semanticLabel,
      );
    }
    // Hide the original scan-instruction footer without changing QR pixels.
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: 0,
            maxHeight: double.infinity,
            child: Image.asset(
              asset,
              width: size.width,
              semanticLabel: semanticLabel,
            ),
          ),
        ),
      ),
    );
  }

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
          if (accountLabel != null) SelectableText(accountLabel!),
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
                          child: _image('$title二维码，可双指缩放'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              child: _image('$title二维码'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}
