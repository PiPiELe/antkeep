import 'package:flutter/material.dart';

import 'data/app_database.dart';
import 'date_display.dart';
import 'domain/milestone.dart';
import 'milestone_page.dart';

class MilestonesOverviewPage extends StatefulWidget {
  const MilestonesOverviewPage({super.key, required this.active});

  final bool active;

  @override
  State<MilestonesOverviewPage> createState() => _MilestonesOverviewPageState();
}

class _MilestonesOverviewPageState extends State<MilestonesOverviewPage> {
  late Future<List<({Milestone milestone, String colonyName})>> _items =
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

  Future<void> _openMilestones(Milestone milestone) async {
    try {
      final colony = await AppDatabase.instance.findColony(milestone.colonyId);
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
  Widget build(BuildContext context) => FutureBuilder(
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
        return const Center(child: Text('还没有里程碑，可在蚁群详情中添加。'));
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
                      '${item.colonyName} · ${chineseDate(milestone.occurredAt)}',
                    ),
                    if (milestone.note?.isNotEmpty == true)
                      Text(
                        milestone.note!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openMilestones(milestone),
              ),
            );
          },
        ),
      );
    },
  );
}
