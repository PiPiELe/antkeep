import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../data/app_database.dart';
import '../domain/models.dart';
import '../widgets/photo_source_picker.dart';
import '../widgets/photo_save_preview.dart';
import 'competition_poster_page.dart';
import 'online_api.dart';
import 'online_controller.dart';
import 'online_widgets.dart';

class CompetitionPage extends StatefulWidget {
  const CompetitionPage({super.key, required this.controller, this.initialId});
  final OnlineController controller;
  final String? initialId;

  @override
  State<CompetitionPage> createState() => _CompetitionPageState();
}

class _CompetitionPageState extends State<CompetitionPage> {
  List<Map<String, dynamic>> _competitions = [];
  List<Colony> _colonies = [];
  Map<String, dynamic>? _detail;
  String? _selectedColonyId, _message;
  Uint8List? _photo;
  String? _openingPhotoId;
  bool _photoPreviewOpen = false;
  bool _loading = false, _submitting = false;
  OnlineUser? _account;
  int _revision = 0, _photoTargetRevision = 0;

  @override
  void initState() {
    super.initState();
    _account = widget.controller.user;
    widget.controller.addListener(_onAccountChanged);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _reload(openId: widget.initialId),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onAccountChanged);
    super.dispose();
  }

  void _onAccountChanged() {
    final account = widget.controller.user;
    if (identical(account, _account) && widget.controller.enabled) return;
    _account = account;
    if (_photoPreviewOpen && mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      _photoPreviewOpen = false;
    }
    ++_revision;
    ++_photoTargetRevision;
    setState(() {
      _competitions = [];
      _colonies = [];
      _detail = null;
      _selectedColonyId = null;
      _photo = null;
      _message = null;
      _loading = false;
      _submitting = false;
    });
    if (account != null && widget.controller.enabled) {
      _reload(openId: widget.initialId);
    }
  }

  String _error(Object error) =>
      error is ApiFailure ? error.message : '读取比赛失败，请检查网络后重试。';

  Future<void> _reload({String? openId}) async {
    if (!mounted || widget.controller.user == null) return;
    final account = widget.controller.user;
    final revision = ++_revision;
    final selected = openId ?? _detail?['id'] as String?;
    final changingCompetition = openId != null && openId != _detail?['id'];
    if (changingCompetition) ++_photoTargetRevision;
    setState(() {
      _loading = true;
      _message = null;
      if (changingCompetition) {
        _detail = null;
        _photo = null;
        _submitting = false;
      }
    });
    bool current() =>
        mounted &&
        revision == _revision &&
        identical(account, widget.controller.user);
    var readingDetail = false;
    try {
      final contests = await widget.controller.competitions();
      if (!current()) return;
      final colonies = (await AppDatabase.instance.listColonies())
          .where((c) => !c.archived)
          .toList();
      if (!current()) return;
      setState(() {
        _competitions = contests;
        _colonies = colonies;
        if (!_colonies.any((c) => c.id == _selectedColonyId)) {
          final nextColonyId = _colonies.isEmpty ? null : _colonies.first.id;
          if (nextColonyId != _selectedColonyId) {
            _selectedColonyId = nextColonyId;
            _photo = null;
            ++_photoTargetRevision;
            _submitting = false;
          }
        }
      });
      readingDetail = selected != null;
      final detail = selected == null
          ? null
          : await widget.controller.competition(selected);
      if (!current()) return;
      setState(() {
        _detail = detail;
      });
    } catch (error) {
      if (current()) {
        setState(() {
          if (readingDetail) {
            _detail = null;
            _photo = null;
            ++_photoTargetRevision;
          }
          _message = _error(error);
        });
      }
    } finally {
      if (current()) setState(() => _loading = false);
    }
  }

  Future<void> _pickPhoto() async {
    final account = widget.controller.user;
    final targetRevision = _photoTargetRevision;
    try {
      final source = await choosePhotoSource(context);
      if (source == null || !mounted) return;
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 640,
        maxHeight: 640,
        imageQuality: 50,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final jpeg =
          bytes.length >= 3 &&
          bytes[0] == 0xff &&
          bytes[1] == 0xd8 &&
          bytes[2] == 0xff;
      final png =
          bytes.length >= 4 &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4e &&
          bytes[3] == 0x47;
      if ((!jpeg && !png) || bytes.length > 160 * 1024) {
        throw const ApiFailure('请选择 JPEG/PNG 图片，压缩后需小于 160 KiB。');
      }
      if (mounted &&
          identical(account, widget.controller.user) &&
          targetRevision == _photoTargetRevision) {
        setState(() {
          _photo = bytes;
          _message = null;
        });
      }
    } catch (error) {
      if (mounted &&
          identical(account, widget.controller.user) &&
          targetRevision == _photoTargetRevision) {
        setState(() => _message = _error(error));
      }
    }
  }

  Future<void> _openOwnPhoto(String id) async {
    final revision = _revision;
    final account = widget.controller.user;
    setState(() => _openingPhotoId = id);
    try {
      final bytes = await widget.controller.competitionPhoto(id);
      if (!mounted ||
          revision != _revision ||
          !identical(account, widget.controller.user)) {
        return;
      }
      setState(() => _openingPhotoId = null);
      _photoPreviewOpen = true;
      await showPhotoSavePreview(context, bytes: bytes, title: '比赛照片');
    } catch (error) {
      if (mounted &&
          revision == _revision &&
          identical(account, widget.controller.user)) {
        setState(() => _message = _error(error));
      }
    } finally {
      _photoPreviewOpen = false;
      if (mounted && _openingPhotoId == id) {
        setState(() => _openingPhotoId = null);
      }
    }
  }

  Future<Map<String, int>?> _markOriginCounts(int workers, int brood) async {
    final form = GlobalKey<FormState>();
    final fields = <String, TextEditingController>{
      'adoptedWorkerCount': TextEditingController(),
      'ownWorkerCount': TextEditingController(),
      'adoptedBroodCount': TextEditingController(),
      'ownBroodCount': TextEditingController(),
    };
    final route = DialogRoute<Map<String, int>>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('标注参赛数量来源'),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('当前工蚁 $workers 只，幼蛹茧 $brood 只。请分别填写合工与亲工数量；合工不参与比赛得分。'),
              const SizedBox(height: 12),
              for (final field in [
                ('adoptedWorkerCount', '合工工蚁（不计分）'),
                ('ownWorkerCount', '亲工工蚁（计分）'),
                ('adoptedBroodCount', '合工幼蛹茧（不计分）'),
                ('ownBroodCount', '亲工幼蛹茧（计分）'),
              ])
                TextFormField(
                  controller: fields[field.$1],
                  decoration: InputDecoration(labelText: field.$2),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (value) {
                    final count = int.tryParse(value ?? '');
                    return count == null || count > 1000000
                        ? '请填写 0～1000000 的整数'
                        : null;
                  },
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
              if (!form.currentState!.validate()) return;
              final counts = fields.map(
                (key, value) => MapEntry(key, int.parse(value.text)),
              );
              if (counts['adoptedWorkerCount']! + counts['ownWorkerCount']! !=
                      workers ||
                  counts['adoptedBroodCount']! + counts['ownBroodCount']! !=
                      brood) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('合工与亲工之和须分别等于当前工蚁、幼蛹茧总数。')),
                );
                return;
              }
              Navigator.pop(context, counts);
            },
            child: const Text('确认数量'),
          ),
        ],
      ),
    );
    final result = await Navigator.of(context, rootNavigator: true).push(route);
    await route.completed;
    for (final controller in fields.values) {
      controller.dispose();
    }
    return result;
  }

  Future<void> _submit() async {
    final detail = _detail;
    if (detail == null || _submitting) return;
    final account = widget.controller.user;
    final targetRevision = _photoTargetRevision;
    bool current() =>
        mounted &&
        identical(account, widget.controller.user) &&
        targetRevision == _photoTargetRevision;
    final mine = detail['myEntry'] as Map<String, dynamic>?;
    final registering = mine == null;
    final id = registering ? _selectedColonyId : mine['colonyId'] as String?;
    final colony = _colonies.where((c) => c.id == id).firstOrNull;
    if (colony == null) {
      setState(
        () => _message = registering ? '请先选择仍在饲养的蚁群。' : '报名的蚁群已不在本机，无法读取当前数量。',
      );
      return;
    }
    if (registering && _photo == null) {
      setState(() => _message = '报名时请上传一张蚁群图片。');
      return;
    }
    setState(() => _submitting = true);
    try {
      final records = await AppDatabase.instance.listRecords(colony.id);
      if (!current()) return;
      final counts = colony.currentPopulation(records);
      if (counts.workers == null ||
          counts.eggs == null ||
          counts.larvae == null ||
          counts.cocoons == null) {
        throw const ApiFailure('卵、幼虫、蛹或工蚁数量未知，请先在蚁群日记中补齐当前数量。');
      }
      final needsOrigin = counts.workers! > 0 || mine?['originTracked'] == true;
      final originCounts = needsOrigin
          ? await _markOriginCounts(
              counts.workers!,
              counts.larvae! + counts.cocoons!,
            )
          : null;
      if (!current() || (needsOrigin && originCounts == null)) return;
      if (!mounted) return;
      Map<String, dynamic>? disclaimer;
      bool? confirmed;
      if (registering) {
        disclaimer = await widget.controller.competitionDisclaimer();
        if (!mounted || !current()) return;
        var agreed = false;
        confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              scrollable: true,
              title: Text(
                '${disclaimer!['title']} · v${disclaimer['version']}',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(disclaimer['content'] as String),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('我已阅读并同意本版比赛声明'),
                    value: agreed,
                    onChanged: (value) =>
                        setDialogState(() => agreed = value == true),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: agreed ? () => Navigator.pop(context, true) : null,
                  child: const Text('同意并报名'),
                ),
              ],
            ),
          ),
        );
      } else {
        confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('确认更新比赛数据'),
            content: Text(
              '将上传「${colony.name}」当前的卵幼蛹工数量${_photo == null ? '' : '及所选图片'}。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认上传'),
              ),
            ],
          ),
        );
      }
      if (confirmed != true || !current()) return;
      final snapshot = <String, dynamic>{
        'queenCount': colony.currentQueenCount(records),
        'eggCount': counts.eggs,
        'larvaCount': counts.larvae,
        'cocoonCount': counts.cocoons,
        'workerCount': counts.workers,
        ...?originCounts,
        if (_photo != null) 'photoBase64': base64Encode(_photo!),
        if (registering) ...{
          'colonyId': colony.id,
          'colonyName': colony.name,
          'species': colony.species,
          'disclaimerPublicationId': disclaimer!['id'],
          'disclaimerAccepted': true,
        },
      };
      if (registering) {
        await widget.controller.enterCompetition(
          detail['id'] as String,
          snapshot,
        );
      } else {
        await widget.controller.updateCompetition(
          mine['id'] as String,
          snapshot,
        );
      }
      if (!current()) return;
      setState(() => _photo = null);
      await _reload(openId: detail['id'] as String);
      if (current()) {
        setState(() => _message = registering ? '报名成功，今日数据已上传。' : '今日比赛数据已上传。');
      }
    } catch (error) {
      if (!current()) return;
      // Read server state after an uncertain response; a timeout may follow a
      // successful write, and the unique daily key is authoritative.
      try {
        await _reload(openId: detail['id'] as String);
      } catch (_) {}
      if (current()) setState(() => _message = _error(error));
    } finally {
      if (current()) setState(() => _submitting = false);
    }
  }

  String _mode(String? mode) => switch (mode) {
    'WORKER_GROWTH' => '工蚁净增长',
    'TOTAL_GROWTH' => '虫口净增长',
    _ => '积分制',
  };
  String _state(String? state) => switch (state) {
    'UPCOMING' => '未开始',
    'ENDED' => '已结束',
    'DISABLED' => '已停用',
    'PENDING_REVIEW' => '名称待审核',
    'REJECTED' => '名称未通过审核',
    _ => '进行中',
  };

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final online = widget.controller.enabled;
      final signedIn = widget.controller.user != null;
      return Scaffold(
        appBar: AppBar(
          title: const Text('蚁友比赛'),
          actions: [
            IconButton(
              tooltip: '刷新比赛',
              onPressed: _loading || !signedIn ? null : _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: !online
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('请先在设置中切换到在线模式。'),
                ),
              )
            : !signedIn
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('登录后可报名蚁友比赛并查看榜单。'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                LoginPage(controller: widget.controller),
                          ),
                        );
                      },
                      child: const Text('登录 / 注册'),
                    ),
                  ],
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_loading) const LinearProgressIndicator(),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _message!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (_detail == null) ...[
                    Text('选择比赛', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _loading
                          ? null
                          : () async {
                              final created = await Navigator.of(context)
                                  .push<bool>(
                                    MaterialPageRoute<bool>(
                                      builder: (_) => CompetitionProposalPage(
                                        controller: widget.controller,
                                      ),
                                    ),
                                  );
                              if (created == true && mounted) await _reload();
                            },
                      icon: const Icon(Icons.add),
                      label: const Text('发起比赛'),
                    ),
                    const SizedBox(height: 8),
                    if (_competitions.isEmpty && !_loading)
                      const Text('暂无可参加的比赛。'),
                    for (final c in _competitions)
                      Card(
                        child: ListTile(
                          title: Text(c['title'] as String),
                          subtitle: Text(
                            '${_mode(c['scoreMode'] as String?)} · ${_state(c['state'] as String?)} · '
                            '${c['startDate']} 至 ${c['endDate'] ?? '长期'}'
                            '${c['myEntryId'] == null ? '' : ' · 已报名'}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _reload(openId: c['id'] as String),
                        ),
                      ),
                  ] else
                    ..._detailWidgets(context),
                ],
              ),
      );
    },
  );

  List<Widget> _detailWidgets(BuildContext context) {
    final d = _detail!;
    final mine = d['myEntry'] as Map<String, dynamic>?;
    final active = d['state'] == 'ACTIVE';
    final updatedToday = mine != null && mine['lastUpdateDate'] == d['today'];
    final entries = (d['entries'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    return [
      TextButton.icon(
        onPressed: () => setState(() {
          _detail = null;
          _photo = null;
          ++_photoTargetRevision;
          ++_revision;
          _loading = false;
          _submitting = false;
        }),
        icon: const Icon(Icons.arrow_back),
        label: const Text('全部比赛'),
      ),
      Text(
        d['title'] as String,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      Text(
        '${_mode(d['scoreMode'] as String?)} · ${_state(d['state'] as String?)} · ${d['startDate']} 至 ${d['endDate'] ?? '长期'}',
      ),
      const SizedBox(height: 8),
      Text(
        '排名以报名时的数量为基线。${d['scoreMode'] == 'POINTS' ? '纯新后且报名时无卵幼蛹，基础获得 ${d['queenBasePoints'] ?? 10} 分；已有工蚁或卵幼蛹从 0 分开始。亲工工蚁净增每只 ${d['workerGrowthPoints'] ?? 2} 分，卵及亲工幼蛹茧净增每只 ${d['broodGrowthPoints'] ?? (d['broodPointsEnabled'] == false ? 0 : 1)} 分。' : ''}'
        '已有工蚁的蚁群可报名，须标注合工与亲工数量；合工不计分。',
      ),
      if (d['reviewStatus'] == 'APPROVED' && d['enabled'] == true) ...[
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (d['state'] == 'UPCOMING' || d['state'] == 'ACTIVE')
              OutlinedButton.icon(
                onPressed: () =>
                    _openPoster(d, CompetitionPosterKind.promotion),
                icon: const Icon(Icons.image_outlined),
                label: const Text('比赛宣传海报'),
              ),
            if (d['state'] == 'ACTIVE' || d['state'] == 'ENDED')
              OutlinedButton.icon(
                onPressed: () =>
                    _openPoster(d, CompetitionPosterKind.leaderboard),
                icon: const Icon(Icons.leaderboard_outlined),
                label: const Text('榜单宣传海报'),
              ),
          ],
        ),
      ],
      const SizedBox(height: 16),
      if (mine == null && active) ...[
        DropdownButtonFormField<String>(
          key: ValueKey(_selectedColonyId),
          initialValue: _selectedColonyId,
          decoration: const InputDecoration(labelText: '选择参赛蚁群'),
          items: _colonies
              .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
              .toList(),
          onChanged: (value) => setState(() {
            if (value != _selectedColonyId) {
              _selectedColonyId = value;
              _photo = null;
              ++_photoTargetRevision;
              _submitting = false;
            }
          }),
        ),
        if (_colonies.isEmpty) const Text('本机暂无在养蚁群。'),
        if (_colonies.isNotEmpty)
          const Text('已有工蚁的蚁群也可报名，提交时需标注合工、亲工的工蚁及幼蛹茧数量。'),
      ],
      if (mine != null)
        Text(
          '我的名次：${mine['rank']} · ${mine['score']} ${d['scoreMode'] == 'POINTS' ? '分' : '只'} · '
          '${updatedToday ? '今日已更新' : '今日待更新'}',
        ),
      if (mine != null &&
          (mine['photos'] as List<dynamic>? ?? []).isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('我的比赛照片', style: Theme.of(context).textTheme.titleMedium),
        for (final item
            in (mine['photos'] as List<dynamic>).cast<Map<String, dynamic>>())
          ListTile(
            leading: const Icon(Icons.photo_outlined),
            title: Text(item['date'] as String),
            subtitle: const Text('查看并保存照片'),
            trailing: _openingPhotoId == item['id']
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(),
                  )
                : const Icon(Icons.chevron_right),
            onTap: _openingPhotoId == null
                ? () => _openOwnPhoto(item['id'] as String)
                : null,
          ),
      ],
      if (active && !updatedToday) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _submitting ? null : _pickPhoto,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text(
            _photo == null
                ? (mine == null ? '选择报名图片（必选）' : '选择今日图片（可选）')
                : '已选图片 · 重新选择',
          ),
        ),
        if (_photo != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Image.memory(_photo!, height: 120, fit: BoxFit.contain),
          ),
        FilledButton(
          onPressed: _submitting || _loading || _colonies.isEmpty
              ? null
              : _submit,
          child: Text(
            _submitting
                ? '上传中…'
                : mine == null
                ? '报名并上传'
                : '上传今日数据',
          ),
        ),
      ],
      const SizedBox(height: 20),
      Text(
        '比赛榜单 · ${entries.length} 个参赛 ID',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      for (final e in entries)
        Card(
          child: ListTile(
            leading: const Icon(Icons.emoji_events_outlined),
            title: Text(
              e['username'] == null
                  ? '${e['rank']}. ID ${(e['contestantId'] as String).substring(0, 8).toUpperCase()}'
                  : '${e['rank']}. ${e['username']} · ${e['colonyName']}',
            ),
            subtitle: Text(
              '工蚁 ${e['workerCount']} · 卵 ${e['eggCount'] ?? '未知'} · '
              '幼虫 ${e['larvaCount'] ?? '未知'} · 蛹 ${e['cocoonCount'] ?? '未知'}'
              '${e['adoptedWorkerCount'] == null ? '' : '\n合工工蚁 ${e['adoptedWorkerCount']} / 亲工工蚁 ${e['ownWorkerCount']} · 合工幼蛹茧 ${e['adoptedBroodCount']} / 亲工幼蛹茧 ${e['ownBroodCount']}'}',
            ),
            trailing: Text(
              '${e['score']}${d['scoreMode'] == 'POINTS' ? ' 分' : ' 只'}',
            ),
          ),
        ),
    ];
  }

  void _openPoster(Map<String, dynamic> detail, CompetitionPosterKind kind) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CompetitionPosterPage(
          controller: widget.controller,
          competitionId: detail['id'] as String,
          kind: kind,
        ),
      ),
    );
  }
}

