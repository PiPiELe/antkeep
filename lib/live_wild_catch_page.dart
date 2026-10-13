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
import 'widgets/photo_source_picker.dart';

String wildCatchExactTime(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${chineseDate(time)} ${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}

String _elapsed(DateTime start, DateTime end) {
  final duration = end.difference(start);
  String two(int value) => value.toString().padLeft(2, '0');
  return '${duration.inHours}:${two(duration.inMinutes.remainder(60))}:${two(duration.inSeconds.remainder(60))}';
}

String _colonyLabel(WildCatchColony colony) => [
  if (colony.queenCount != null) '蚁后 ${colony.queenCount}',
  if (colony.workerCount != null) '工蚁 ${colony.workerCount}',
  if (colony.note?.isNotEmpty == true) colony.note!,
].join(' · ');

class StartWildCatchPage extends StatefulWidget {
  const StartWildCatchPage({super.key});

  @override
  State<StartWildCatchPage> createState() => _StartWildCatchPageState();
}

class _StartWildCatchPageState extends State<StartWildCatchPage> {
  final _place = TextEditingController();
  double? _latitude;
  double? _longitude;
  bool _busy = false;

  @override
  void dispose() {
    _place.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _locate() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _message('手机定位服务未开启，仍可手动填写地点。');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _message('未获得定位权限，仍可手动填写地点。');
        return;
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
            '纬度 ${position.latitude.toStringAsFixed(5)}，经度 ${position.longitude.toStringAsFixed(5)}\n'
            '定位精度约 ${position.accuracy.round()} 米。地点名称仍需填写。',
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
    } on TimeoutException {
      _message('定位超时，可重试或手动填写地点。');
    } catch (_) {
      _message('暂时无法获取定位，可重试或手动填写地点。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    final place = _place.text.trim();
    if (place.isEmpty || place.length > 100) {
      _message('请先填写不超过 100 字的野采地点。');
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final existing = (await AppDatabase.instance.listWildCatchRecords())
          .where((record) => record.isActive)
          .firstOrNull;
      if (existing != null) {
        if (mounted) Navigator.pop(context, existing);
        return;
      }
      final now = DateTime.now();
      final record = WildCatchRecord(
        id: const Uuid().v4(),
        caughtAt: now,
        hasSpecificTime: true,
        place: place,
        latitude: _latitude,
        longitude: _longitude,
        species: const [],
        startedAt: now,
        createdAt: now,
        events: [WildCatchEvent(at: now, action: '开始', detail: '地点：$place')],
      );
      await AppDatabase.instance.saveWildCatchRecord(record);
      if (mounted) Navigator.pop(context, record);
    } catch (error) {
      _message('开始野采失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('野采开始')),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed: _busy ? null : _start,
          icon: const Icon(Icons.play_arrow),
          label: const Text('确认地点并开始野采'),
        ),
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('先确认本次野采地点', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('点击开始后才会计时。手机定位可选，地点名称需要手动填写。'),
        const SizedBox(height: 24),
        TextField(
          controller: _place,
          maxLength: 100,
          autofocus: true,
          decoration: InputDecoration(
            labelText: '野采地点 *',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: '获取手机定位（可选）',
              icon: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
              onPressed: _busy ? null : _locate,
            ),
          ),
        ),
        if (_latitude != null)
          Text(
            '已确认位置：纬度 ${_latitude!.toStringAsFixed(5)}，经度 ${_longitude!.toStringAsFixed(5)}',
          ),
      ],
    ),
  );
}

class LiveWildCatchPage extends StatefulWidget {
  const LiveWildCatchPage({super.key, required this.initialRecord});
  final WildCatchRecord initialRecord;

  @override
  State<LiveWildCatchPage> createState() => _LiveWildCatchPageState();
}

class _LiveWildCatchPageState extends State<LiveWildCatchPage> {
  late WildCatchRecord _record = widget.initialRecord;
  final _timeline = ScrollController();
  Timer? _timer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timeline.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<bool> _commit(WildCatchRecord updated) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      await AppDatabase.instance.saveWildCatchRecord(updated);
      if (mounted) {
        setState(() => _record = updated);
        if (_timeline.hasClients) _timeline.jumpTo(0);
      }
      return true;
    } catch (error) {
      _message('保存失败：$error');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPhotos() async {
    if (_busy) return;
    final source = await choosePhotoSource(context);
    if (source == null || !mounted) return;
    final copied = <String>[];
    try {
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
      if (images.isEmpty || !mounted) return;
      setState(() => _busy = true);
      final at = DateTime.now();
      for (final image in images) {
        copied.add(await LocalMediaStore.instance.copyImage(image));
      }
      final updated = _record.withLiveChange(
        photos: [..._record.photos, ...copied],
        event: WildCatchEvent(
          at: at,
          action: '照片',
          detail: '添加 ${copied.length} 张野采照片',
          photoPaths: copied,
        ),
      );
      await AppDatabase.instance.saveWildCatchRecord(updated);
      if (mounted) {
        setState(() => _record = updated);
        if (_timeline.hasClients) _timeline.jumpTo(0);
      }
    } catch (error) {
      await removeUnreferencedMedia(
        AppDatabase.instance,
        LocalMediaStore.instance,
        copied,
      );
      _message('添加照片失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removePhoto(String path) async {
    final updated = _record.withLiveChange(
      photos: [..._record.photos]..remove(path),
      event: WildCatchEvent(
        at: DateTime.now(),
        action: '照片',
        detail: '移除 1 张野采照片',
      ),
    );
    if (await _commit(updated)) {
      await removeUnreferencedMedia(
        AppDatabase.instance,
        LocalMediaStore.instance,
        [path],
      );
    }
  }

  Future<void> _addNote() async {
    final controller = TextEditingController();
    try {
      final note = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('记录野采事件'),
          content: TextField(
            controller: controller,
            maxLength: 500,
            maxLines: 4,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '记录此刻发生的事',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isEmpty) return;
                Navigator.pop(context, value);
              },
              child: const Text('记录'),
            ),
          ],
        ),
      );
      if (note == null || !mounted) return;
      await _commit(
        _record.withLiveChange(
          note: note,
          event: WildCatchEvent(at: DateTime.now(), action: '备注', detail: note),
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _addColony() async {
    final species = TextEditingController();
    final queens = TextEditingController();
    final workers = TextEditingController();
    final note = TextEditingController();
    try {
      final result = await showDialog<WildCatchSpecies>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('记录采获蚁群'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: species,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: '蚁种名称 *'),
                ),
                TextField(
                  controller: queens,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: '蚁后数量（可选）'),
                ),
                TextField(
                  controller: workers,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: '工蚁数量（可选）'),
                ),
                TextField(
                  controller: note,
                  maxLength: 300,
                  decoration: const InputDecoration(labelText: '这群的备注（可选）'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final entry = WildCatchSpecies(
                  name: species.text.trim(),
                  colonies: [
                    WildCatchColony(
                      queenCount: int.tryParse(queens.text.trim()),
                      workerCount: int.tryParse(workers.text.trim()),
                      note: note.text.trim().isEmpty ? null : note.text.trim(),
                    ),
                  ],
                );
                try {
                  entry.validate();
                  Navigator.pop(context, entry);
                } on FormatException catch (error) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(error.message)));
                }
              },
              child: const Text('记录'),
            ),
          ],
        ),
      );
      if (result == null || !mounted) return;
      final next = [..._record.species];
      final index = next.indexWhere((entry) => entry.name == result.name);
      if (index == -1) {
        next.add(result);
      } else {
        next[index] = WildCatchSpecies(
          name: result.name,
          colonies: [...next[index].colonies, ...result.colonies],
        );
      }
      await _commit(
        _record.withLiveChange(
          species: next,
          event: WildCatchEvent(
            at: DateTime.now(),
            action: '战果',
            detail:
                '采获 ${result.name} 1 群 · ${_colonyLabel(result.colonies.single)}',
          ),
        ),
      );
    } finally {
      species.dispose();
      queens.dispose();
      workers.dispose();
      note.dispose();
    }
  }

  Future<WildCatchRecord> _removeColony(
    int speciesIndex,
    int colonyIndex,
  ) async {
    final next = [..._record.species];
    final selected = next[speciesIndex];
    final colonies = [...selected.colonies]..removeAt(colonyIndex);
    if (colonies.isEmpty) {
      next.removeAt(speciesIndex);
    } else {
      next[speciesIndex] = WildCatchSpecies(
        name: selected.name,
        colonies: colonies,
      );
    }
    await _commit(
      _record.withLiveChange(
        species: next,
        event: WildCatchEvent(
          at: DateTime.now(),
          action: '战果',
          detail: '移除 ${selected.name} 第 ${colonyIndex + 1} 群',
        ),
      ),
    );
    return _record;
  }

  Future<void> _end() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('结束本次野采？'),
        content: const Text('结束时间和期间的每条记录都会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续野采'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('结束野采'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final at = DateTime.now();
    final updated = _record.withLiveChange(
      endedAt: at,
      event: WildCatchEvent(at: at, action: '结束', detail: '本次野采结束'),
    );
    if (await _commit(updated) && mounted) {
      _timer?.cancel();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => WildCatchEndPage(record: updated)),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('野采进行中')),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed: _busy ? null : _end,
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('结束野采'),
        ),
      ),
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '已用时 ${_elapsed(_record.startedAt!, DateTime.now())}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text('地点：${_record.place}'),
              if (_record.latitude != null)
                Text(
                  '纬度 ${_record.latitude!.toStringAsFixed(5)}，经度 ${_record.longitude!.toStringAsFixed(5)}',
                ),
              Text('开始：${wildCatchExactTime(_record.startedAt!)}'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _addPhotos,
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text('拍照'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _addColony,
                    icon: const Icon(Icons.add),
                    label: const Text('记战果'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _addNote,
                    icon: const Icon(Icons.edit_note),
                    label: const Text('记事件'),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => WildCatchResultsPage(
                        record: _record,
                        onRemove: _removeColony,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.summarize_outlined),
                  label: const Text('查看当前战果汇总'),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _WildCatchTimeline(
            record: _record,
            controller: _timeline,
            onRemovePhoto: _busy ? null : _removePhoto,
          ),
        ),
      ],
    ),
  );
}

