import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import 'data/app_database.dart';
import 'data/local_media_store.dart';
import 'data/media_cleanup.dart';
import 'date_display.dart';
import 'domain/wild_catch_record.dart';
import 'live_wild_catch_page.dart';
import 'widgets/photo_source_picker.dart';
import 'widgets/photo_save_preview.dart';

class WildCatchPage extends StatefulWidget {
  const WildCatchPage({super.key});

  @override
  State<WildCatchPage> createState() => _WildCatchPageState();
}

class _WildCatchPageState extends State<WildCatchPage> {
  bool _startingLive = false;
  final Set<String> _expandedRecords = {};
  late Future<List<WildCatchRecord>> _records = AppDatabase.instance
      .listWildCatchRecords();

  void _refresh() => setState(() {
    _records = AppDatabase.instance.listWildCatchRecords();
  });

  Future<void> _edit([WildCatchRecord? record]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => _WildCatchForm(record: record)),
    );
    if (saved == true && mounted) _refresh();
  }

  Future<void> _openLive(WildCatchRecord record) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => record.isActive
            ? LiveWildCatchPage(initialRecord: record)
            : WildCatchDataPage(record: record),
      ),
    );
    if (mounted) _refresh();
  }

  Future<void> _startLive() async {
    if (_startingLive) return;
    _startingLive = true;
    try {
      final record = await Navigator.push<WildCatchRecord>(
        context,
        MaterialPageRoute(builder: (_) => const StartWildCatchPage()),
      );
      if (record != null && mounted) await _openLive(record);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('开始野采失败：$error')));
      }
    } finally {
      _startingLive = false;
    }
  }

  Future<void> _delete(WildCatchRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除野采记录？'),
        content: const Text('这条本地记录删除后无法恢复。'),
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
    if (confirmed != true) return;
    try {
      await AppDatabase.instance.deleteWildCatchRecord(record.id);
      await removeUnreferencedMedia(
        AppDatabase.instance,
        LocalMediaStore.instance,
        record.photos,
      );
      if (mounted) _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('野采数据'),
      actions: [
        TextButton(onPressed: () => _edit(), child: const Text('补记野采')),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _startLive,
      icon: const Icon(Icons.play_arrow),
      label: const Text('开始野采'),
    ),
    body: FutureBuilder<List<WildCatchRecord>>(
      future: _records,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('加载失败：${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return const Center(child: Text('还没有野采记录，记录第一次野采战果吧。'));
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          itemCount: snapshot.data!.length,
          itemBuilder: (context, index) {
            final record = snapshot.data![index];
            final expanded = _expandedRecords.contains(record.id);
            final colors = Theme.of(context).colorScheme;
            final textTheme = Theme.of(context).textTheme;
            final speciesCount = record.species
                .where((entry) => entry.name.isNotEmpty)
                .length;
            final colonyCount = record.species.fold<int>(
              0,
              (total, entry) => total + entry.colonies.length,
            );
            return Card(
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () =>
                          record.isLive ? _openLive(record) : _edit(record),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              record.place.isEmpty ? '进行中的野采' : record.place,
                              style: textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              [
                                chineseDate(record.caughtAt),
                                if (record.isActive) '进行中',
                                if (record.isLive && !record.isActive) '实时记录',
                                if (record.hasSpecificTime)
                                  TimeOfDay.fromDateTime(record.caughtAt)
                                      .format(context),
                              ].join(' · '),
                              style: textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text('$speciesCount 种 · $colonyCount 群'),
                            if (record.species.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              for (final entry in record.species)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    '${entry.displayName} · ${entry.colonies.length} 群',
                                  ),
                                ),
                            ],
                            if (record.note?.isNotEmpty == true &&
                                !expanded) ...[
                              const SizedBox(height: 8),
                              Text(
                                record.note!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (expanded) ...[
                      const Divider(height: 20),
                      for (final entry in record.species)
                        for (var i = 0; i < entry.colonies.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 8, bottom: 4),
                            child: Text(
                              '${entry.displayName} · 第 ${i + 1} 群：${_colonySummary(entry.colonies[i])}',
                            ),
                          ),
                      if (record.note?.isNotEmpty == true)
                        Padding(
                          padding: const EdgeInsets.only(right: 8, bottom: 4),
                          child: Text(record.note!),
                        ),
                      if (record.latitude != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            _coordinateLabel(
                              record.latitude!,
                              record.longitude!,
                            ),
                            style: textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                    if (record.photos.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text('${record.photos.length} 张野采照片'),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 72,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: record.photos.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (context, index) => _WildCatchImage(
                            key: ValueKey(record.photos[index]),
                            relativePath: record.photos[index],
                            size: 72,
                          ),
                        ),
                      ),
                    ],
                    const Divider(height: 20),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () => setState(() {
                            if (expanded) {
                              _expandedRecords.remove(record.id);
                            } else {
                              _expandedRecords.add(record.id);
                            }
                          }),
                          icon: Icon(
                            expanded ? Icons.expand_less : Icons.expand_more,
                          ),
                          label: Text(expanded ? '收起详情' : '查看详情'),
                        ),
                        const Spacer(),
                        if (record.species.isNotEmpty)
                          IconButton(
                            tooltip: '管理野采战果',
                            icon: const Icon(Icons.summarize_outlined),
                            onPressed: () async {
                              await Navigator.push<void>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      WildCatchResultsPage(record: record),
                                ),
                              );
                              if (mounted) _refresh();
                            },
                          ),
                        if (record.isLive && !record.isActive)
                          IconButton(
                            tooltip: '编辑野采记录',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _edit(record),
                          ),
                        IconButton(
                          tooltip: '删除野采记录',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(record),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ),
  );
}

