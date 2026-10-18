import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_preferences.dart';
import 'domain/colony_tag.dart';

class ColonyTagSettingsPage extends StatefulWidget {
  const ColonyTagSettingsPage({super.key, required this.preferences});

  final AppPreferences preferences;

  @override
  State<ColonyTagSettingsPage> createState() => _ColonyTagSettingsPageState();
}

class _ColonyTagSettingsPageState extends State<ColonyTagSettingsPage> {
  late List<ColonyTag> _order = widget.preferences.colonyTagOrder;
  bool _saving = false;

  Future<void> _save(List<ColonyTag> order) async {
    if (_saving || listEquals(order, _order)) return;
    setState(() {
      _order = order;
      _saving = true;
    });
    try {
      await widget.preferences.setColonyTagOrder(order);
    } catch (_) {
      if (mounted) {
        setState(() => _order = widget.preferences.colonyTagOrder);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('标签顺序保存失败，已恢复原顺序，请重试')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _reorder(int oldIndex, int newIndex) {
    if (_saving) return;
    final order = [..._order];
    order.insert(newIndex, order.removeAt(oldIndex));
    _save(order);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('蚁群标签展示管理')),
    body: SafeArea(
      child: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        buildDefaultDragHandles: false,
        onReorderItem: _reorder,
        header: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('展示顺序', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              const Text('拖动右侧手柄调整顺序，自动保存。所有蚁群的列表与详情共用此顺序，仅显示符合条件的标签。'),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _saving || listEquals(_order, ColonyTag.values)
                    ? null
                    : () => _save(ColonyTag.values),
                icon: const Icon(Icons.restore),
                label: const Text('恢复默认顺序'),
              ),
              if (_saving) const LinearProgressIndicator(),
            ],
          ),
        ),
        itemCount: _order.length,
        itemBuilder: (context, index) {
          final tag = _order[index];
          return Card(
            key: ValueKey(tag),
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              leading: CircleAvatar(radius: 16, child: Text('${index + 1}')),
              title: Text(tag.label),
              subtitle: Text(tag.description),
              trailing: ReorderableDragStartListener(
                index: index,
                enabled: !_saving,
                child: Semantics(
                  label: '拖动排序：${tag.label}',
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.drag_handle),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
