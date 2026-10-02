import 'package:flutter/material.dart';

import '../domain/models.dart';
import 'online_api.dart';
import 'online_controller.dart';
import 'online_widgets.dart';

class InventoryPushPage extends StatefulWidget {
  const InventoryPushPage({
    super.key,
    required this.controller,
    required this.loadItems,
  });
  final OnlineController controller;
  final Future<List<InventoryItem>> Function() loadItems;

  @override
  State<InventoryPushPage> createState() => _InventoryPushPageState();
}

class _InventoryPushPageState extends State<InventoryPushPage> {
  List<InventoryItem> _items = [];
  final Set<String> _selected = {};
  Map<String, dynamic>? _status;
  String? _statusUser, _message;
  bool _loading = true, _submitting = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _message = null;
      _status = null;
    });
    final userId = widget.controller.user?.id;
    try {
      final items = await widget.loadItems();
      if (!mounted) return;
      setState(() {
        _items = items;
        _selected.retainAll(items.map((item) => item.id));
      });
      final status = widget.controller.enabled && userId != null
          ? await widget.controller.inventoryPushStatus()
          : null;
      if (!mounted) return;
      setState(() {
        _status = status;
        _statusUser = userId;
      });
    } catch (error) {
      if (mounted) setState(() => _message = _errorText(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _errorText(Object error) =>
      error is ApiFailure ? error.message : '暂时无法完成操作，请检查网络后刷新状态重试。';

  Future<void> _submit() async {
    if (_submitting || _selected.isEmpty) return;
    final userId = widget.controller.user?.id;
    final items = _items.where((item) => _selected.contains(item.id)).toList();
    setState(() => _submitting = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认推送物品数据'),
          content: Text(
            '将向 B 端推送所选的 ${items.length} 条物品数据，包括名称、分组、购买状态、数量、购入价和日期、有效期信息。成功后今天不能再次推送。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认推送'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      if (widget.controller.user?.id != userId) return;
      final receipt = await widget.controller.pushInventory(items);
      if (!mounted) return;
      setState(() {
        _status = {
          'date': receipt['date'],
          'pushedToday': true,
          'itemCount': receipt['itemCount'],
        };
        _statusUser = userId;
        _message = '推送成功，B 端已收到 ${receipt['itemCount']} 条物品数据。';
      });
    } catch (error) {
      // A timeout can happen after the server commits. Read back the status
      // before letting the user retry; never consume quota on this device.
      Map<String, dynamic>? status;
      try {
        status = await widget.controller.inventoryPushStatus();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _status = status;
        _statusUser = userId;
        _message = status?['pushedToday'] == true
            ? 'B 端确认今日已收到 ${status!['itemCount']} 条物品数据，今天不能再次推送。'
            : _errorText(error);
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final locked = _loading || _submitting || controller.busy;
      final knownStatus = _status != null && _statusUser == controller.user?.id;
      final pushed = knownStatus && _status!['pushedToday'] == true;
      return Scaffold(
        appBar: AppBar(
          title: const Text('数据推送'),
          actions: [
            IconButton(
              tooltip: '刷新推送状态',
              onPressed: locked ? null : _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: !controller.enabled
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('请先在设置中切换到在线版，再登录并选择物品推送。'),
                ),
              )
            : controller.user == null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('登录后可推送物品栏数据，每个账号每天一次。'),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: locked
                          ? null
                          : () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      LoginPage(controller: controller),
                                ),
                              );
                              if (mounted) await _reload();
                            },
                      child: const Text('登录 / 注册'),
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '物品栏 · ${controller.user!.username}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '勾选需要推送的物品，单次最多 200 条。由服务端按北京时间限制每天成功推送一次，零点后可再次推送。',
                        ),
                        const SizedBox(height: 8),
                        Text(
                          knownStatus
                              ? '${_status!['date']} · ${pushed ? '今日已推送 ${_status!['itemCount']} 条' : '今日尚未推送'}'
                              : '请刷新并确认今日推送状态。',
                        ),
                        if (_message != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _message!,
                              key: const Key('push-message'),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_loading) const LinearProgressIndicator(),
                  CheckboxListTile(
                    title: Text('全选（${_selected.length}/${_items.length}）'),
                    value:
                        _items.isNotEmpty && _selected.length == _items.length,
                    onChanged:
                        locked ||
                            pushed ||
                            _items.isEmpty ||
                            _items.length > 200
                        ? null
                        : (value) => setState(() {
                            _selected.clear();
                            if (value == true) {
                              _selected.addAll(_items.map((item) => item.id));
                            }
                          }),
                  ),
                  Expanded(
                    child: _items.isEmpty && !_loading
                        ? const Center(child: Text('物品栏暂无数据'))
                        : ListView.builder(
                            itemCount: _items.length,
                            itemBuilder: (context, index) {
                              final item = _items[index];
                              return CheckboxListTile(
                                key: ValueKey(item.id),
                                title: Text(item.fullName),
                                subtitle: Text(
                                  '${item.purchased ? '已购' : '未购'} · 数量 ${item.quantity ?? '未填写'} · 购入价 ${item.purchasePriceText ?? '未填写'}',
                                ),
                                value: _selected.contains(item.id),
                                onChanged: locked || pushed
                                    ? null
                                    : (value) => setState(() {
                                        if (value == true) {
                                          if (_selected.length >= 200) {
                                            _message = '单次最多选择 200 条物品。';
                                            return;
                                          }
                                          _selected.add(item.id);
                                        } else {
                                          _selected.remove(item.id);
                                        }
                                      }),
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
                          icon: const Icon(Icons.cloud_upload_outlined),
                          onPressed:
                              locked ||
                                  pushed ||
                                  !knownStatus ||
                                  _selected.isEmpty
                              ? null
                              : _submit,
                          label: Text(
                            _submitting
                                ? '正在推送…'
                                : pushed
                                ? '今日已推送'
                                : '推送所选 ${_selected.length} 条',
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      );
    },
  );
}
