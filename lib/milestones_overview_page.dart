import 'package:flutter/material.dart';

import 'data/app_database.dart';
import 'date_display.dart';
import 'domain/milestone.dart';
import 'milestone_page.dart';
import 'milestone_share_page.dart';

class MilestonesOverviewPage extends StatefulWidget {
  const MilestonesOverviewPage({super.key, required this.active});

  final bool active;

  @override
  State<MilestonesOverviewPage> createState() => _MilestonesOverviewPageState();
}

class _MilestonesOverviewPageState extends State<MilestonesOverviewPage> {
  late Future<List<({Milestone milestone, String? colonyName})>> _items =
      AppDatabase.instance.listAllMilestones();

  @override
  void didUpdateWidget(MilestonesOverviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _items = AppDatabase.instance.listAllMilestones();
    }
  }

  void _reload() => setState(() {
    _items = AppDatabase.instance.listAllMilestones();
  });

  Future<void> _edit([Milestone? milestone]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MilestoneFormPage(milestone: milestone),
      ),
    );
    if (saved == true && mounted) _reload();
  }

  Future<void> _delete(Milestone milestone) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除里程碑？'),
        content: Text('确定删除「${milestone.title}」吗？'),
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
    if (confirmed != true || !mounted) return;
    try {
      await AppDatabase.instance.deleteMilestone(milestone);
      if (mounted) _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
    }
  }

  Future<void> _openMilestones(Milestone milestone) async {
    if (milestone.colonyId == null) {
      await _edit(milestone);
      return;
    }
    try {
      final colony = await AppDatabase.instance.findColony(milestone.colonyId!);
      if (!mounted) return;
      if (colony == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('蚁群不存在，无法查看里程碑')));
        _reload();
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => MilestonePage(colony: colony)),
      );
      if (mounted) _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('打开里程碑失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: FutureBuilder(
          future: _items,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('加载里程碑失败：${snapshot.error}'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = snapshot.data!;
            if (items.isEmpty) {
              return const Center(child: Text('还没有里程碑，添加一个值得铭记的成长节点吧。'));
            }
            return RefreshIndicator(
              onRefresh: () async {
                _reload();
                await _items;
              },
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final milestone = item.milestone;
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.flag_outlined),
                      title: Text(milestone.title),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${item.colonyName == null ? '独立里程碑' : item.colonyName!} · ${chineseDate(milestone.occurredAt)}',
                          ),
                          if (milestone.note?.isNotEmpty == true)
                            Text(
                              milestone.note!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                      trailing: milestone.colonyId == null
                          ? PopupMenuButton<String>(
                              tooltip: '里程碑操作',
                              onSelected: (action) {
                                if (action == 'share') {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => MilestoneSharePage(
                                        milestone: milestone,
                                      ),
                                    ),
                                  );
                                } else if (action == 'delete') {
                                  _delete(milestone);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'share',
                                  child: Text('分享里程碑'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('删除里程碑'),
                                ),
                              ],
                            )
                          : const Icon(Icons.chevron_right),
                      onTap: () => _openMilestones(milestone),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: const Text('添加里程碑'),
            ),
          ),
        ),
      ),
    ],
  );
}
