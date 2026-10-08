import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'data/local_media_store.dart';
import 'data/share_image_export.dart';
import 'domain/models.dart';
import 'domain/share_card_data.dart';
import 'widgets/share_card_poster.dart';

class ShareCardsPage extends StatefulWidget {
  const ShareCardsPage({
    super.key,
    required this.colony,
    required this.records,
    this.initialRecord,
    this.initialKind,
    this.now,
  });
  final Colony colony;
  final List<CareRecord> records;
  final CareRecord? initialRecord;
  final ShareCardKind? initialKind;
  final DateTime? now;
  @override
  State<ShareCardsPage> createState() => _ShareCardsPageState();
}

class _ShareCardsPageState extends State<ShareCardsPage> {
  final _posterKey = GlobalKey();
  final _caption = TextEditingController();
  late final DateTime _now;
  late final List<CareRecord> _records;
  late ShareCardKind _kind;
  CareRecord? _diary;
  late DateTime _from, _to, _month;
  bool _dark = false, _counts = true, _dates = true, _duration = true;
  bool _environment = true, _note = true, _busy = false;
  bool _diaryExpanded = false;
  int _alignment = 0;
  List<String?> _photoPaths = [];
  List<Uint8List?> _photos = [];
  bool _loading = false, _missingPhoto = false;
  int _loadVersion = 0;

  @override
  void initState() {
    super.initState();
    _now = widget.now ?? DateTime.now();
    _records =
        widget.records.where((r) => r.colonyId == widget.colony.id).toList()
          ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    _diary = widget.initialRecord ?? _records.firstOrNull;
    _kind =
        widget.initialKind ??
        (widget.initialRecord == null
            ? ShareCardKind.colony
            : ShareCardKind.diary);
    _to = shareDay(_now);
    _from = _records.isEmpty
        ? shareDay(widget.colony.acquiredOn ?? widget.colony.createdAt)
        : shareDay(_records.last.occurredAt);
    if (_from.isAfter(_to)) _from = _to;
    _month = DateTime(_now.year, _now.month);
    _defaults();
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  List<String> _photosOn(DateTime date) => _records
      .where((r) => shareDay(r.occurredAt) == shareDay(date))
      .expand((r) => r.photos)
      .toSet()
      .toList();

  void _defaults({bool resetCaption = true}) {
    if (resetCaption) {
      _caption.text = _kind == ShareCardKind.diary
          ? (_diary?.note ?? '').characters.take(600).toString()
          : '';
    }
    switch (_kind) {
      case ShareCardKind.colony:
        _photoPaths = [
          if (widget.colony.coverPhotoPath != null)
            widget.colony.coverPhotoPath,
        ];
      case ShareCardKind.diary:
        _photoPaths = (_diary?.photos ?? []).take(1).toList();
      case ShareCardKind.comparison:
        _photoPaths = [
          _photosOn(_from).firstOrNull,
          _photosOn(_to).firstOrNull,
        ];
      case ShareCardKind.monthly:
        _photoPaths = ShareMonth(
          widget.colony,
          _records,
          _month,
          _now,
        ).photos.take(4).toList();
    }
    _loadPhotos();
  }

  Future<Uint8List> _preparePhoto(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 1200,
      allowUpscaling: false,
    );
    try {
      final frame = await codec.getNextFrame();
      try {
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (data == null) throw StateError('无法读取照片');
        final png = data.buffer.asUint8List();
        if (mounted) await precacheImage(MemoryImage(png), context);
        return png;
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  Future<void> _loadPhotos() async {
    final version = ++_loadVersion;
    _loading = true;
    _missingPhoto = false;
    final paths = List<String?>.of(_photoPaths);
    final result = <Uint8List?>[];
    var missing = false;
    for (final path in paths) {
      if (path == null) {
        result.add(null);
        continue;
      }
      try {
        result.add(
          await _preparePhoto(await LocalMediaStore.instance.readImage(path)),
        );
      } catch (_) {
        result.add(null);
        missing = true;
      }
    }
    if (!mounted || version != _loadVersion) return;
    setState(() {
      _photos = result;
      _loading = false;
      _missingPhoto = missing;
    });
  }

  Future<void> _changeDate({required bool first}) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: first ? _from : _to,
      firstDate: first ? DateTime(1900) : _from,
      lastDate: first ? _to : _now,
      helpText: first ? '选择对比开始日期' : '选择对比结束日期',
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (first) {
        _from = selected;
      } else {
        _to = selected;
      }
      _defaults(resetCaption: false);
    });
  }