class CompetitionProposalPage extends StatefulWidget {
  const CompetitionProposalPage({super.key, required this.controller});
  final OnlineController controller;
  @override
  State<CompetitionProposalPage> createState() =>
      _CompetitionProposalPageState();
}

class _CompetitionProposalPageState extends State<CompetitionProposalPage> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _queenPoints = TextEditingController(text: '10');
  final _workerPoints = TextEditingController(text: '2');
  final _broodPoints = TextEditingController(text: '1');
  String _mode = 'POINTS';
  bool _submitting = false;
  DateTime _start = DateTime.now();
  DateTime? _end;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _queenPoints.dispose();
    _workerPoints.dispose();
    _broodPoints.dispose();
    super.dispose();
  }

  String _date(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _chooseDate({required bool end}) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: end ? (_end ?? _start) : _start,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (selected != null && mounted) {
      setState(() {
        if (end) {
          _end = selected;
        } else {
          _start = selected;
        }
      });
    }
  }

  Future<void> _submit() async {
    if (_submitting || !_form.currentState!.validate()) return;
    if (_end != null && _end!.isBefore(_start)) {
      setState(() => _error = '结束日期不能早于开始日期。');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.controller.proposeCompetition({
        'title': _title.text.trim(),
        'type': 'NEW_QUEEN_GROWTH',
        'scoreMode': _mode,
        'queenBasePoints': _mode == 'POINTS'
            ? int.parse(_queenPoints.text)
            : 10,
        'workerGrowthPoints': _mode == 'POINTS'
            ? int.parse(_workerPoints.text)
            : 2,
        'broodGrowthPoints': _mode == 'POINTS'
            ? int.parse(_broodPoints.text)
            : 1,
        'startDate': _date(_start),
        'endDate': _end == null ? null : _date(_end!),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiFailure ? error.message : '提交失败，请稍后重试。',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('发起蚁友比赛')),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('比赛名称提交蚁记管理后台审核，通过后其他用户才能看到并报名。'),
          const SizedBox(height: 16),
          TextFormField(
            controller: _title,
            maxLength: 100,
            decoration: const InputDecoration(labelText: '比赛名称'),
            validator: (value) =>
                value == null || value.trim().isEmpty ? '请填写比赛名称' : null,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _mode,
            decoration: const InputDecoration(labelText: '排名方式'),
            items: const [
              DropdownMenuItem(value: 'POINTS', child: Text('积分制')),
              DropdownMenuItem(value: 'WORKER_GROWTH', child: Text('工蚁净增长')),
              DropdownMenuItem(value: 'TOTAL_GROWTH', child: Text('虫口净增长')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _mode = value);
            },
          ),
          if (_mode == 'POINTS') ...[
            const SizedBox(height: 12),
            Text('积分设置', style: Theme.of(context).textTheme.titleMedium),
            const Text('填 0 表示该项不计分；增长按报名后的净增加量计算。'),
            _pointField('新后基础获得积分', _queenPoints),
            _pointField('每增工蚁获得积分', _workerPoints),
            _pointField('每增卵幼蛹获得积分', _broodPoints),
          ],
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => _chooseDate(end: false),
            child: Text('开始日期：${_date(_start)}'),
          ),
          OutlinedButton(
            onPressed: () => _chooseDate(end: true),
            child: Text(_end == null ? '结束日期：长期比赛' : '结束日期：${_date(_end!)}'),
          ),
          if (_end != null)
            TextButton(
              onPressed: () => setState(() => _end = null),
              child: const Text('改为长期比赛'),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: Text(_submitting ? '提交中…' : '提交审核'),
          ),
        ],
      ),
    ),
  );

  Widget _pointField(String label, TextEditingController controller) =>
      TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
        validator: (value) {
          if (_mode != 'POINTS') return null;
          final points = int.tryParse(value ?? '');
          return points == null || points < 0 || points > 100
              ? '请输入 0 到 100 的整数'
              : null;
        },
      );
}
