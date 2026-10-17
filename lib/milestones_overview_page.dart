import 'package:flutter/material.dart';

import 'data/app_database.dart';
import 'domain/milestone.dart';
import 'milestone_page.dart';
import 'milestone_share_page.dart';
import 'widgets/milestone_design.dart';

class MilestonesOverviewPage extends StatefulWidget {
  const MilestonesOverviewPage({super.key, required this.active});

  final bool active;

  @override
  State<MilestonesOverviewPage> createState() => _MilestonesOverviewPageState();
}

class _MilestonesOverviewPageState extends State<MilestonesOverviewPage> {
  bool _all = true;
  bool _newestFirst = true;
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

  Future<void> _add() async {
    final saved = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const MilestoneFormPage()));
    if (saved == true && mounted) _reload();
  }

  Future<void> _preview(Milestone milestone) async {
    try {
      final colony = milestone.colonyId == null
          ? null
          : await AppDatabase.instance.findColony(milestone.colonyId!);
      if (!mounted) return;
      if (milestone.colonyId != null && colony == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('蚁群不存在，无法查看里程碑')));
        _reload();
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              MilestoneSharePage(colony: colony, milestone: milestone),
        ),
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
  Widget build(BuildContext context) => Theme(
    data: MilestoneDesign.theme(context),
    child: ColoredBox(
      color: MilestoneDesign.background,
      child: Column(
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
                final allItems = snapshot.data!;
                final items = allItems.toList()
                  ..sort(
                    (a, b) => _newestFirst
                        ? b.milestone.occurredAt.compareTo(
                            a.milestone.occurredAt,
                          )
                        : a.milestone.occurredAt.compareTo(
                            b.milestone.occurredAt,
                          ),
                  );
                return RefreshIndicator(
                  onRefresh: () async {
                    _reload();
                    await _items;
                  },
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                    children: [
                      const Text(
                        '记录重要的时刻\n让每一个值得铭记的瞬间，都被永远铭刻',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: Color(0xffd6cbc0),
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const MilestoneHero(),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          ChoiceChip(
                            label: Text('全部 ${allItems.length}'),
                            selected: _all,
                            selectedColor: const Color(0xff87a4cf),
                            onSelected: (_) => setState(() => _all = true),
                          ),
                          const SizedBox(width: 6),
                          ChoiceChip(
                            label: Text('我的里程碑 ${allItems.length}'),
                            selected: !_all,
                            selectedColor: const Color(0xff87a4cf),
                            onSelected: (_) => setState(() => _all = false),
                          ),
                          const Spacer(),
                          ActionChip(
                            label: const Text('按时间'),
                            avatar: const Icon(Icons.schedule, size: 16),
                            onPressed: () =>
                                setState(() => _newestFirst = !_newestFirst),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: Text('还没有里程碑，添加一个值得铭记的成长节点吧。')),
                        ),
                      for (final item in items)
                        MilestoneListCard(
                          milestone: item.milestone,
                          onTap: () => _preview(item.milestone),
                        ),
                    ],
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
                  onPressed: _add,
                  icon: const Icon(Icons.add),
                  label: const Text('添加里程碑'),
                  style: FilledButton.styleFrom(
                    backgroundColor: MilestoneDesign.parchment,
                    foregroundColor: MilestoneDesign.background,
                    minimumSize: const Size(0, 48),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