String _colonySummary(WildCatchColony colony) {
  final parts = [
    if (colony.queenCount != null) '蚁后 ${colony.queenCount} 只',
    if (colony.workerCount != null) '工蚁 ${colony.workerCount} 只',
    if (colony.note?.isNotEmpty == true) colony.note!,
  ];
  return parts.isEmpty ? '未填写数量' : parts.join(' · ');
}

String _coordinateLabel(double latitude, double longitude) =>
    '纬度 ${latitude.toStringAsFixed(5)}，经度 ${longitude.toStringAsFixed(5)}';

class _WildCatchImage extends StatefulWidget {
  const _WildCatchImage({
    super.key,
    this.relativePath,
    this.image,
    required this.size,
  });

  final String? relativePath;
  final XFile? image;
  final double size;

  @override
  State<_WildCatchImage> createState() => _WildCatchImageState();
}

class _WildCatchImageState extends State<_WildCatchImage> {
  late final Future<Uint8List> _bytes =
      widget.image?.readAsBytes() ??
      LocalMediaStore.instance.readImage(widget.relativePath!);

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _bytes,
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Icon(
            snapshot.hasError
                ? Icons.broken_image_outlined
                : Icons.image_outlined,
          ),
        );
      }
      return InkWell(
        onTap: () =>
            showPhotoSavePreview(context, bytes: snapshot.data!, title: '野采照片'),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            snapshot.data!,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => SizedBox(
              width: widget.size,
              height: widget.size,
              child: const Icon(Icons.broken_image_outlined),
            ),
          ),
        ),
      );
    },
  );
}

class _ColonyDraft {
  _ColonyDraft([WildCatchColony? colony])
    : queens = TextEditingController(text: colony?.queenCount?.toString()),
      workers = TextEditingController(text: colony?.workerCount?.toString()),
      note = TextEditingController(text: colony?.note),
      colonyId = colony?.colonyId;

  final TextEditingController queens;
  final TextEditingController workers;
  final TextEditingController note;
  final String? colonyId;

