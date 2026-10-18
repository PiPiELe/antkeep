part of 'inventory_page.dart';

Future<T?> _sheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Theme(data: _inventoryTheme(context), child: child),
    );

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.title,
    required this.children,
    required this.onSave,
    this.saveLabel = '保存修改',
    this.height = .72,
    this.busy = false,
    this.error,
    this.onDelete,
    this.cancelLabel = '取消',
    this.onCancel,
  });
  final String title;
  final List<Widget> children;
  final VoidCallback? onSave;
  final String saveLabel;
  final double height;
  final bool busy;
  final String? error;
  final VoidCallback? onDelete;
  final String cancelLabel;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        height: (MediaQuery.sizeOf(context).height * height).clamp(
          0,
          MediaQuery.sizeOf(context).height -
              MediaQuery.viewInsetsOf(context).bottom -
              MediaQuery.paddingOf(context).top,
        ),
        decoration: BoxDecoration(
          color: _palette(context).surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: _palette(context).line),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 9),
                  decoration: BoxDecoration(
                    color: _palette(context).muted.withValues(alpha: .6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 5, 10, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭',
                        onPressed: busy ? null : () => Navigator.pop(context),
                        icon: const Icon(Icons.close, size: 21),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: _palette(context).line),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (onDelete != null)
                        IconButton(
                          tooltip: '删除',
                          onPressed: busy ? null : onDelete,
                          icon: Icon(
                            Icons.delete_outline,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      Expanded(
                        flex: 2,
                        child: OutlinedButton(
                          onPressed: busy
                              ? null
                              : onCancel ?? () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 46),
                          ),
                          child: Text(cancelLabel),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 3,
                        child: FilledButton(
                          onPressed: busy ? null : onSave,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 46),
                          ),
                          child: Text(busy ? '正在保存…' : saveLabel),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _label(String text, {String? hint}) => Padding(
  padding: const EdgeInsets.only(top: 17, bottom: 8),
  child: Row(
    children: [
      Expanded(
        child: Text(
          text,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      if (hint != null) Text(hint, style: const TextStyle(fontSize: 10)),
    ],
  ),
);
Widget _divider(BuildContext context) => Padding(
  padding: const EdgeInsets.only(top: 18, bottom: 4),
  child: Divider(color: _palette(context).line),
);
String? _optional(String value) => value.trim().isEmpty ? null : value.trim();

Future<bool> _confirmDelete(BuildContext context, String message) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除？'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    ) ==
    true;

class _ItemEditor extends StatefulWidget {
  const _ItemEditor({this.items, this.templates = const []});
  final List<InventoryItem>? items;
  final List<ItemTemplate> templates;
  @override
  State<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<_ItemEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: widget.items?.first.productName,
  );
  late final _purpose = TextEditingController(
    text: widget.items?.first.purpose,
  );
  late String _category = widget.items?.first.categoryLabel ?? '工具';
  late String _icon = widget.items == null
      ? 'box'
      : _itemIcon(widget.items!.first);
  late bool _expiry = widget.items?.first.allowsExpiry ?? false;
  final _newSpecs = <({String name, String? note})>[];
  ItemTemplate? _template;
  String? _templateUnit;
  int? get _months => _template?.months ?? widget.items?.first.shelfLifeMonths;
  List<({String name, String? note})> get _draftSpecs => [
    if (_templateUnit != null && !_newSpecs.any((s) => s.name == _templateUnit))
      (name: _templateUnit!, note: null),
    ..._newSpecs,
  ];
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _purpose.dispose();
    super.dispose();
  }

  Future<void> _chooseTemplate() async {
    final selected = await showDialog<ItemTemplate>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择物品模板'),
        content: SizedBox(
          width: double.maxFinite,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.templates.length,
              itemBuilder: (context, index) {
                final template = widget.templates[index];
                return ListTile(
                  title: Text(template.name),
                  subtitle: Text(
                    '${template.category} · ${template.unit} · '
                    '${template.months == null ? '无默认有效期' : '保质期 ${template.months} 个月'}',
                  ),
                  onTap: () => Navigator.pop(context, template),
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _template = selected;
      _name.text = selected.name;
      _category = inventoryCategories.contains(selected.category)
          ? selected.category
          : defaultInventoryCategory(selected.name);
      _expiry = selected.months != null;
      _templateUnit = selected.unit;
    });
  }

  Future<void> _chooseIcon() async {
    final selected = await _sheet<String>(
      context,
      _IconPicker(selected: _icon),
    );
    if (selected != null && mounted) setState(() => _icon = selected);
  }

  Future<void> _addSpec() async {
    final spec = await _sheet<({String name, String? note})>(
      context,
      _SpecEditor(
        draftNames: {
          ..._draftSpecs.map((s) => s.name),
          ...?widget.items
              ?.where((i) => i.groupLabel != null)
              .map((i) => i.childLabel),
        },
      ),
    );
    if (spec != null && mounted) setState(() => _newSpecs.add(spec));
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final name = _name.text.trim();
      final existing = await AppDatabase.instance.listInventory();
      final ownIds = widget.items?.map((i) => i.id).toSet() ?? <String>{};
      if (existing.any(
        (i) => i.productName == name && !ownIds.contains(i.id),
      )) {
        throw StateError('该物品已存在，请在原物品中添加规格');
      }
      final original =
          widget.items ??
          [
            InventoryItem(
              id: const Uuid().v4(),
              name: name,
              purchased: false,
              createdAt: DateTime.now(),
              shelfLifeMonths: _months,
            ),
          ];
      final items = [
        for (final item in original)
          InventoryItem.fromMap({
            ...item.toMap(),
            'name': item.groupLabel == null ? name : item.childLabel,
            'group_name': item.groupLabel == null ? null : name,
            'purpose': _optional(_purpose.text),
            'category': _category,
            'icon_key': _icon,
            'supports_expiry': _expiry ? 1 : 0,
          }),
        for (final spec in _draftSpecs)
          InventoryItem(
            id: const Uuid().v4(),
            name: spec.name,
            groupName: name,
            purpose: _optional(_purpose.text),
            category: _category,
            iconKey: _icon,
            supportsExpiry: _expiry,
            shelfLifeMonths: _months,
            specNote: spec.note,
            purchased: false,
            createdAt: DateTime.now(),
          ),
      ];
      await AppDatabase.instance.saveInventoryCatalog(items);
      if (mounted) Navigator.pop(context, name);
    } catch (error) {
      if (mounted) setState(() => _error = _saveError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _SheetFrame(
    title: widget.items == null ? '新增物品' : '编辑物品',
    height: .86,
    busy: _busy,
    error: _error,
    onSave: _save,
    saveLabel: widget.items == null ? '保存物品' : '保存修改',
    children: [
      Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _muted(
              context,
              widget.items == null
                  ? '填写名称和分类即可创建。其他信息以后可以补充。'
                  : '调整物品资料；已有入手记录与历史有效期会保留。',
              size: 11,
            ),
            if (widget.items == null && widget.templates.isNotEmpty) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _chooseTemplate,
                icon: const Icon(Icons.playlist_add, size: 18),
                label: const Text('从模板填写'),
              ),
              _muted(context, '可选；填入名称、分类、单位规格和默认保质期。', size: 10),
            ],
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Semantics(
                  label: '选择物品图标',
                  button: true,
                  child: InkWell(
                    onTap: _chooseIcon,
                    child: Column(
                      children: [
                        _thumbnail(
                          context,
                          InventoryItem(
                            id: '',
                            name: '',
                            purchased: false,
                            createdAt: DateTime(2000),
                            iconKey: _icon,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _muted(context, '选择图标', size: 10),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('物品名称 *', style: TextStyle(fontSize: 12)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _name,
                        maxLength: 200,
                        decoration: const InputDecoration(
                          hintText: '例如：EPP 泡沫箱',
                          counterText: '',
                        ),
                        validator: (v) =>
                            (v?.trim().isEmpty ?? true) ? '请填写物品名称' : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            _label('分类 *'),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final category in inventoryCategories)
                  _choice(
                    context,
                    category,
                    _category == category,
                    () => setState(() => _category = category),
                  ),
              ],
            ),
            _label('用途', hint: '选填'),
            TextFormField(
              controller: _purpose,
              maxLength: 200,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: '例如：运输时保温',
                counterText: '',
              ),
            ),
            _divider(context),
            _label('规格管理（可选）'),
            _muted(context, '即使没有预设规格，也能在保存后添加', size: 10),
            if (widget.items != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final item in widget.items!.where(
                      (i) => i.groupLabel != null,
                    ))
                      _tag(context, item.childLabel),
                  ],
                ),
              ),
            Wrap(
              spacing: 6,
              children: [
                for (final spec in _draftSpecs)
                  InputChip(
                    label: Text(spec.name),
                    onDeleted: () => setState(() {
                      if (spec.name == _templateUnit) _templateUnit = null;
                      _newSpecs.remove(spec);
                    }),
                  ),
              ],
            ),
            OutlinedButton.icon(
              onPressed: _addSpec,
              icon: const Icon(Icons.add, size: 17),
              label: const Text('添加规格'),
            ),
            if (widget.items != null)
              _muted(context, '已有规格可回到列表展开后单独编辑。', size: 10),
            _divider(context),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                '支持有效期管理',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                '营养液、食品等按需开启；默认关闭',
                style: TextStyle(fontSize: 10),
              ),
              value: _expiry,
              onChanged: (value) => setState(() => _expiry = value),
            ),
            if (_expiry && _months != null)
              _muted(
                context,
                '默认保质期 $_months 个月；新增入手时预填到期日期，可修改或关闭。',
                size: 10,
              ),
            _muted(context, '每批入手均可不填写有效期。关闭此项不会清除历史记录的到期时间。', size: 10),
          ],
        ),
      ),
    ],
  );
}

