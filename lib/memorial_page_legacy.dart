part of 'memorial_page.dart';

extension _LegacyMemorialLayout on _MemorialPageState {
  Widget _legacyMemorialCard(Memorial item, {bool grouped = false}) {
    final tile = ListTile(
      contentPadding: const EdgeInsets.all(16),
      leading: const TombstoneIcon(size: 44),
      title: Text(item.name),
      subtitle: Text(
        '${item.kind.epitaph}\n${item.species ?? item.kind.label} · ${item.diedOn == null ? '日期未填写' : chineseDate(item.diedOn!)}',
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MemorialDetailPage(
            memorialId: item.id,
            onOpenColony: widget.onOpenColony,
          ),
        ),
      ),
    );
    return grouped ? tile : Card(child: tile);
  }

  Widget _legacyGroupCard(
    MapEntry<String, List<Memorial>> group,
    Map<String, String> colonyNames,
  ) {
    final title = group.key.isEmpty
        ? '未关联蚁群'
        : colonyNames[group.key] ?? '已删除的蚁群';
    final expanded = _expandedGroups.contains(group.key);
    void toggle() => _refreshLegacy(() {
      if (expanded) {
        _expandedGroups.remove(group.key);
      } else {
        _expandedGroups.add(group.key);
      }
    });
    return Card(
      child: Column(
        children: [
          ListTile(
            title: Text(title),
            subtitle: Text('${group.value.length} 条纪念'),
            trailing: IconButton(
              tooltip: '${expanded ? '折叠' : '展开'}$title',
              onPressed: toggle,
              icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
            ),
            onTap: toggle,
          ),
          if (expanded)
            for (final item in group.value) ...[
              const Divider(height: 1),
              _legacyMemorialCard(item, grouped: true),
            ],
        ],
      ),
    );
  }

  Widget _buildLegacy(BuildContext context) => Scaffold(
    floatingActionButton: MenuAnchor(
      alignmentOffset: const Offset(0, 8),
      consumeOutsideTap: true,
      menuChildren: [
        MenuItemButton(
          leadingIcon: const TombstoneIcon(size: 24),
          onPressed: () => _add(),
          child: const Text('单独添加'),
        ),
        MenuItemButton(
          leadingIcon: const TombstoneIcon(size: 24),
          onPressed: () => _add(wholeColony: true),
          child: const Text('整群移入'),
        ),
      ],
      builder: (context, controller, child) => FloatingActionButton(
        heroTag: 'memorial-add',
        tooltip: '添加纪念',
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        child: const TombstoneIcon(size: 28),
      ),
    ),
    body:
        FutureBuilder<
          ({List<Memorial> memorials, Map<String, String> colonyNames})
        >(
          future: _items,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: TextButton(
                  onPressed: () => _refreshLegacy(_reload),
                  child: const Text('加载失败，点击重试'),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data!;
            final items = data.memorials;
            final groupingControl = Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilterChip(
                  label: const Text('按蚁群折叠'),
                  selected: _grouped,
                  onSelected: _savingGrouping ? null : _setGrouped,
                ),
              ),
            );
            if (items.isEmpty) {
              return Column(
                children: [
                  groupingControl,
                  const Expanded(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TombstoneIcon(size: 64),
                            SizedBox(height: 16),
                            Text('为逝去的小生命留一份纪念'),
                            SizedBox(height: 8),
                            Text(
                              '纪念每一位渺小却不屈、奋战至最后一息的勇士，\n'
                              '纪念每一位勤勉而坚韧、为族群倾尽一生的君主，\n'
                              '纪念每一个尚未羽化、便早早沉睡的小小生命，\n'
                              '纪念每一个曾繁盛如星，终湮没于历史长河的文明。\n\n'
                              '它们无声地来过，却曾竭尽全力地活着。',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }
            final groups = <String, List<Memorial>>{};
            for (final item in items) {
              groups.putIfAbsent(item.colonyId ?? '', () => []).add(item);
            }
            final grouped = groups.entries.toList();
            return Column(
              children: [
                groupingControl,
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                    itemCount: _grouped ? grouped.length : items.length,
                    itemBuilder: (context, index) => _grouped
                        ? _legacyGroupCard(grouped[index], data.colonyNames)
                        : _legacyMemorialCard(items[index]),
                  ),
                ),
              ],
            );
          },
        ),
  );
}