  Future<void> _chooseMonth() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(1900),
      lastDate: _now,
      helpText: '选择月份（点选该月任意一天）',
    );
    if (selected != null && mounted) {
      setState(() {
        _month = DateTime(selected.year, selected.month);
        _defaults(resetCaption: false);
      });
    }
  }

  Future<void> _choosePhoto(int slot) async {
    final List<String> candidates;
    if (_kind == ShareCardKind.monthly) {
      candidates = ShareMonth(widget.colony, _records, _month, _now).photos;
    } else if (_kind == ShareCardKind.comparison) {
      candidates = _photosOn(slot == 0 ? _from : _to);
    } else if (_kind == ShareCardKind.diary) {
      candidates = _diary?.photos ?? [];
    } else {
      candidates = {
        if (widget.colony.coverPhotoPath != null) widget.colony.coverPhotoPath!,
        ..._records.expand((r) => r.photos),
      }.toList();
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: 420,
          child: Column(
            children: [
              const Padding(padding: EdgeInsets.all(16), child: Text('选择图片')),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: () => Navigator.pop(context, ':gallery'),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('从相册选择'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, ':none'),
                    child: const Text('不放照片'),
                  ),
                ],
              ),
              Expanded(
                child: candidates.isEmpty
                    ? const Center(child: Text('这里还没有记录照片，可从相册选择'))
                    : GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                            ),
                        itemCount: candidates.length,
                        itemBuilder: (context, index) => InkWell(
                          onTap: () =>
                              Navigator.pop(context, candidates[index]),
                          child: _PhotoThumbnail(path: candidates[index]),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    if (selected == ':gallery') {
      try {
        final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 1800,
          maxHeight: 1800,
        );
        if (picked == null || !mounted) return;
        setState(() => _loading = true);
        final bytes = await _preparePhoto(await picked.readAsBytes());
        if (!mounted) return;
        setState(() {
          while (_photos.length <= slot) {
            _photos.add(null);
          }
          _photos[slot] = bytes;
          _missingPhoto = false;
        });
      } catch (_) {
        if (mounted) _message('无法读取照片，请重新选择');
      } finally {
        if (mounted) setState(() => _loading = false);
      }
      return;
    }
    if (selected == ':none') {
      setState(() {
        if (slot < _photos.length) {
          if (_kind == ShareCardKind.comparison) {
            _photos[slot] = null;
          } else {
            _photos.removeAt(slot);
          }
        }
      });
    } else {
      setState(() => _loading = true);
      try {
        final bytes = await _preparePhoto(
          await LocalMediaStore.instance.readImage(selected),
        );
        if (mounted) {
          setState(() {
            while (_photos.length <= slot) {
              _photos.add(null);
            }
            _photos[slot] = bytes;
            _missingPhoto = false;
          });
        }
      } catch (_) {
        if (mounted) _message('照片已丢失或无法读取，请重新选择');
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  void _message(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _save({bool toFile = false}) async {
    if (_busy || _loading) return;
    setState(() => _busy = true);
    try {
      FocusScope.of(context).unfocus();
      final posterContext = _posterKey.currentContext!;
      await Scrollable.ensureVisible(posterContext, duration: Duration.zero);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final boundary =
          _posterKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(
        pixelRatio: 1080 / boundary.size.width,
      );
      Uint8List bytes;
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('图片生成失败');
        bytes = data.buffer.asUint8List();
      } finally {
        image.dispose();
      }
      final result = await ShareImageExport.save(bytes, toFile: toFile);
      if (mounted) _message(result ?? '已取消保存');
    } on PlatformException catch (error) {
      if (mounted) {
        _message(
          error.code == 'permission_denied'
              ? '未获得保存照片权限，可到系统设置开启，或选择“另存为文件”'
              : '保存失败，请重试或选择“另存为文件”',
        );
      }
    } catch (_) {
      if (mounted) _message('图片未保存成功，请重试或选择“另存为文件”');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final noDiary = _kind == ShareCardKind.diary && _diary == null;
    return Scaffold(
      appBar: AppBar(title: const Text('生成分享图')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy || _loading || noDiary
                      ? null
                      : () => _save(),
                  icon: const Icon(Icons.download_outlined),
                  label: Text(_busy ? '正在保存…' : '保存图片'),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _busy || _loading || noDiary
                    ? null
                    : () => _save(toFile: true),
                child: const Text('另存为文件'),
              ),
            ],
          ),
        ),
      ),
      body: AbsorbPointer(
        absorbing: _busy || _loading,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) {
                  final fade = (16 / bounds.width).clamp(0.0, 0.5);
                  return LinearGradient(
                    colors: const [
                      Colors.transparent,
                      Colors.white,
                      Colors.white,
                      Colors.transparent,
                    ],
                    stops: [0, fade, 1 - fade, 1],
                  ).createShader(bounds);
                },
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    spacing: 8,
                    children: ShareCardKind.values
                        .map(
                          (kind) => ChoiceChip(
                            label: Text(kind.label),
                            selected: _kind == kind,
                            onSelected: (_) => setState(() {
                              if (_kind == kind) return;
                              _kind = kind;
                              _defaults();
                            }),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_kind == ShareCardKind.diary && _records.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InkWell(
                      key: const ValueKey('diary-selector'),
                      borderRadius: BorderRadius.circular(4),
                      onTap: () =>
                          setState(() => _diaryExpanded = !_diaryExpanded),
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: '选择日记'),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${shareDate(_diary!.occurredAt)} · ${_diary!.type.label}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Icon(
                              _diaryExpanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_diaryExpanded) ...[
                      const SizedBox(height: 8),
                      Container(
                        key: const ValueKey('diary-options'),
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.sizeOf(context).height * 0.35,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ListView.builder(
                          primary: false,
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: _records.length,
                          itemBuilder: (context, index) {
                            final r = _records[index];
                            final selected = r.id == _diary?.id;
                            return ListTile(
                              selected: selected,
                              selectedTileColor: Theme.of(context)
                                  .colorScheme
                                  .secondaryContainer,
                              title: Text(
                                '${shareDate(r.occurredAt)} · ${r.type.label}',
                              ),
                              subtitle: Text(
                                r.note?.trim().isNotEmpty == true
                                    ? r.note!
                                    : '无备注',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: selected
                                  ? const Icon(Icons.check)
                                  : null,
                              onTap: () => setState(() {
                                _diary = r;
                                _diaryExpanded = false;
                                _defaults();
                              }),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              if (_kind == ShareCardKind.comparison)
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () => _changeDate(first: true),
                      child: Text('开始 ${shareDate(_from)}'),
                    ),
                    OutlinedButton(
                      onPressed: () => _changeDate(first: false),
                      child: Text('结束 ${shareDate(_to)}'),
                    ),
                  ],
                ),
              if (_kind == ShareCardKind.monthly)
                OutlinedButton.icon(
                  onPressed: _chooseMonth,
                  icon: const Icon(Icons.calendar_month),
                  label: Text('${_month.year} 年 ${_month.month} 月 · 更换月份'),
                ),
              if (_kind == ShareCardKind.comparison)
                const Text('默认使用对应日期的记录照片，也可自行选图。数量沿用截至当天的最近记录。'),
              if (noDiary)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('还没有日记，添加一条养护记录后即可生成日记卡片。'),
                )
              else ...[
                const SizedBox(height: 12),
                if (_loading) const LinearProgressIndicator(),
                if (_missingPhoto) const Text('部分照片无法读取，当前以占位图显示，可重新选择。'),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: RepaintBoundary(
                      key: _posterKey,
                      child: MediaQuery(
                        data: MediaQuery.of(context)
                            .copyWith(textScaler: TextScaler.noScaling),
                        child: ShareCardPoster(
                          colony: widget.colony,
                          records: _records,
                          kind: _kind,
                          now: _now,
                          from: _from,
                          to: _to,
                          month: _month,
                          diary: _diary,
                          photos: _kind == ShareCardKind.monthly
                              ? _photos.whereType<Uint8List>().toList()
                              : _photos,
                          caption: _caption.text,
                          dark: _dark,
                          showCounts: _counts,
                          showDates: _kind == ShareCardKind.monthly || _dates,
                          showDuration: _duration,
                          showEnvironment: _environment,
                          showNote: _note,
                          photoAlignment: [
                            Alignment.center,
                            Alignment.topCenter,
                            Alignment.bottomCenter,
                          ][_alignment],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  margin: EdgeInsets.zero,
                  elevation: 0,
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '分享设置',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('浅色手账'),
                              selected: !_dark,
                              onSelected: (_) => setState(() => _dark = false),
                            ),
                            ChoiceChip(
                              label: const Text('深色摄影'),
                              selected: _dark,
                              onSelected: (_) => setState(() => _dark = true),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final paired =
                                constraints.maxWidth >= 260 &&
                                MediaQuery.textScalerOf(context).scale(14) <=
                                    18;
                            final width = paired
                                ? (constraints.maxWidth - 8) / 2
                                : constraints.maxWidth;
                            return Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                for (
                                  var i = 0;
                                  i <
                                      (_kind == ShareCardKind.comparison
                                          ? 2
                                          : _kind == ShareCardKind.monthly
                                          ? 4
                                          : 1);
                                  i++
                                )
                                  SizedBox(
                                    width: width,
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: const Size(0, 48),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                      onPressed: () => _choosePhoto(i),
                                      icon: const Icon(
                                        Icons.photo_outlined,
                                        size: 20,
                                      ),
                                      label: Text(
                                        _kind == ShareCardKind.comparison
                                            ? (i == 0 ? '开始照片' : '结束照片')
                                            : '照片 ${i + 1}',
                                      ),
                                    ),
                                  ),
                                SizedBox(
                                  width: width,
                                  child: DropdownButtonFormField<int>(
                                    initialValue: _alignment,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      prefixText: '照片裁切  ',
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
                                      border: OutlineInputBorder(),
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 0,
                                        child: Text('居中'),
                                      ),
                                      DropdownMenuItem(
                                        value: 1,
                                        child: Text('靠上'),
                                      ),
                                      DropdownMenuItem(
                                        value: 2,
                                        child: Text('靠下'),
                                      ),
                                    ],
                                    onChanged: (value) =>
                                        setState(() => _alignment = value!),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        if (_kind == ShareCardKind.diary &&
                            (_diary?.note?.characters.length ?? 0) > 600)
                          const Text('原日记较长，分享文字默认取前 600 字，可在下方调整。'),
                        Stack(
                          children: [
                            TextField(
                              controller: _caption,
                              maxLength: 600,
                              buildCounter: (
                                _, {
                                required currentLength,
                                required isFocused,
                                required maxLength,
                              }) => null,
                              minLines: 2,
                              maxLines: 6,
                              decoration: InputDecoration(
                                labelText: _kind == ShareCardKind.diary
                                    ? '分享文字'
                                    : '写一句话（可选）',
                                alignLabelWithHint: true,
                                contentPadding: const EdgeInsets.fromLTRB(
                                  12,
                                  12,
                                  12,
                                  36,
                                ),
                                border: const OutlineInputBorder(),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            Positioned(
                              right: 12,
                              bottom: 10,
                              child: IgnorePointer(
                                child: Text(
                                  '${_caption.text.characters.length}/600',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_kind == ShareCardKind.diary)
                          Padding(
                            padding: const EdgeInsets.only(left: 12, top: 4),
                            child: Text(
                              '不修改原日记',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          '展示内容',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            FilterChip(
                              showCheckmark: false,
                              visualDensity: VisualDensity.compact,
                              labelPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              label: const Text('数量'),
                              selected: _counts,
                              onSelected: (v) => setState(() => _counts = v),
                            ),
                            if (_kind != ShareCardKind.monthly)
                              FilterChip(
                                showCheckmark: false,
                                visualDensity: VisualDensity.compact,
                                labelPadding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                label: const Text('日期'),
                                selected: _dates,
                                onSelected: (v) => setState(() => _dates = v),
                              ),
                            if (_kind == ShareCardKind.colony ||
                                _kind == ShareCardKind.comparison)
                              FilterChip(
                                showCheckmark: false,
                                visualDensity: VisualDensity.compact,
                                labelPadding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                label: const Text('天数'),
                                selected: _duration,
                                onSelected: (v) =>
                                    setState(() => _duration = v),
                              ),
                            if (_kind == ShareCardKind.diary)
                              FilterChip(
                                showCheckmark: false,
                                visualDensity: VisualDensity.compact,
                                labelPadding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                label: const Text('温湿度'),
                                selected: _environment,
                                onSelected: (v) =>
                                    setState(() => _environment = v),
                              ),
                            FilterChip(
                              showCheckmark: false,
                              visualDensity: VisualDensity.compact,
                              labelPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              label: const Text('文字'),
                              selected: _note,
                              onSelected: (v) => setState(() => _note = v),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('图片在本机生成，不上传数据。保存后可自行分享。'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoThumbnail extends StatefulWidget {
  const _PhotoThumbnail({required this.path});
  final String path;
  @override
  State<_PhotoThumbnail> createState() => _PhotoThumbnailState();
}

class _PhotoThumbnailState extends State<_PhotoThumbnail> {
  late final Future<Uint8List> _bytes = LocalMediaStore.instance.readImage(
    widget.path,
  );
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _bytes,
    builder: (context, snapshot) => snapshot.hasData
        ? Image.memory(
            snapshot.data!,
            cacheWidth: 240,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
          )
        : Icon(
            snapshot.hasError
                ? Icons.broken_image_outlined
                : Icons.photo_outlined,
          ),
  );
}
