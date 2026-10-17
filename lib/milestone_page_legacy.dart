part of 'milestone_page.dart';

extension _ClassicMilestoneForm on _MilestoneFormPageState {
  Widget _buildClassicForm(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.milestone == null ? '添加里程碑' : '编辑里程碑')),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(_saving ? '保存中…' : '保存里程碑'),
        ),
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _title,
          maxLength: 80,
          decoration: const InputDecoration(labelText: '里程碑标题'),
          onChanged: (_) => _refreshLegacy(() {}),
        ),
        if (_colonies != null)
          FutureBuilder<List<Colony>>(
            future: _colonies,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text('加载蚁群失败：${snapshot.error}');
              }
              if (!snapshot.hasData) {
                return const LinearProgressIndicator();
              }
              return DropdownButtonFormField<String?>(
                initialValue: _selectedColonyId,
                decoration: const InputDecoration(labelText: '关联蚁群（可选）'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('不关联蚁群'),
                  ),
                  for (final colony in snapshot.data!)
                    DropdownMenuItem<String?>(
                      value: colony.id,
                      child: Text(colony.name),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (value) => _refreshLegacy(() {
                        _selectedColonyId = value;
                        _selectedColony = value == null
                            ? null
                            : snapshot.data!.firstWhere(
                                (colony) => colony.id == value,
                              );
                        if (value == null) _syncDiary = false;
                      }),
              );
            },
          ),
        if (widget.milestone == null &&
            (widget.colony != null || _selectedColonyId != null))
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('同步一条蚁群日记'),
            subtitle: const Text('保存为观察日记，记录里程碑标题和说明。'),
            value: _syncDiary,
            onChanged: _saving
                ? null
                : (value) => _refreshLegacy(() => _syncDiary = value ?? false),
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _saving ? null : _pickDate,
          icon: const Icon(Icons.calendar_today_outlined),
          label: Text('发生日期：${chineseDate(_occurredAt)}'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('记录具体时间'),
          value: _hasTime,
          onChanged: _saving ? null : _setTime,
        ),
        if (_hasTime)
          OutlinedButton.icon(
            onPressed: _saving ? null : () => _setTime(true),
            icon: const Icon(Icons.schedule),
            label: Text(
              '具体时间：${TimeOfDay.fromDateTime(_occurredAt).format(context)}',
            ),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          maxLength: 2000,
          maxLines: 5,
          decoration: const InputDecoration(labelText: '里程碑说明（可选）'),
          onChanged: (_) => _refreshLegacy(() {}),
        ),
        const SizedBox(height: 20),
        Text('选择石刻画面', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final artwork in MilestoneArtwork.values) ...[
                ChoiceChip(
                  label: Text(artwork.label),
                  selected: _artwork == artwork,
                  onSelected: _saving
                      ? null
                      : (_) => _refreshLegacy(() => _artwork = artwork),
                ),
                if (artwork != MilestoneArtwork.values.last)
                  const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _saving ? null : _pickPhoto,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(
                  _selectedPhotoBytes != null ||
                          (!_removePhoto && widget.milestone?.photoPath != null)
                      ? '更换自己的照片'
                      : '添加自己的照片（可选）',
                ),
              ),
            ),
            if (_selectedPhotoBytes != null ||
                (!_removePhoto && widget.milestone?.photoPath != null))
              IconButton(
                tooltip: '移除照片',
                onPressed: _saving
                    ? null
                    : () => _refreshLegacy(() {
                        _selectedPhoto = null;
                        _selectedPhotoBytes = null;
                        _removePhoto = true;
                      }),
                icon: const Icon(Icons.delete_outline),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: MilestonePoster(
              colony: widget.colony ?? _selectedColony,
              milestone: Milestone(
                id: widget.milestone?.id ?? 'preview',
                colonyId: widget.colony?.id ?? _selectedColonyId,
                title: _title.text.trim().isEmpty ? '里程碑标题' : _title.text,
                note: _note.text.trim().isEmpty ? null : _note.text,
                occurredAt: _occurredAt,
                createdAt: widget.milestone?.createdAt ?? DateTime.now(),
                artwork: _artwork,
                photoPath: _removePhoto ? null : widget.milestone?.photoPath,
              ),
              artwork: _artwork,
              photoBytes: _selectedPhotoBytes,
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text('里程碑本身不参与日记和数量统计；若同步观察日记，新增的日记会计入篇数。'),
      ],
    ),
  );
}