extension _LegacyMemorialDetailLayout on _MemorialDetailPageState {
  Widget _buildLegacyDetail(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('纪念详情')),
    body: FutureBuilder<_MemorialDetail>(
      future: _detail,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: () => _refreshLegacy(_reload),
              child: const Text('加载失败，点击重试'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final detail = snapshot.data!;
        final item = detail.item;
        if (item == null) return const Center(child: Text('这份纪念已移除'));
        final colony = detail.colony;
        final ended = detail.related.where(
          (m) => m.kind == MemorialKind.colony,
        );
        Widget paragraph(String title, String? value) => value == null
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    Text(value),
                  ],
                ),
              );
        final content = ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Center(child: TombstoneIcon(size: 80)),
            const SizedBox(height: 16),
            Center(
              child: Text(
                item.name,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                item.kind.epitaph,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '${item.kind.label} · ${item.species ?? '品种未填写'}',
                textAlign: TextAlign.center,
              ),
            ),
            Center(
              child: Text(
                item.diedOn == null ? '日期未填写' : chineseDate(item.diedOn!),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.ios_share),
              label: const Text('生成纪念分享图'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => MemorialSharePage(memorial: item),
                ),
              ),
            ),
            paragraph('留给它的话', item.farewell),
            if (colony != null) ...[
              const SizedBox(height: 20),
              Card(
                margin: EdgeInsets.zero,
                elevation: 0,
                color: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outline
                        .withValues(alpha: 0.55),
                  ),
                ),
                child: ListTile(
                  title: Text('关联蚁群 · ${colony.name}'),
                  subtitle: Text(colony.archived ? '整群已结束 · 档案与日记保留' : '仍在饲养中'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await widget.onOpenColony(context, colony.id);
                    if (mounted) _refreshLegacy(_reload);
                  },
                ),
              ),
              if (item.kind == MemorialKind.queen && !colony.archived)
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _openForm(colony: colony),
                  icon: const TombstoneIcon(size: 20),
                  label: const Text('记录后续：整群结束'),
                ),
              if (item.kind == MemorialKind.queen && ended.isNotEmpty)
                paragraph(
                  '后续结局',
                  '蚁群已于${ended.first.diedOn == null ? '日期未填写时' : chineseDate(ended.first.diedOn!)}结束，完整故事保存在下方关联纪念中。',
                ),
            ],
            if (detail.related.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('同一蚁群的纪念', style: Theme.of(context).textTheme.titleMedium),
              for (final related in detail.related)
                ListTile(
                  leading: const TombstoneIcon(),
                  title: Text(related.name),
                  subtitle: Text(
                    '${related.kind.label} · ${related.diedOn == null ? '日期未填写' : chineseDate(related.diedOn!)}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => MemorialDetailPage(
                          memorialId: related.id,
                          onOpenColony: widget.onOpenColony,
                        ),
                      ),
                    );
                    if (mounted) _refreshLegacy(_reload);
                  },
                ),
            ],
            paragraph('离世原因', item.cause),
            paragraph('最后的观察', item.observation),
            paragraph('这次学到了什么', item.lesson),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: _busy ? null : () => _openForm(item: item),
              child: const Text('编辑纪念'),
            ),
            if (item.kind == MemorialKind.colony && colony != null)
              TextButton(
                onPressed: _busy ? null : () => _remove(item, restore: true),
                child: const Text('恢复到饲养列表'),
              )
            else
              TextButton(
                onPressed: _busy ? null : () => _remove(item),
                child: const Text('删除纪念'),
              ),
          ],
        );
        final backgroundColor = Theme.of(context).scaffoldBackgroundColor;
        final isQueen = item.kind == MemorialKind.queen;
        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRect(
                        child: FractionalTranslation(
                          translation: isQueen
                              ? const Offset(0, 0.22)
                              : Offset.zero,
                          child: Opacity(
                            opacity: 0.45,
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: FractionallySizedBox(
                                widthFactor: 1,
                                heightFactor: 1,
                                child: Image.asset(
                                  memorialArtworkAsset(item.kind),
                                  fit: BoxFit.cover,
                                  alignment: Alignment.bottomCenter,
                                  errorBuilder: (_, _, _) =>
                                      const SizedBox.shrink(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: isQueen
                                ? [
                                    backgroundColor,
                                    backgroundColor.withValues(alpha: 0.96),
                                    backgroundColor.withValues(alpha: 0.15),
                                    backgroundColor.withValues(alpha: 0.24),
                                  ]
                                : [
                                    backgroundColor,
                                    backgroundColor.withValues(alpha: 0.9),
                                    backgroundColor.withValues(alpha: 0.45),
                                    backgroundColor.withValues(alpha: 0.15),
                                  ],
                            stops: isQueen
                                ? const [0, 0.45, 0.7, 1]
                                : const [0, 0.28, 0.7, 1],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            content,
          ],
        );
      },
    ),
  );
}
