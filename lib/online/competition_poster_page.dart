import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../data/share_image_export.dart';
import 'online_controller.dart';

/// Publicly shareable posters use only the anonymous leaderboard projection.
enum CompetitionPosterKind { promotion, leaderboard }

enum CompetitionPosterStyle {
  classic('自然经典'),
  challenge('竞技冲榜');

  const CompetitionPosterStyle(this.label);
  final String label;
}

enum CompetitionAntArt {
  none('不添加', null),
  ponerine('猛蚁', 'ponerine'),
  camponotus('弓背蚁', 'camponotus'),
  harvester('收获蚁', 'harvester'),
  messorBarbarus('原生收获蚁', 'messor-barbarus'),
  pogonomyrmexBarbatus('巴巴斯特', 'pogonomyrmex-barbatus'),
  leafcutter('切叶蚁', 'leafcutter');

  const CompetitionAntArt(this.label, this.assetName);
  final String label;
  final String? assetName;

  String? get assetPath =>
      assetName == null ? null : 'assets/competition/ants/$assetName.webp';
}

class _CompetitionTrackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gold = Paint()..color = const Color(0xffffc16b);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 5), gold);
    gold
      ..color = const Color(0x33ffc16b)
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.square;
    for (var index = 0; index < 4; index++) {
      final x = 245.0 + index * 29;
      canvas.drawLine(Offset(x, 0), Offset(x + 105, 105), gold);
    }
    gold.color = const Color(0xffffc16b);
    canvas.drawRect(Rect.fromLTWH(0, size.height - 4, size.width, 4), gold);
  }

  @override
  bool shouldRepaint(covariant _CompetitionTrackPainter oldDelegate) => false;
}

enum CompetitionPosterSize {
  square('1:1 方图', 360, 1080, 3),
  portrait('4:5 竖图', 450, 1350, 4),
  story('9:16 长图', 640, 1920, 5);

  const CompetitionPosterSize(
    this.label,
    this.logicalHeight,
    this.pixelHeight,
    this.topCount,
  );
  final String label;
  final double logicalHeight;
  final int pixelHeight;
  final int topCount;
}

class CompetitionPosterPage extends StatefulWidget {
  const CompetitionPosterPage({
    super.key,
    required this.controller,
    required this.competitionId,
    required this.kind,
  });

  final OnlineController controller;
  final String competitionId;
  final CompetitionPosterKind kind;

  @override
  State<CompetitionPosterPage> createState() => _CompetitionPosterPageState();
}

