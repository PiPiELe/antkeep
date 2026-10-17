part of 'milestone_share_page.dart';

extension _ClassicMilestoneShare on _MilestoneSharePageState {
  Widget _buildClassicShare(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('石刻预览'),
      actions: [
        if (_colony?.archived != true)
          IconButton(
            tooltip: '编辑里程碑',
            onPressed: _busy ? null : _edit,
            icon: const Icon(Icons.edit_outlined),
          ),
        if (_colony?.archived != true)
          PopupMenuButton<String>(
            tooltip: '更多操作',
            onSelected: (value) {
              if (value == 'delete') _delete();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('删除里程碑')),
            ],
          ),
      ],
    ),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            Expanded(
              child: Builder(
                builder: (buttonContext) => FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _export(buttonContext, share: true),
                  icon: const Icon(Icons.share_outlined),
                  label: Text(_busy ? '生成中…' : '转发分享'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Builder(
              builder: (buttonContext) => OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _export(buttonContext, share: false),
                icon: const Icon(Icons.download_outlined),
                label: const Text('保存图片'),
              ),
            ),
          ],
        ),
      ),
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: MilestonePoster(
                colony: _colony,
                milestone: _milestone,
                artwork: _milestone.artwork,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text('说明较长时，分享图显示摘要；里程碑原文仍完整保留。'),
        ],
      ),
    ),
  );
}
