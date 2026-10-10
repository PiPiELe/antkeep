import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/app_database.dart';
import '../domain/models.dart';
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
  bool _loading = false, _submitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _reload(openId: widget.initialId),
    );
  }

  String _error(Object error) =>
      error is ApiFailure ? error.message : '读取比赛失败，请检查网络后重试。';

  Future<void> _reload({String? openId}) async {
    if (_loading || !mounted || widget.controller.user == null) return;
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final contests = await widget.controller.competitions();
      final colonies = (await AppDatabase.instance.listColonies())
          .where((c) => c.isNewQueenColony)
          .toList();
      final selected = openId ?? _detail?['id'] as String?;
      final detail = selected == null
          ? null
          : await widget.controller.competition(selected);
      if (!mounted) return;
      setState(() {
        _competitions = contests;
        _colonies = colonies;
        _detail = detail;
        if (!_colonies.any((c) => c.id == _selectedColonyId)) {
          _selectedColonyId = _colonies.isEmpty ? null : _colonies.first.id;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _message = _error(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
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
      if (mounted) {
        setState(() {
          _photo = bytes;
          _message = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _message = _error(error));
    }
  }

  Future<void> _submit() async {
    final detail = _detail;
    if (detail == null || _submitting) return;
    final mine = detail['myEntry'] as Map<String, dynamic>?;
    final registering = mine == null;
    final id = registering ? _selectedColonyId : mine['colonyId'] as String?;
    final colony = _colonies.where((c) => c.id == id).firstOrNull;
    if (colony == null) {
      setState(
        () => _message = registering ? '请先选择仍在饲养的新后群。' : '报名的蚁群已不在本机，无法读取当前数量。',
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
      final counts = colony.currentPopulation(records);
      if (counts.workers == null ||
          counts.eggs == null ||
          counts.larvae == null ||
          counts.cocoons == null) {
        throw const ApiFailure('卵、幼虫、蛹或工蚁数量未知，请先在蚁群日记中补齐当前数量。');
      }
      if (!mounted) return;
      Map<String, dynamic>? disclaimer;
      bool? confirmed;
      if (registering) {
        disclaimer = await widget.controller.competitionDisclaimer();
        if (!mounted) return;
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
      if (confirmed != true || !mounted) return;
      final snapshot = <String, dynamic>{
        'queenCount': colony.queenCount,
        'eggCount': counts.eggs,
        'larvaCount': counts.larvae,
        'cocoonCount': counts.cocoons,
        'workerCount': counts.workers,
        if (_photo != null) 'photoBase64': base64Encode(_photo!),
        if (registering) ...{
          'colonyId': colony.id,
          'colonyName': colony.name,
          'species': colony.species,
          'initialWorkerCount': colony.initialWorkerCount,
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
      if (!mounted) return;
      setState(() => _photo = null);
      await _reload(openId: detail['id'] as String);
      if (mounted) {
        setState(() => _message = registering ? '报名成功，今日数据已上传。' : '今日比赛数据已上传。');
      }
    } catch (error) {
      // Read server state after an uncertain response; a timeout may follow a
      // successful write, and the unique daily key is authoritative.
      try {
        await _reload(openId: detail['id'] as String);
      } catch (_) {}
      if (mounted) setState(() => _message = _error(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _mode(String? mode) => switch (mode) {
    'WORKER_GROWTH' => '工蚁净增长',
    'TOTAL_GROWTH' => '总虫口净增长',
    _ => '积分',
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
                        if (mounted) await _reload(openId: widget.initialId);
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
        onPressed: () => setState(() => _detail = null),
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
        '排名以报名时的数量为基线。积分赛中，报名时无工蚁和卵幼蛹的纯新后从 10 分开始；已有工蚁或卵幼蛹从 0 分开始。'
        '工蚁净增加每只 2 分${d['broodPointsEnabled'] == true ? '，卵幼蛹净增加每只 1 分' : '；本场不计卵幼蛹分'}。',
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
          decoration: const InputDecoration(labelText: '选择新后群'),
          items: _colonies
              .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
              .toList(),
          onChanged: (value) => setState(() => _selectedColonyId = value),
        ),
        if (_colonies.isEmpty) const Text('本机暂无初始工蚁数为 0 的在养新后群。'),
      ],
      if (mine != null)
        Text(
          '我的名次：${mine['rank']} · ${mine['score']} ${d['scoreMode'] == 'POINTS' ? '分' : '只'} · '
          '${updatedToday ? '今日已更新' : '今日待更新'}',
        ),
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
              '幼虫 ${e['larvaCount'] ?? '未知'} · 蛹 ${e['cocoonCount'] ?? '未知'}',
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
  String _mode = 'POINTS';
  bool _broodPoints = true, _submitting = false;
  DateTime _start = DateTime.now();
  DateTime? _end;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
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
        'broodPointsEnabled': _broodPoints,
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
          const Text('比赛名称提交内容管理后台审核，通过后其他用户才能看到并报名。'),
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
              DropdownMenuItem(value: 'POINTS', child: Text('积分赛')),
              DropdownMenuItem(value: 'WORKER_GROWTH', child: Text('工蚁净增长')),
              DropdownMenuItem(value: 'TOTAL_GROWTH', child: Text('总虫口净增长')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _mode = value);
            },
          ),
          if (_mode == 'POINTS')
            SwitchListTile(
              title: const Text('卵幼蛹计分'),
              subtitle: const Text('开启后，报名后净增加每只计 1 分'),
              value: _broodPoints,
              onChanged: (value) => setState(() => _broodPoints = value),
            ),
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
}
