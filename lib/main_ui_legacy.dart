part of 'main.dart';

extension _LegacyColonyForm on _ColonyFormPageState {
  Widget _legacySection({
    required IconData icon,
    required String title,
    String? hint,
    Widget? action,
    required List<Widget> children,
  }) => Card(
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              if (hint != null) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    hint,
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(fontSize: 10, height: 1.2),
                  ),
                ),
              ],
              if (action != null) ...[const Spacer(), action],
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    ),
  );

  Widget _buildLegacyForm(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.colony == null ? '新入手蚁群' : '编辑蚁群')),
    bottomNavigationBar: SafeArea(
      top: false,
      maintainBottomViewPadding: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '保存中…' : '保存蚁群'),
        ),
      ),
    ),
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _legacySection(
            icon: Icons.pest_control_outlined,
            title: '品种与昵称',
            action: TextButton(
              onPressed: _enterCustomSpecies,
              child: const Text('未收录？', style: TextStyle(fontSize: 10)),
            ),
            children: [
              _SearchableChoiceField(
                label: '品种分类/细分种类',
                hintText: '点击选择或搜索品种',
                value: [?_speciesFamily, ?_selectedSpecies].join(' / '),
                options: speciesOptions.keys.toList(),
                searchOptions: {
                  for (final entry in speciesOptions.entries)
                    for (final species in entry.value) species: entry.key,
                },
                onSelected: _selectFamily,
                onSearchSelected: _selectSpecies,
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const ValueKey('colony-name'),
                controller: _name,
                decoration: const InputDecoration(
                  labelText: '蚁群昵称 *',
                  hintText: '例如：红土一号',
                ),
                validator: (value) =>
                    _textOrNull(value ?? '') == null ? '请填写一个昵称' : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _legacySection(
            icon: Icons.bar_chart_outlined,
            title: '数量',
            hint: '档案起始数量，日记中的死亡数量会从此扣减',
            children: [
              DropdownButtonFormField<GrowthPath>(
                isExpanded: true,
                initialValue: _developmentPath,
                decoration: const InputDecoration(labelText: '发育模式'),
                items: [
                  for (final path in GrowthPath.values)
                    DropdownMenuItem(value: path, child: Text(path.label)),
                ],
                onChanged: (path) =>
                    _refreshLegacy(() => _developmentPath = path!),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _queens,
                      validator: widget.colony == null
                          ? _validateRequiredCount
                          : _validateCount,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: widget.colony == null ? '蚁后 *' : '蚁后',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _workers,
                      validator: widget.colony == null
                          ? _validateRequiredCount
                          : _validateCount,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: widget.colony == null ? '工蚁 *' : '工蚁',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _eggs,
                      validator: _validateCount,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '卵',
                        hintText: '可选',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _cocoons,
                      validator: _validateCount,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '蛹茧',
                        hintText: '可选',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _larvae,
                validator: _validateCount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '幼虫',
                  hintText: '可选，暂无请填 0',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '工蚁填 0 表示从新后开始养',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Checkbox(
                    value: _showSpecialized,
                    onChanged: (value) =>
                        _refreshLegacy(() => _showSpecialized = value ?? false),
                  ),
                  const Text('特化'),
                  if (_showSpecialized) ...[
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _specialized,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? '请输入特化数量'
                            : _validateCount(value),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '特化数量'),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _legacySection(
            icon: Icons.home_outlined,
            title: '巢体',
            children: [
              _SearchableChoiceField(
                label: '巢体类型（可选）',
                hintText: '点击搜索或选择巢体类型',
                value: _selectedNest,
                options: _nestTypeOptions,
                onSelected: (nest) =>
                    _refreshLegacy(() => _selectedNest = nest),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              controller: _environmentExpansion,
              initiallyExpanded: false,
              maintainState: true,
              leading: Icon(
                Icons.thermostat_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(
                '环境预警（可选）',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _targetTemperatureLower,
                        validator: (value) => _validateAlertLimit(
                          value,
                          _targetTemperature,
                          isLower: true,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: '温度下限 °C',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _targetTemperature,
                        validator: (value) => _validateAlertLimit(
                          value,
                          _targetTemperatureLower,
                          isLower: false,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: '温度上限 °C',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _targetHumidityLower,
                        validator: (value) => _validateAlertLimit(
                          value,
                          _targetHumidity,
                          isLower: true,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: '湿度下限 %',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _targetHumidity,
                        validator: (value) => _validateAlertLimit(
                          value,
                          _targetHumidityLower,
                          isLower: false,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: '湿度上限 %',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('超出范围时提醒', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _legacySection(
            icon: Icons.receipt_long_outlined,
            title: '来源与补充信息',
            children: [
              TextFormField(
                controller: _source,
                decoration: InputDecoration(
                  labelText: '来源（可选）',
                  hintText: '商户 / 地点 / 赠送人',
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 24,
                        child: VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: '选择来源',
                        initialValue: _sourceType ?? '',
                        onSelected: (source) => _refreshLegacy(
                          () => _sourceType = _textOrNull(source),
                        ),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: '野采', child: Text('野采')),
                          PopupMenuItem(value: '网购', child: Text('网购')),
                          PopupMenuItem(value: '蚁友赠送', child: Text('蚁友赠送')),
                          PopupMenuItem(value: '', child: Text('不选择')),
                        ],
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 48),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_sourceType ?? '选择'),
                                const Icon(Icons.arrow_drop_down, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_wildCatchRecords != null) ...[
                const SizedBox(height: 12),
                _wildCatchField(),
              ],
              const SizedBox(height: 12),
              _PurchasePriceField(controller: _purchasePrice),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      icon: const Icon(Icons.calendar_today_outlined, size: 16),
                      label: Text(
                        _acquiredOn == null
                            ? '入手日期（可选）'
                            : '入手日期：${_date(_acquiredOn!)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: context,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                          initialDate: _acquiredOn ?? DateTime.now(),
                        );
                        if (date != null) {
                          _refreshLegacy(() => _acquiredOn = date);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      icon: const Icon(Icons.photo_outlined, size: 16),
                      label: Text(
                        _cover != null
                            ? '已选择封面照片'
                            : widget.colony?.coverPhotoPath != null
                            ? '更换封面照片'
                            : '添加封面照片',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: _saving ? null : _pickCover,
                    ),
                  ),
                ],
              ),
              if (_coverPreview != null) ...[
                const SizedBox(height: 12),
                _CoverPhotoPreview(image: _coverPreview!),
              ],
            ],
          ),
        ],
      ),
    ),
  );
}