class _IconPicker extends StatefulWidget {
  const _IconPicker({required this.selected});
  final String selected;
  @override
  State<_IconPicker> createState() => _IconPickerState();
}

class _IconPickerState extends State<_IconPicker> {
  late String _selected = widget.selected;
  @override
  Widget build(BuildContext context) => _SheetFrame(
    title: '选择物品图标',
    height: .65,
    saveLabel: '完成选择',
    onSave: () => Navigator.pop(context, _selected),
    children: [
      _muted(context, '没有实物照片时，可使用统一线性图标或通用占位图。', size: 11),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final entry in _icons.entries)
            SizedBox(
              width: 88,
              child: OutlinedButton(
                onPressed: () => setState(() => _selected = entry.key),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: _selected == entry.key
                        ? Theme.of(context).colorScheme.primary
                        : _palette(context).line,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Column(
                  children: [
                    Icon(entry.value.$2, size: 25),
                    const SizedBox(height: 8),
                    Text(entry.value.$1),
                  ],
                ),
              ),
            ),
        ],
      ),
    ],
  );
}

class _SpecEditor extends StatefulWidget {
  const _SpecEditor({this.group, this.spec, this.draftNames});
  final List<InventoryItem>? group;
  final InventoryItem? spec;
  final Set<String>? draftNames;
  @override
  State<_SpecEditor> createState() => _SpecEditorState();
}

