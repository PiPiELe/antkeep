import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

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

class LiveWildCatchPage extends StatefulWidget {
  const LiveWildCatchPage({super.key, required this.initialRecord});

  final WildCatchRecord initialRecord;

  @override
  State<LiveWildCatchPage> createState() => _LiveWildCatchPageState();
}

class _LiveWildCatchPageState extends State<LiveWildCatchPage> {
  late WildCatchRecord _record = widget.initialRecord;
  late final TextEditingController _place = TextEditingController(
    text: _record.place,
  );
  late final TextEditingController _note = TextEditingController(
    text: _record.note,
  );
  Timer? _timer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (_record.isActive) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _place.dispose();
    _note.dispose();
    super.dispose();
  }

  void _error(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _commit(
    String action,
    String detail,
    WildCatchRecord Function(WildCatchEvent event) change,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final event = WildCatchEvent(
        at: DateTime.now(),
        action: action,
        detail: detail,
      );
      final updated = change(event);
      await AppDatabase.instance.saveWildCatchRecord(updated);
      if (mounted) setState(() => _record = updated);
    } catch (error) {
      _error('保存失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _savePlace() async {
    final value = _place.text.trim();
    if (value.isEmpty || value.length > 100) {
      _error('请填写不超过 100 字的野采地点。');
      return;
    }
    if (value == _record.place) return;
    await _commit(
      '地点',
      value,
      (event) => _record.withLiveChange(place: value, event: event),
    );
  }

  Future<void> _saveNote() async {
    final value = _note.text.trim();
    if (value.length > 500) {
      _error('备注最多 500 字。');
      return;
    }
    if (value == (_record.note ?? '')) return;
    await _commit(
      '备注',
      value.isEmpty ? '清空备注' : value,
      (event) => _record.withLiveChange(note: value, event: event),
    );
  }

  Future<void> _locate() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _error('手机定位服务未开启，可继续手动填写地点。');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _error('未获得定位权限，可继续手动填写地点。');
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
            '纬度 ${position.latitude.toStringAsFixed(5)}，经度 ${position.longitude.toStringAsFixed(5)}\n定位精度约 ${position.accuracy.round()} 米。',
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
      if (confirmed != true) return;
      setState(() => _busy = false);
      await _commit(
        '定位',
        '已确认当前位置',
        (event) => _record.withLiveChange(
          latitude: position.latitude,
          longitude: position.longitude,
          event: event,
        ),
      );
    } on TimeoutException {
      _error('定位超时，可重试或手动填写地点。');
    } catch (_) {
      _error('暂时无法获取定位，可重试或手动填写地点。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPhotos() async {
    if (_busy) return;
    final source = await choosePhotoSource(context);
    if (source == null || !mounted) return;
    setState(() => _busy = true);
    final copied = <String>[];
    try {
      final images = source == ImageSource.camera
          ? [
              if (await ImagePicker().pickImage(
                    source: source,
                    imageQuality: 86,
                  )
                  case final XFile photo)
                photo,
            ]
          : await ImagePicker().pickMultiImage(imageQuality: 86);
      final pickedAt = DateTime.now();
      for (final image in images) {
        copied.add(await LocalMediaStore.instance.copyImage(image));
      }
      if (copied.isEmpty) return;
      final updated = _record.withLiveChange(
        photos: [..._record.photos, ...copied],
        event: WildCatchEvent(
          at: pickedAt,
          action: '照片',
          detail: '添加 ${copied.length} 张野采照片',
          photoPaths: copied,
        ),
      );
      await AppDatabase.instance.saveWildCatchRecord(updated);
      if (mounted) setState(() => _record = updated);
    } catch (error) {
      await removeUnreferencedMedia(
        AppDatabase.instance,
        LocalMediaStore.instance,
        copied,
      );
      _error('添加照片失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removePhoto(String path) async {
    if (_busy) return;
    await _commit(
      '照片',
      '移除 1 张野采照片',
      (event) => _record.withLiveChange(
        photos: [..._record.photos]..remove(path),
        event: event,
      ),
    );
    if (!_record.photos.contains(path)) {
      await removeUnreferencedMedia(
        AppDatabase.instance,
        LocalMediaStore.instance,
        [path],
      );
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
              child: const Text('保存蚁群'),
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
        '战果',
        '采获 ${result.name} 1 群',
        (event) => _record.withLiveChange(species: next, event: event),
      );
    } finally {
      species.dispose();
      queens.dispose();
      workers.dispose();
      note.dispose();
    }
  }

  Future<void> _removeColony(int speciesIndex, int colonyIndex) async {
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
      '战果',
      '移除 ${selected.name} 第 ${colonyIndex + 1} 群',
      (event) => _record.withLiveChange(species: next, event: event),
    );
  }

  Future<void> _end() async {
    if (_place.text.trim().isEmpty ||
        _place.text.trim().length > 100 ||
        _note.text.trim().length > 500) {
      _error('结束前请检查地点和备注。');
      return;
    }
    if (_place.text.trim() != _record.place) await _savePlace();
    if (_note.text.trim() != (_record.note ?? '')) await _saveNote();
    if (_record.place != _place.text.trim() ||
        (_record.note ?? '') != _note.text.trim()) {
      _error('请先保存本次填写的信息。');
      return;
    }
    if (_busy) return;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('结束本次野采？'),
        content: const Text('结束时间会记入时间线。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续记录'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('结束野采'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _commit(
      '结束',
      '本次野采结束',
      (event) => _record.withLiveChange(endedAt: event.at, event: event),
    );
    if (!_record.isActive) _timer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final active = _record.isActive;
    final duration = (_record.endedAt ?? DateTime.now()).difference(
      _record.startedAt!,
    );
    String two(int value) => value.toString().padLeft(2, '0');
    final elapsed =
        '${duration.inHours}:${two(duration.inMinutes.remainder(60))}:${two(duration.inSeconds.remainder(60))}';
    return Scaffold(
      appBar: AppBar(title: Text(active ? '实时野采' : '野采时间线')),
      bottomNavigationBar: active
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: _busy ? null : _end,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('结束野采'),
                ),
              ),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    active ? '进行中 · 已用时 $elapsed' : '已结束 · 历时 $elapsed',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text('开始：${wildCatchExactTime(_record.startedAt!)}'),
                  if (_record.endedAt != null)
                    Text('结束：${wildCatchExactTime(_record.endedAt!)}'),
                  Text('记录创建：${wildCatchExactTime(_record.createdAt)}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (active) ...[
            TextField(
              controller: _place,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: '野采地点 *',
                border: OutlineInputBorder(),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _busy ? null : _savePlace,
                    child: const Text('保存地点'),
                  ),
                  TextButton.icon(
                    onPressed: _busy ? null : _locate,
                    icon: const Icon(Icons.my_location),
                    label: const Text('获取手机定位（可选）'),
                  ),
                ],
              ),
            ),
          ] else
            ListTile(title: const Text('野采地点'), subtitle: Text(_record.place)),
          if (_record.latitude != null)
            Text(
              '纬度 ${_record.latitude!.toStringAsFixed(5)}，经度 ${_record.longitude!.toStringAsFixed(5)}',
            ),
          const SizedBox(height: 16),
          Text('野采照片', style: Theme.of(context).textTheme.titleMedium),
          const Text('照片只关联本次野采，无需选择蚁种或蚁群。'),
          if (_record.photos.isNotEmpty)
            SizedBox(
              height: 96,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final path in _record.photos)
                    Padding(
                      padding: const EdgeInsets.only(right: 8, top: 8),
                      child: Stack(
                        children: [
                          _LivePhoto(key: ValueKey(path), path: path),
                          if (active)
                            Positioned(
                              right: 0,
                              top: 0,
                              child: IconButton.filledTonal(
                                tooltip: '移除野采照片',
                                onPressed: _busy
                                    ? null
                                    : () => _removePhoto(path),
                                icon: const Icon(Icons.close, size: 18),
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                                padding: EdgeInsets.zero,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          if (active)
            OutlinedButton.icon(
              onPressed: _busy ? null : _addPhotos,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('拍照或添加照片'),
            ),
          const SizedBox(height: 16),
          Text('野采战果', style: Theme.of(context).textTheme.titleMedium),
          for (
            var speciesIndex = 0;
            speciesIndex < _record.species.length;
            speciesIndex++
          )
            for (
              var colonyIndex = 0;
              colonyIndex < _record.species[speciesIndex].colonies.length;
              colonyIndex++
            )
              ListTile(
                title: Text(
                  '${_record.species[speciesIndex].name} · 第 ${colonyIndex + 1} 群',
                ),
                subtitle: Text(
                  [
                    if (_record
                            .species[speciesIndex]
                            .colonies[colonyIndex]
                            .queenCount !=
                        null)
                      '蚁后 ${_record.species[speciesIndex].colonies[colonyIndex].queenCount}',
                    if (_record
                            .species[speciesIndex]
                            .colonies[colonyIndex]
                            .workerCount !=
                        null)
                      '工蚁 ${_record.species[speciesIndex].colonies[colonyIndex].workerCount}',
                    if (_record
                            .species[speciesIndex]
                            .colonies[colonyIndex]
                            .note
                            ?.isNotEmpty ==
                        true)
                      _record.species[speciesIndex].colonies[colonyIndex].note!,
                  ].join(' · '),
                ),
                trailing: active
                    ? IconButton(
                        tooltip: '移除采获蚁群',
                        icon: const Icon(Icons.close),
                        onPressed: _busy
                            ? null
                            : () => _removeColony(speciesIndex, colonyIndex),
                      )
                    : null,
              ),
          if (active)
            OutlinedButton.icon(
              onPressed: _busy ? null : _addColony,
              icon: const Icon(Icons.add),
              label: const Text('记录采获蚁群'),
            ),
          const SizedBox(height: 16),
          if (active) ...[
            TextField(
              controller: _note,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '本次野采备注（可选）',
                border: OutlineInputBorder(),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: _busy ? null : _saveNote,
                child: const Text('保存备注'),
              ),
            ),
          ] else if (_record.note?.isNotEmpty == true)
            ListTile(title: const Text('备注'), subtitle: Text(_record.note!)),
          const SizedBox(height: 16),
          Text('时间线', style: Theme.of(context).textTheme.titleMedium),
          for (final event in _record.events)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  leading: const Icon(Icons.timeline),
                  title: Text(event.action),
                  subtitle: Text(
                    '${wildCatchExactTime(event.at)}${event.detail.isEmpty ? '' : '\n${event.detail}'}',
                  ),
                  isThreeLine: event.detail.isNotEmpty,
                ),
                if (event.photoPaths.any(_record.photos.contains))
                  SizedBox(
                    height: 96,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final path in event.photoPaths)
                          if (_record.photos.contains(path))
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 72,
                                right: 8,
                                top: 8,
                              ),
                              child: _LivePhoto(
                                key: ValueKey('event-$path'),
                                path: path,
                              ),
                            ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _LivePhoto extends StatefulWidget {
  const _LivePhoto({super.key, required this.path});
  final String path;
  @override
  State<_LivePhoto> createState() => _LivePhotoState();
}

class _LivePhotoState extends State<_LivePhoto> {
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