class _CompetitionPosterPageState extends State<CompetitionPosterPage> {
  final _posterKey = GlobalKey();
  Map<String, dynamic>? _detail;
  bool _loading = true, _saving = false;
  CompetitionPosterSize _size = CompetitionPosterSize.story;
  CompetitionPosterStyle _style = CompetitionPosterStyle.classic;
  CompetitionAntArt _antArt = CompetitionAntArt.none;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    if (!mounted || _saving) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.controller.competition(widget.competitionId);
      if (mounted) setState(() => _detail = detail);
    } catch (_) {
      if (mounted) setState(() => _error = '读取比赛数据失败，请检查网络后重试。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _notice(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _save({bool toFile = false}) async {
    if (_saving || _loading || _detail == null) return;
    setState(() => _saving = true);
    try {
      // Refresh before each export so dates, rank and participation count are current.
      final latest = await widget.controller.competition(widget.competitionId);
      if (!mounted) return;
      setState(() => _detail = latest);
      if (_antArt.assetPath case final artPath?) {
        await precacheImage(AssetImage(artPath), context);
      }
      await Scrollable.ensureVisible(
        _posterKey.currentContext!,
        duration: Duration.zero,
      );
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final boundary =
          _posterKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      Uint8List bytes;
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('PNG export failed');
        bytes = data.buffer.asUint8List();
      } finally {
        image.dispose();
      }
      final result = await ShareImageExport.save(bytes, toFile: toFile);
      if (mounted) _notice(result ?? '已取消保存');
    } on PlatformException catch (error) {
      if (mounted) {
        _notice(
          error.code == 'permission_denied'
              ? '未获得保存照片权限，可改用“另存为文件”。'
              : '海报保存失败，请重试。',
        );
      }
    } catch (_) {
      if (mounted) _notice('生成海报失败，请检查网络后重试。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.kind == CompetitionPosterKind.promotion ? '比赛宣传海报' : '榜单宣传海报',
      ),
      actions: [
        IconButton(
          tooltip: '刷新',
          onPressed: _loading || _saving ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _loading || _saving || _detail == null
                    ? null
                    : () => _save(),
                icon: const Icon(Icons.download_outlined),
                label: Text(_saving ? '正在生成…' : '保存图片'),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _loading || _saving || _detail == null
                  ? null
                  : () => _save(toFile: true),
              child: const Text('另存为文件'),
            ),
          ],
        ),
      ),
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) ...[
            Text(_error!),
            TextButton(onPressed: _refresh, child: const Text('重试')),
          ],
          if (_detail != null) ...[
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: CompetitionPosterStyle.values
                  .map(
                    (style) => ChoiceChip(
                      label: Text(style.label),
                      selected: _style == style,
                      onSelected: _saving
                          ? null
                          : (_) => setState(() => _style = style),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 4),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: CompetitionAntArt.values
                  .map(
                    (art) => ChoiceChip(
                      label: Text(art.label),
                      selected: _antArt == art,
                      onSelected: _saving
                          ? null
                          : (_) => setState(() => _antArt = art),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 4),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: CompetitionPosterSize.values
                  .map(
                    (size) => ChoiceChip(
                      label: Text(size.label),
                      selected: _size == size,
                      onSelected: _saving
                          ? null
                          : (_) => setState(() => _size = size),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            Text(
              '预览 · 导出 1080 × ${_size.pixelHeight} PNG',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: RepaintBoundary(
                  key: _posterKey,
                  child: MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.noScaling),
                    child: CompetitionPoster(
                      detail: _detail!,
                      kind: widget.kind,
                      size: _size,
                      style: _style,
                      antArt: _antArt,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (widget.kind == CompetitionPosterKind.leaderboard)
              const Text('榜单海报始终使用随机参赛 ID；完整榜单请在在线版查看。'),
          ],
        ],
      ),
    ),
  );
}

class CompetitionPoster extends StatelessWidget {
  const CompetitionPoster({
    super.key,
    required this.detail,
    required this.kind,
    this.size = CompetitionPosterSize.story,
    this.style = CompetitionPosterStyle.classic,
    this.antArt = CompetitionAntArt.none,
  });

  final Map<String, dynamic> detail;
  final CompetitionPosterKind kind;
  final CompetitionPosterSize size;
  final CompetitionPosterStyle style;
  final CompetitionAntArt antArt;

  static const _green = Color(0xff163d35);
  static const _mint = Color(0xffb8dfba);
  static const _cream = Color(0xfff5f1e4);
  static const _gold = Color(0xffffc16b);

  bool get _isChallenge => style == CompetitionPosterStyle.challenge;
  Color get _accent => _isChallenge ? _gold : _mint;

  String get _mode => switch (detail['scoreMode']) {
    'WORKER_GROWTH' => '工蚁净增长',
    'TOTAL_GROWTH' => '总虫口净增长',
    _ => '积分排名',
  };

  String get _rule => switch (detail['scoreMode']) {
    'WORKER_GROWTH' => '按报名后新增的工蚁数量排名',
    'TOTAL_GROWTH' => '按报名后工蚁与卵幼蛹的净增长排名',
    _ =>
      detail['broodPointsEnabled'] == true
          ? '纯新后起始 10 分 · 新增工蚁 +2 分 · 卵幼蛹 +1 分'
          : '纯新后起始 10 分 · 新增工蚁 +2 分',
  };

  String get _period =>
      '${detail['startDate']} — ${detail['endDate'] ?? '长期进行'}';

  String get _status => switch (detail['state']) {
    'UPCOMING' => '即将开始',
    'ENDED' => '比赛已结束',
    _ => '火热进行中',
  };

  @override
  Widget build(BuildContext context) {
    final entries = ((detail['entries'] as List<dynamic>?) ?? const [])
        .cast<Map<String, dynamic>>()
        .take(size.topCount)
        .toList();
    final title = detail['title'] as String? ?? '蚁友比赛';
    final count = detail['participantCount'] as int? ?? entries.length;
    return SizedBox(
      width: 360,
      height: size.logicalHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _isChallenge
                ? const [
                    Color(0xff26313d),
                    Color(0xff17232e),
                    Color(0xff0b1720),
                  ]
                : const [Color(0xff24574a), _green, Color(0xff0d2927)],
          ),
        ),
        child: Stack(
          children: [
            if (_isChallenge)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _CompetitionTrackPainter()),
                ),
              ),
            Positioned(
              top: -85,
              right: -70,
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _accent.withValues(alpha: _isChallenge ? .2 : .14),
                    width: 28,
                  ),
                ),
              ),
            ),
            if (antArt.assetPath case final artPath?)
              Positioned(
                top: size == CompetitionPosterSize.square ? 32 : 48,
                right: -22,
                width: 280,
                height: size == CompetitionPosterSize.square ? 126 : 156,
                child: Opacity(
                  opacity: _isChallenge ? .78 : .32,
                  child: Image.asset(artPath, fit: BoxFit.contain),
                ),
              ),
            if (antArt != CompetitionAntArt.none)
              Positioned(
                top: 40,
                left: 0,
                width: 280,
                height: 165,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _isChallenge
                          ? const [Color(0xff26313d), Color(0x0026313d)]
                          : const [Color(0xff24574a), Color(0x0024574a)],
                    ),
                  ),
                ),
              ),
            if (antArt != CompetitionAntArt.none && _isChallenge)
              Positioned(
                top: size == CompetitionPosterSize.square
                    ? 70
                    : size == CompetitionPosterSize.portrait
                    ? 82
                    : 106,
                left: 0,
                right: 0,
                height: 74,
                child: const ColoredBox(color: Color(0x6617232e)),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                size == CompetitionPosterSize.square ? 16 : 24,
                24,
                size == CompetitionPosterSize.square ? 14 : 22,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _isChallenge
                            ? Icons.emoji_events_outlined
                            : Icons.spa_outlined,
                        color: _accent,
                        size: 25,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '蚁记 ANTKEEP',
                        style: TextStyle(
                          color: _cream,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        kind == CompetitionPosterKind.promotion
                            ? _isChallenge
                                  ? '挑战报名'
                                  : '比赛招募'
                            : _isChallenge
                            ? '冠军榜单'
                            : '实时榜单',
                        style: TextStyle(color: _accent, fontSize: 12),
                      ),
                    ],
                  ),
                  SizedBox(
                    height: size == CompetitionPosterSize.square
                        ? 12
                        : size == CompetitionPosterSize.portrait
                        ? 12
                        : 34,
                  ),
                  Text(
                    _isChallenge
                        ? 'ANTKEEP CHALLENGE  /  新后发育赛'
                        : '蚁友比赛  /  新后发育赛',
                    style: TextStyle(
                      color: _accent,
                      fontSize: _isChallenge ? 11 : 13,
                      letterSpacing: _isChallenge ? .5 : 1.2,
                    ),
                  ),
                  SizedBox(
                    height: size == CompetitionPosterSize.square ? 5 : 10,
                  ),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _cream,
                      fontSize: size == CompetitionPosterSize.story ? 30 : 24,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (size != CompetitionPosterSize.square) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: .18),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$_status  ·  $_mode',
                        style: const TextStyle(color: _cream, fontSize: 12),
                      ),
                    ),
                  ],
                  SizedBox(
                    height: size == CompetitionPosterSize.square
                        ? 10
                        : size == CompetitionPosterSize.portrait
                        ? 15
                        : 22,
                  ),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(
                        size == CompetitionPosterSize.square
                            ? 12
                            : size == CompetitionPosterSize.portrait
                            ? 12
                            : 20,
                      ),
                      decoration: BoxDecoration(
                        color: _cream,
                        borderRadius: BorderRadius.circular(22),
                        border: _isChallenge
                            ? Border.all(color: _gold, width: 2)
                            : null,
                      ),
                      child: kind == CompetitionPosterKind.promotion
                          ? _promotionContent()
                          : _leaderboardContent(entries, count),
                    ),
                  ),
                  SizedBox(
                    height: size == CompetitionPosterSize.square ? 8 : 16,
                  ),
                  Text(
                    kind == CompetitionPosterKind.promotion
                        ? _isChallenge
                              ? '打开蚁记在线版 → 蚁友比赛 → 报名挑战'
                              : '打开蚁记在线版 → 蚁友比赛 → 选择比赛报名'
                        : '完整榜单请在蚁记在线版查看',
                    style: const TextStyle(
                      color: _cream,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (size != CompetitionPosterSize.square) ...[
                    const SizedBox(height: 5),
                    Text(
                      kind == CompetitionPosterKind.promotion
                          ? '报名需选择新后群并上传蚁群图片'
                          : '生成于 ${detail['today'] ?? ''}  ·  海报仅展示随机参赛 ID',
                      style: TextStyle(color: _accent, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _promotionContent() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (size == CompetitionPosterSize.story)
        Text(
          _isChallenge ? '冲击榜首，见证每一步' : '一起记录，从新后到繁盛',
          style: TextStyle(
            color: _green,
            fontSize: size == CompetitionPosterSize.portrait ? 17 : 21,
            fontWeight: FontWeight.w800,
          ),
        ),
      SizedBox(height: size == CompetitionPosterSize.story ? 22 : 0),
      _info('比赛时间', _period),
      SizedBox(
        height: size == CompetitionPosterSize.square
            ? 7
            : size == CompetitionPosterSize.portrait
            ? 10
            : 16,
      ),
      _info('排名方式', _mode),
      SizedBox(
        height: size == CompetitionPosterSize.square
            ? 7
            : size == CompetitionPosterSize.portrait
            ? 10
            : 16,
      ),
      _info('计分规则', _rule),
      if (size == CompetitionPosterSize.story) const Spacer(),
      if (size == CompetitionPosterSize.story)
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(
            size == CompetitionPosterSize.portrait ? 8 : 12,
          ),
          decoration: BoxDecoration(
            color: const Color(0xffe2ead8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            '比赛从报名数量起算 · 每日可更新一次',
            style: TextStyle(
              color: _green,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
    ],
  );

  Widget _info(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(color: Color(0xff6d8275), fontSize: 11),
      ),
      SizedBox(height: size == CompetitionPosterSize.story ? 4 : 1),
      Text(
        value,
        maxLines: size == CompetitionPosterSize.story
            ? 3
            : label == '计分规则'
            ? 2
            : 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: _green,
          fontSize: size == CompetitionPosterSize.story ? 15 : 12,
          height: 1.35,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );

  Widget _leaderboardContent(List<Map<String, dynamic>> entries, int count) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _isChallenge
                      ? 'TOP ${size.topCount} · 冲榜'
                      : 'TOP ${size.topCount}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _isChallenge ? const Color(0xff89520e) : _green,
                    fontSize: size == CompetitionPosterSize.square ? 18 : 23,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '$count 位参赛者',
                style: const TextStyle(color: _green, fontSize: 12),
              ),
            ],
          ),
          SizedBox(height: size == CompetitionPosterSize.square ? 6 : 14),
          if (entries.isEmpty)
            const Expanded(child: Center(child: Text('等待第一位蚁友报名')))
          else
            ...entries.map(_entryRow),
          const Spacer(),
          Text(
            '排名按报名基线计算 · $_mode',
            style: const TextStyle(color: Color(0xff6d8275), fontSize: 11),
          ),
        ],
      );

  Widget _entryRow(Map<String, dynamic> entry) {
    final id = entry['contestantId'] as String? ?? '';
    final shortId = id.length <= 8
        ? id.toUpperCase()
        : id.substring(0, 8).toUpperCase();
    final unit = detail['scoreMode'] == 'POINTS' ? '分' : '只';
    return Container(
      height: size == CompetitionPosterSize.square
          ? 39
          : size == CompetitionPosterSize.portrait
          ? 45
          : 51,
      margin: EdgeInsets.only(
        bottom: size == CompetitionPosterSize.square ? 3 : 6,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: _isChallenge && entry['rank'] == 1
            ? const Color(0xffffe4b5)
            : Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '${entry['rank']}',
              style: TextStyle(
                color: _isChallenge ? const Color(0xffa45b0a) : _green,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ID $shortId',
                  maxLines: 1,
                  style: const TextStyle(
                    color: _green,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '工 ${entry['workerCount']}  卵 ${entry['eggCount']}  '
                  '幼 ${entry['larvaCount']}  蛹 ${entry['cocoonCount']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff6d8275),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 5),
          Text(
            '${entry['score']} $unit',
            style: const TextStyle(
              color: _green,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