class WildCatchEndPage extends StatelessWidget {
  const WildCatchEndPage({super.key, required this.record});
  final WildCatchRecord record;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('野采结束')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Icon(Icons.check_circle_outline, size: 64),
        const SizedBox(height: 12),
        Center(
          child: Text('本次野采已结束', style: Theme.of(context).textTheme.titleLarge),
        ),
        const SizedBox(height: 24),
        _WildCatchSummary(record: record),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => WildCatchDataPage(record: record),
            ),
          ),
          child: const Text('查看本次野采数据'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('返回野采列表'),
        ),
      ],
    ),
  );
}

class WildCatchDataPage extends StatelessWidget {
  const WildCatchDataPage({super.key, required this.record});
  final WildCatchRecord record;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('野采数据')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _WildCatchSummary(record: record),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => WildCatchResultsPage(record: record),
            ),
          ),
          icon: const Icon(Icons.summarize_outlined),
          label: const Text('查看野采战果汇总'),
        ),
        const SizedBox(height: 16),
        Text('记录时间线', style: Theme.of(context).textTheme.titleMedium),
        _WildCatchTimeline(record: record, shrinkWrap: true),
      ],
    ),
  );
}

class _WildCatchSummary extends StatelessWidget {
  const _WildCatchSummary({required this.record});
  final WildCatchRecord record;