class _SpecEditorState extends State<_SpecEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.spec?.childLabel);
  late final _note = TextEditingController(text: widget.spec?.specNote);
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final name = _name.text.trim();
    final note = _optional(_note.text);
    if (widget.draftNames != null) {
      Navigator.pop(context, (name: name, note: note));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final base = widget.group!.first;
      final spec =
          widget.spec ??
          InventoryItem(
            id: const Uuid().v4(),
            name: name,
            groupName: base.productName,
            purchased: false,
            createdAt: DateTime.now(),
            category: base.categoryLabel,
            purpose: base.purpose,
            iconKey: base.iconKey,
            supportsExpiry: base.allowsExpiry,
            shelfLifeMonths: base.shelfLifeMonths,
          );
      final updated = InventoryItem.fromMap({
        ...spec.toMap(),
        'name': name,
        'group_name': base.productName,
        'spec_note': note,
      });
      await AppDatabase.instance.saveInventoryCatalog([updated]);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = _saveError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (!await _confirmDelete(
          context,
          '删除「${widget.spec!.childLabel}」规格？已有入手记录的规格不能删除。',
        ) ||
        !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      // Retain a direct item if deleting the last spec of a legacy group.
      final group = widget.group!;
      if (group.length == 1 && group.single.records.isEmpty) {
        final item = group.single;
        await AppDatabase.instance.saveInventoryCatalog([
          InventoryItem.fromMap({
            ...item.toMap(),
            'name': item.productName,
            'group_name': null,
            'spec_note': null,
          }),
        ]);
      } else {
        await AppDatabase.instance.deleteInventorySpec(widget.spec!.id);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = _saveError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _SheetFrame(
    title: widget.spec == null ? '添加规格' : '编辑规格',
    height: .62,
    busy: _busy,
    error: _error,
    onSave: _save,
    onDelete: widget.spec == null ? null : _delete,
    saveLabel: widget.spec == null ? '保存规格' : '保存修改',
    children: [
      Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _muted(
              context,
              '${widget.group?.first.productName ?? '新物品'} / 尺寸、容量、材质都可以作为规格。',
              size: 11,
            ),
            _label('规格名称 *'),
            TextFormField(
              controller: _name,
              maxLength: 50,
              decoration: const InputDecoration(
                hintText: '例如：20cm、30cm、加厚型',
                counterText: '',
              ),
              validator: (value) {
                final name = value?.trim() ?? '';
                if (name.isEmpty) return '请填写规格名称';
                if ((widget.draftNames?.contains(name) ?? false) ||
                    (widget.group?.any(
                          (i) =>
                              i.groupLabel != null &&
                              i.id != widget.spec?.id &&
                              i.childLabel == name,
                        ) ??
                        false)) {
                  return '该规格已存在';
                }
                return null;
              },
            ),
            _label('快捷填写', hint: '点击选择'),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final name in ['20cm', '30cm', '50ml', '100ml', '加厚款'])
                  _choice(
                    context,
                    name,
                    false,
                    () => setState(() => _name.text = name),
                  ),
              ],
            ),
            _label('规格说明', hint: '选填'),
            TextFormField(
              controller: _note,
              maxLength: 200,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: '适合不同饲养场景',
                counterText: '',
              ),
            ),
            const SizedBox(height: 14),
            _info(context, '增加规格不代表已入手。已有入手记录的规格需要保留关联信息。'),
          ],
        ),
      ),
    ],
  );
}