  void dispose() {
    queens.dispose();
    workers.dispose();
    note.dispose();
  }

  WildCatchColony toModel() => WildCatchColony(
    colonyId: colonyId,
    queenCount: queens.text.trim().isEmpty
        ? null
        : int.parse(queens.text.trim()),
    workerCount: workers.text.trim().isEmpty
        ? null
        : int.parse(workers.text.trim()),
    note: note.text.trim().isEmpty ? null : note.text.trim(),
  );
}

class _SpeciesDraft {
  _SpeciesDraft([WildCatchSpecies? species])
    : name = TextEditingController(text: species?.name),
      colonies = species == null
          ? [_ColonyDraft()]
          : species.colonies.map(_ColonyDraft.new).toList();

  final TextEditingController name;
  final List<_ColonyDraft> colonies;

  void dispose() {
    name.dispose();
    for (final colony in colonies) {
      colony.dispose();
    }
  }

  WildCatchSpecies toModel() => WildCatchSpecies(
    name: name.text.trim(),
    colonies: colonies.map((colony) => colony.toModel()).toList(),
  );
}

class _WildCatchForm extends StatefulWidget {
  const _WildCatchForm({this.record});

  final WildCatchRecord? record;

  @override
  State<_WildCatchForm> createState() => _WildCatchFormState();
}