  @override
  Widget build(BuildContext context) {
    final colonyCount = record.species.fold<int>(
      0,
      (total, entry) => total + entry.colonies.length,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(record.place, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('开始：${wildCatchExactTime(record.startedAt!)}'),
            if (record.endedAt != null)
              Text('结束：${wildCatchExactTime(record.endedAt!)}'),
            Text('记录创建：${wildCatchExactTime(record.createdAt)}'),
            if (record.endedAt != null)
              Text('历时：${_elapsed(record.startedAt!, record.endedAt!)}'),
            const SizedBox(height: 8),
            Text(
              '${record.species.length} 种 · $colonyCount 群 · ${record.photos.length} 张照片 · ${record.events.length} 条事件',
            ),
          ],
        ),
      ),
    );
  }
}

class WildCatchResultsPage extends StatefulWidget {
  const WildCatchResultsPage({super.key, required this.record, this.onRemove});
  final WildCatchRecord record;
  final Future<WildCatchRecord> Function(int speciesIndex, int colonyIndex)?
  onRemove;

  @override
  State<WildCatchResultsPage> createState() => _WildCatchResultsPageState();
}

class _WildCatchResultsPageState extends State<WildCatchResultsPage> {
  late WildCatchRecord _record = widget.record;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('野采战果汇总')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_record.species.isEmpty) const Text('目前还没有采获蚁群。'),
        for (
          var speciesIndex = 0;
          speciesIndex < _record.species.length;
          speciesIndex++
        )
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_record.species[speciesIndex].name} · ${_record.species[speciesIndex].colonies.length} 群',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  for (
                    var colonyIndex = 0;
                    colonyIndex < _record.species[speciesIndex].colonies.length;
                    colonyIndex++
                  )
                    ListTile(
                      title: Text('第 ${colonyIndex + 1} 群'),
                      subtitle: Text(
                        _colonyLabel(
                          _record.species[speciesIndex].colonies[colonyIndex],
                        ),
                      ),
                      trailing: widget.onRemove == null
                          ? null
                          : IconButton(
                              tooltip: '移除采获蚁群',
                              icon: const Icon(Icons.close),
                              onPressed: () async {
                                final updated = await widget.onRemove!(
                                  speciesIndex,
                                  colonyIndex,
                                );
                                if (mounted) setState(() => _record = updated);
                              },
                            ),
                    ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

class _WildCatchTimeline extends StatelessWidget {
  const _WildCatchTimeline({
    required this.record,
    this.controller,
    this.shrinkWrap = false,
    this.onRemovePhoto,
  });
  final WildCatchRecord record;
  final ScrollController? controller;
  final bool shrinkWrap;
  final Future<void> Function(String path)? onRemovePhoto;

  Widget _photoThumbnail(String path) => Stack(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: _WildCatchPhoto(path: path),
      ),
      if (onRemovePhoto != null)
        Positioned(
          right: 0,
          top: 0,
          child: IconButton(
            tooltip: '移除野采照片',
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.cancel, size: 18),
            onPressed: () => onRemovePhoto!(path),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final events = record.events.reversed.toList();
    return ListView.builder(
      controller: controller,
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.fromLTRB(12, 12, 16, 20),
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        final visiblePhotos = event.photoPaths
            .where(record.photos.contains)
            .toList();
        final description = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(event.action, style: Theme.of(context).textTheme.titleMedium),
            Text(
              wildCatchExactTime(event.at),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (event.detail.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(event.detail),
              ),
          ],
        );
        return Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _TimelineRailPainter(
                    color: Theme.of(context).colorScheme.primary,
                    first: index == 0,
                    last: index == events.length - 1,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 44),
              child: Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (visiblePhotos.length == 1)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: description),
                            const SizedBox(width: 8),
                            _photoThumbnail(visiblePhotos.single),
                          ],
                        )
                      else
                        description,
                      if (visiblePhotos.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: SizedBox(
                            height: 88,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                for (final path in visiblePhotos)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: _photoThumbnail(path),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TimelineRailPainter extends CustomPainter {
  const _TimelineRailPainter({
    required this.color,
    required this.first,
    required this.last,
  });
  final Color color;
  final bool first;
  final bool last;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const y = 32.0;
    if (!first) {
      canvas.drawLine(const Offset(16, 0), const Offset(16, y), paint);
    }
    if (!last) {
      canvas.drawLine(const Offset(16, y), Offset(16, size.height), paint);
    }
    canvas.drawLine(const Offset(16, y), const Offset(43, y), paint);
    canvas.drawCircle(const Offset(16, y), 5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _TimelineRailPainter oldDelegate) =>
      color != oldDelegate.color ||
      first != oldDelegate.first ||
      last != oldDelegate.last;
}

class _WildCatchPhoto extends StatefulWidget {
  const _WildCatchPhoto({required this.path});
  final String path;
  @override
  State<_WildCatchPhoto> createState() => _WildCatchPhotoState();
}

class _WildCatchPhotoState extends State<_WildCatchPhoto> {
  late final Future<Uint8List> _bytes = LocalMediaStore.instance.readImage(
    widget.path,
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _bytes,
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const SizedBox(
          width: 88,
          height: 88,
          child: Icon(Icons.image_outlined),
        );
      }
      return InkWell(
        onTap: () => showDialog<void>(
          context: context,
          builder: (context) => Dialog(
            child: InteractiveViewer(child: Image.memory(snapshot.data!)),
          ),
        ),
        child: Image.memory(
          snapshot.data!,
          width: 88,
          height: 88,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox(
            width: 88,
            height: 88,
            child: Icon(Icons.broken_image_outlined),
          ),
        ),
      );
    },
  );
}