class _RecordEditor extends StatefulWidget {
  const _RecordEditor({required this.item, this.record});
  final InventoryItem item;
  final InventoryBatch? record;
  @override
  State<_RecordEditor> createState() => _RecordEditorState();
}

class _RecordEditorState extends State<_RecordEditor> {
  final _form = GlobalKey<FormState>();
  late final _quantity = TextEditingController(
    text: widget.record == null
        ? '1'
        : widget.record!.quantity?.toString() ?? '',
  );
  late final _cost = TextEditingController(
    text: formatPurchasePrice(widget.record?.costCents) ?? '',
  );
  late final _note = TextEditingController(text: widget.record?.note);
  late DateTime? _acquired = widget.record == null
      ? DateTime.now()
      : widget.record!.acquiredAt;
  late DateTime? _expires = widget.record == null
      ? widget.item.suggestedExpiryDate(_acquired!)
      : widget.record!.expiresAt;
  late bool _defaultExpiry = widget.record == null && _expires != null;
  late bool _expiryEnabled = _expires != null;
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _quantity.dispose();
    _cost.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool expiry) async {
    final current = expiry ? _expires : _acquired;
    final chosen = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (chosen != null && mounted) {
      setState(() {
        if (expiry) {
          _expires = chosen;
          _defaultExpiry = false;
        } else {
          _acquired = chosen;
          if (_defaultExpiry) {
            _expires = widget.item.suggestedExpiryDate(chosen);
          }
        }
      });
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_expiryEnabled && _expires == null) {
      setState(() => _error = '请选择有效期截止日期');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final record = InventoryBatch(
        id: widget.record?.id ?? const Uuid().v4(),
        quantity: int.tryParse(_quantity.text.trim()),
        costCents: parsePurchasePrice(_cost.text),
        acquiredAt: _acquired,
        expiresAt: _expiryEnabled ? _expires : null,
        note: _optional(_note.text),
      );
      await AppDatabase.instance.saveInventoryBatch(
        widget.item.id,
        record,
        newItem: widget.item,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = _saveError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (!await _confirmDelete(context, '只删除这一次入手记录，物品资料和其他批次会保留。') ||
        !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await AppDatabase.instance.deleteInventoryBatch(
        widget.item.id,
        widget.record!.id,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = _saveError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _dateField(String title, DateTime? date, bool expiry) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _label(title),
      OutlinedButton.icon(
        onPressed: () => _pickDate(expiry),
        icon: const Icon(Icons.calendar_today_outlined, size: 17),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text(date == null ? '未填写 · 点击选择日期' : _date(date)),
        ),
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 45)),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final showExpiry =
        widget.item.allowsExpiry || widget.record?.expiresAt != null;
    return _SheetFrame(
      title: widget.record == null ? '记录入手' : '编辑入手记录',
      height: showExpiry ? .79 : .66,
      busy: _busy,
      error: _error,
      onSave: _save,
      onDelete: widget.record == null ? null : _delete,
      saveLabel: widget.record == null ? '保存记录' : '保存修改',
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _muted(
                context,
                '${widget.item.groupLabel == null ? '${widget.item.name} · 不区分规格' : widget.item.fullName}\n仅为个人养蚁物品记录，不涉及购买交易。',
                size: 11,
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        _label(widget.record == null ? '数量 *' : '剩余数量'),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 32,
                              height: 46,
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                tooltip: '减少数量',
                                onPressed: () => setState(() {
                                  final count =
                                      int.tryParse(_quantity.text) ?? 1;
                                  _quantity.text =
                                      '${(count - 1).clamp(widget.record == null ? 1 : 0, 1000000)}';
                                }),
                                icon: const Icon(Icons.remove, size: 17),
                              ),
                            ),
                            Expanded(
                              child: TextFormField(
                                controller: _quantity,
                                textAlign: TextAlign.center,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 3,
                                    vertical: 14,
                                  ),
                                ),
                                validator: (value) {
                                  final text = value?.trim() ?? '';
                                  final q = int.tryParse(text);
                                  if (text.isEmpty && widget.record != null) {
                                    return null;
                                  }
                                  return q == null ||
                                          q < (widget.record == null ? 1 : 0) ||
                                          q > 1000000
                                      ? '请输入有效数量'
                                      : null;
                                },
                              ),
                            ),
                            SizedBox(
                              width: 32,
                              height: 46,
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                tooltip: '增加数量',
                                onPressed: () => setState(
                                  () => _quantity.text =
                                      '${((int.tryParse(_quantity.text) ?? 0) + 1).clamp(1, 1000000)}',
                                ),
                                icon: const Icon(Icons.add, size: 17),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      children: [
                        _label('入手成本', hint: '选填'),
                        TextFormField(
                          controller: _cost,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(hintText: '¥ 0.00'),
                          validator: (value) =>
                              (value?.trim().isEmpty ?? true) ||
                                  parsePurchasePrice(value!) != null
                              ? null
                              : '金额最多两位小数',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (widget.record != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _muted(context, '填 0 表示已用完，记录与成本会保留。', size: 10),
                ),
              _dateField('入手日期', _acquired, false),
              if (showExpiry) ...[
                _divider(context),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    '设置有效期（可选）',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    '只影响当前这一次入手记录',
                    style: TextStyle(fontSize: 10),
                  ),
                  value: _expiryEnabled,
                  onChanged: (value) => setState(() => _expiryEnabled = value),
                ),
                if (_expiryEnabled) ...[
                  _dateField('有效期至 *', _expires, true),
                  const SizedBox(height: 6),
                  _muted(context, '保存后，只有这批物品会参与临期提醒。', size: 10),
                ],
              ],
              _label('用途或备注', hint: '选填'),
              TextFormField(
                controller: _note,
                maxLength: 200,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: '例如：备用、日常喂食、购买渠道',
                  counterText: '',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FilterEditor extends StatefulWidget {
  const _FilterEditor({required this.filter, required this.owned});
  final _InventoryFilter filter;
  final bool owned;
  @override
  State<_FilterEditor> createState() => _FilterEditorState();
}

class _FilterEditorState extends State<_FilterEditor> {
  late String _status = widget.filter.status;
  late String _expiry = widget.filter.expiry;
  late String _sort = widget.filter.sort;
  Widget _options(
    List<String> values,
    String selected,
    ValueChanged<String> change,
  ) => Wrap(
    spacing: 7,
    runSpacing: 7,
    children: [
      for (final value in values)
        _choice(
          context,
          value,
          selected == value,
          () => setState(() => change(value)),
        ),
    ],
  );
  @override
  Widget build(BuildContext context) => _SheetFrame(
    title: '筛选与排序',
    height: .66,
    cancelLabel: '重置',
    onCancel: () => setState(() {
      _status = '全部';
      _expiry = '全部';
      _sort = '未入手优先';
    }),
    saveLabel: '应用筛选',
    onSave: () => Navigator.pop(
      context,
      _InventoryFilter(status: _status, expiry: _expiry, sort: _sort),
    ),
    children: [
      _muted(context, '组合筛选条件，快速定位想找的物品；支持名称、用途和规格模糊匹配。', size: 11),
      _label('入手状态'),
      _options(['全部', '未入手', '已入手'], _status, (value) => _status = value),
      _label('有效期状态', hint: '仅已入手使用'),
      if (widget.owned)
        _options(
          ['全部', '即将到期', '已过期', '未设置有效期'],
          _expiry,
          (value) => _expiry = value,
        )
      else
        _muted(context, '切换到「已入手」后可按有效期筛选。', size: 11),
      _label('排序方式'),
      _options(['未入手优先', '名称 A-Z', '名称 Z-A'], _sort, (value) => _sort = value),
      const SizedBox(height: 16),
      _info(context, '未设置有效期的物品不会被误判为过期。'),
    ],
  );
}

String _saveError(Object error) =>
    error is StateError ? error.message : '保存失败，请检查名称是否重复后重试。';