class _WildCatchFormState extends State<_WildCatchForm> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _caughtAt =
      widget.record?.caughtAt ?? DateUtils.dateOnly(DateTime.now());
  late bool _specificTime = widget.record?.hasSpecificTime ?? false;
  late final _place = TextEditingController(text: widget.record?.place);
  late final List<_SpeciesDraft> _species =
      widget.record?.species.map(_SpeciesDraft.new).toList() ?? [];
  final _retiredSpecies = <_SpeciesDraft>[];
  final _retiredColonies = <_ColonyDraft>[];
  late final _note = TextEditingController(text: widget.record?.note);
  late final _savedPhotos = <String>[...?widget.record?.photos];
  final _newPhotos = <XFile>[];
  bool _saving = false;
  bool _pickingPhoto = false;
  bool _locating = false;
  late double? _latitude = widget.record?.latitude;
  late double? _longitude = widget.record?.longitude;

  @override
  void dispose() {
    _place.dispose();
    for (final entry in _species) {
      entry.dispose();
    }
    for (final entry in _retiredSpecies) {
      entry.dispose();
    }
    for (final colony in _retiredColonies) {
      colony.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _caughtAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date != null && mounted) {
      setState(
        () => _caughtAt = DateTime(
          date.year,
          date.month,
          date.day,
          _specificTime ? _caughtAt.hour : 0,
          _specificTime ? _caughtAt.minute : 0,
        ),
      );
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_caughtAt),
    );
    if (time != null && mounted) {
      setState(
        () => _caughtAt = DateTime(
          _caughtAt.year,
          _caughtAt.month,
          _caughtAt.day,
          time.hour,
          time.minute,
        ),
      );
    }
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const _LocationMessage('手机定位服务未开启，请开启后重试，或手动填写地点。');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        throw const _LocationMessage('定位权限已被关闭，请在系统设置中开启，或手动填写地点。');
      }
      if (permission == LocationPermission.denied) {
        throw const _LocationMessage('未获得定位权限，仍可手动填写地点。');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认当前位置'),
          content: Text(
            '${_coordinateLabel(position.latitude, position.longitude)}\n'
            '定位精度约 ${position.accuracy.round()} 米。\n'
            '此坐标会随野采记录保存在本机；地点名称仍需自行填写。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('使用此定位'),
            ),
          ],
        ),
      );
      if (confirmed == true && mounted) {
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
        });
      }
    } on _LocationMessage catch (error) {
      _showLocationError(error.message);
    } on TimeoutException {
      _showLocationError('定位超时，请重试，或手动填写地点。');
    } catch (_) {
      _showLocationError('暂时无法获取定位，请重试，或手动填写地点。');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _showLocationError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _pickPhotos() async {
    setState(() => _pickingPhoto = true);
    try {
      final source = await choosePhotoSource(context);
      if (source == null || !mounted) return;
      final List<XFile> images;
      if (source == ImageSource.camera) {
        final image = await ImagePicker().pickImage(
          source: source,
          imageQuality: 86,
        );
        images = image == null ? [] : [image];
      } else {
        images = await ImagePicker().pickMultiImage(imageQuality: 86);
      }
      if (images.isNotEmpty && mounted) {
        setState(() => _newPhotos.addAll(images));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('选择照片失败，请重试。')));
      }
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  String? _countError(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final count = int.tryParse(value.trim());
    if (count == null || count < 0 || count > 1000000) {
      return '请输入 0～1000000 的整数';
    }
    return null;
  }

  void _removeSpecies(_SpeciesDraft draft) => setState(() {
    _species.remove(draft);
    _retiredSpecies.add(draft);
  });

  void _removeColony(_SpeciesDraft species, _ColonyDraft colony) =>
      setState(() {
        species.colonies.remove(colony);
        _retiredColonies.add(colony);
      });

  Widget _colonyEditor(_SpeciesDraft species, int index) {
    final colony = species.colonies[index];
    return Padding(
      key: ObjectKey(colony),
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text('第 ${index + 1} 群')),
              if (species.colonies.length > 1)
                IconButton(
                  tooltip: '删除第 ${index + 1} 群',
                  icon: const Icon(Icons.close),
                  onPressed: () => _removeColony(species, colony),
                ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: colony.queens,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '蚁后数量',
                    border: OutlineInputBorder(),
                  ),
                  validator: _countError,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: colony.workers,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '工蚁数量',
                    border: OutlineInputBorder(),
                  ),
                  validator: _countError,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: colony.note,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: '这群的备注（可选）',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _speciesEditor(int index) {
    final draft = _species[index];
    return Card(
      key: ObjectKey(draft),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '蚁种 ${index + 1}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: '删除蚁种 ${index + 1}',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _removeSpecies(draft),
                ),
              ],
            ),
            TextFormField(
              controller: draft.name,
              maxLength: 100,
              decoration: InputDecoration(
                labelText: widget.record?.isLive == true
                    ? '蚁种名称（可选）'
                    : '蚁种名称 *',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  widget.record?.isLive == true ||
                      (value != null && value.trim().isNotEmpty)
                  ? null
                  : '请填写蚁种名称',
            ),
            for (var i = 0; i < draft.colonies.length; i++)
              _colonyEditor(draft, i),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    setState(() => draft.colonies.add(_ColonyDraft())),
                icon: const Icon(Icons.add),
                label: const Text('添加蚁群'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final copied = <String>[];
    try {
      for (final photo in _newPhotos) {
        copied.add(await LocalMediaStore.instance.copyImage(photo));
      }
      await AppDatabase.instance.saveWildCatchRecord(
        WildCatchRecord(
          id: widget.record?.id ?? const Uuid().v4(),
          caughtAt: _caughtAt,
          hasSpecificTime: _specificTime,
          place: _place.text.trim(),
          latitude: _latitude,
          longitude: _longitude,
          photos: [..._savedPhotos, ...copied],
          species: _species.map((entry) => entry.toModel()).toList(),
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          startedAt: widget.record?.startedAt,
          endedAt: widget.record?.endedAt,
          events: [
            ...?widget.record?.events,
            if (widget.record?.isLive == true)
              WildCatchEvent(
                at: DateTime.now(),
                action: '修订',
                detail: '结束后修改野采记录',
              ),
          ],
          createdAt: widget.record?.createdAt ?? DateTime.now(),
        ),
      );
      await removeUnreferencedMedia(
        AppDatabase.instance,
        LocalMediaStore.instance,
        widget.record?.photos.where((photo) => !_savedPhotos.contains(photo)) ??
            const [],
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      await removeUnreferencedMedia(
        AppDatabase.instance,
        LocalMediaStore.instance,
        copied,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.record == null ? '记录野采战果' : '编辑野采记录')),
    bottomNavigationBar: SafeArea(
      minimum: const EdgeInsets.all(16),
      child: FilledButton.icon(
        onPressed: _saving ? null : _save,
        icon: const Icon(Icons.save_outlined),
        label: Text(_saving ? '保存中…' : '保存记录'),
      ),
    ),
    body: Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.record?.isLive != true)
              ListTile(
                title: const Text('野采日期'),
                subtitle: Text(chineseDate(_caughtAt)),
                onTap: _pickDate,
              ),
            if (widget.record?.isLive != true)
              SwitchListTile(
                title: const Text('记录具体时间'),
                value: _specificTime,
                onChanged: (value) => setState(() {
                  _specificTime = value;
                  if (!value) _caughtAt = DateUtils.dateOnly(_caughtAt);
                }),
              ),
            if (_specificTime && widget.record?.isLive != true)
              ListTile(
                title: const Text('时间'),
                subtitle: Text(
                  TimeOfDay.fromDateTime(_caughtAt).format(context),
                ),
                onTap: _pickTime,
              ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _place,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: '野采地点 *',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请填写野采地点' : null,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _locating ? null : _locate,
                icon: _locating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location),
                label: Text(_locating ? '定位中…' : '获取手机定位（可选）'),
              ),
            ),
            if (_latitude != null)
              Row(
                children: [
                  Expanded(
                    child: Text(_coordinateLabel(_latitude!, _longitude!)),
                  ),
                  IconButton(
                    tooltip: '移除定位',
                    onPressed: () => setState(() {
                      _latitude = null;
                      _longitude = null;
                    }),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            Text('野采战果', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_species.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('还没有添加蚁种；没有采到蚂蚁也可以保存本次野采。'),
              ),
            for (var index = 0; index < _species.length; index++)
              _speciesEditor(index),
            OutlinedButton.icon(
              onPressed: () => setState(() => _species.add(_SpeciesDraft())),
              icon: const Icon(Icons.add),
              label: const Text('添加蚁种'),
            ),
            const SizedBox(height: 16),
            Text('野采照片（可选）', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text('照片只关联本次野采，无需选择蚁种或蚁群。'),
            const SizedBox(height: 8),
            if (_savedPhotos.isNotEmpty || _newPhotos.isNotEmpty) ...[
              SizedBox(
                height: 88,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final photo in List<String>.of(_savedPhotos))
                      _photoItem(
                        key: ValueKey(photo),
                        relativePath: photo,
                        onRemove: () =>
                            setState(() => _savedPhotos.remove(photo)),
                      ),
                    for (final photo in List<XFile>.of(_newPhotos))
                      _photoItem(
                        key: ObjectKey(photo),
                        image: photo,
                        onRemove: () =>
                            setState(() => _newPhotos.remove(photo)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            OutlinedButton.icon(
              onPressed: _saving || _pickingPhoto ? null : _pickPhotos,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('添加野采照片'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _note,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '本次野采备注（可选）',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _photoItem({
    required Key key,
    String? relativePath,
    XFile? image,
    required VoidCallback onRemove,
  }) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: Stack(
      children: [
        _WildCatchImage(
          key: key,
          relativePath: relativePath,
          image: image,
          size: 80,
        ),
        Positioned(
          right: 0,
          top: 0,
          child: IconButton.filledTonal(
            tooltip: '移除野采照片',
            onPressed: _saving ? null : onRemove,
            icon: const Icon(Icons.close, size: 18),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    ),
  );
}

class _LocationMessage implements Exception {
  const _LocationMessage(this.message);

  final String message;
}
