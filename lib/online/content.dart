import 'dart:convert';

import '../domain/beginner_care_notice.dart';

class ItemTemplate {
  const ItemTemplate({
    required this.id,
    required this.name,
    required this.category,
    required this.unit,
    required this.months,
    required this.enabled,
  });
  final String id, name, category, unit;
  final int? months;
  final bool enabled;
}

class HelpStep {
  const HelpStep(this.id, this.title, this.body);
  final String id, title, body;
}

class AppAnnouncement {
  const AppAnnouncement({
    required this.id,
    required this.title,
    required this.body,
  });
  final String id, title, body;
}

class PublicContent {
  const PublicContent({
    required this.version,
    required this.templates,
    required this.title,
    required this.summary,
    required this.steps,
    this.beginnerCareNotices = bundledBeginnerCareNotices,
    this.announcement,
  });
  final int version;
  final List<ItemTemplate> templates;
  final String title, summary;
  final List<HelpStep> steps;
  final List<BeginnerCareNotice> beginnerCareNotices;
  final AppAnnouncement? announcement;

  static const bundled = PublicContent(
    version: 0,
    templates: [
      ItemTemplate(
        id: 'nutrition-liquid',
        name: '营养液',
        category: '营养补充',
        unit: '瓶',
        months: 3,
        enabled: true,
      ),
    ],
    title: '欢迎使用蚁记',
    summary: '先建立蚁群档案，再记录日常变化；请定期导出备份。',
    steps: [
      HelpStep(
        'create-colony',
        '一窝蚁群，一份档案',
        '在「蚁群」中点击「新入手蚁群」，填写品种和入手日期；不清楚的数量可以留空。',
      ),
      HelpStep(
        'record-care',
        '从日常观察开始记录',
        '进入对应蚁群，记录投喂、补水、环境和数量变化，也可以添加照片或补记过去的事件。',
      ),
      HelpStep('backup-data', '定期备份，留住成长', '在「设置」中导出备份。记录仅存于本机，卸载或换机前请先备份。'),
    ],
  );

  factory PublicContent.decode(String source) {
    if (utf8.encode(source).length > 262144) {
      throw const FormatException('内容过大');
    }
    final data = jsonDecode(source) as Map<String, dynamic>;
    final version = data['version'];
    if (version is! int || version < 1) throw const FormatException('无效版本');
    _text(data['id'], 64);
    DateTime.parse(data['publishedAt'] as String);
    final rawItems = data['itemTemplates'] as List<dynamic>;
    if (rawItems.length > 1000) throw const FormatException('模板过多');
    final ids = <String>{};
    final templates = rawItems
        .map((raw) {
          final m = raw as Map<String, dynamic>;
          final id = _text(m['id'], 64);
          if (!RegExp(r'^[a-z0-9-]+$').hasMatch(id) || !ids.add(id)) {
            throw const FormatException('无效模板 ID');
          }
          final expiry = m['expiry'] as Map<String, dynamic>;
          int? months;
          if (expiry['type'] == 'shelfLife') {
            months = expiry['months'] as int;
            if (months < 1 || months > 120) {
              throw const FormatException('无效保质期');
            }
          } else if (expiry['type'] != 'none') {
            throw const FormatException('未知有效期类型');
          }
          return ItemTemplate(
            id: id,
            name: _text(m['name'], 200),
            category: _text(m['category'], 200),
            unit: _text(m['defaultUnit'], 50),
            months: months,
            enabled: m['enabled'] as bool,
          );
        })
        .toList(growable: false);
    final help = data['onboarding'] as Map<String, dynamic>;
    final rawSteps = help['steps'] as List<dynamic>;
    if (rawSteps.isEmpty || rawSteps.length > 8) {
      throw const FormatException('无效引导步骤');
    }
    final stepIds = <String>{};
    final steps = rawSteps
        .map((raw) {
          final m = raw as Map<String, dynamic>;
          final id = _text(m['id'], 64);
          if (!stepIds.add(id)) throw const FormatException('重复步骤');
          return HelpStep(id, _text(m['title'], 200), _text(m['body'], 4000));
        })
        .toList(growable: false);
    final notices = <BeginnerCareNotice>[];
    final texts = data['texts'];
    AppAnnouncement? announcement;
    if (texts != null) {
      if (texts is! Map<String, dynamic> || texts.length > 200) {
        throw const FormatException('无效公共文案');
      }
      for (final entry in texts.entries) {
        if (entry.key == 'app.announcement') {
          if (entry.value is! Map<String, dynamic>) {
            throw const FormatException('无效启动公告');
          }
          final value = entry.value as Map<String, dynamic>;
          announcement = AppAnnouncement(
            id: _text(value['updatedAt'], 64),
            title: _text(value['title'], 200),
            body: _text(value['body'], 4000),
          );
          continue;
        }
        if (!entry.key.startsWith('beginner-care.')) continue;
        if (!RegExp(r'^beginner-care\.[a-z0-9][a-z0-9._-]*$')
                .hasMatch(entry.key) ||
            entry.key.length > 128 ||
            entry.value is! Map<String, dynamic>) {
          throw const FormatException('无效新手注意事项');
        }
        final value = entry.value as Map<String, dynamic>;
        notices.add(
          BeginnerCareNotice(
            id: entry.key,
            title: _text(value['title'], 200),
            description: _text(value['body'], 4000),
          ),
        );
      }
    }
    return PublicContent(
      version: version,
      templates: templates,
      title: _text(help['title'], 200),
      summary: _text(help['summary'], 2000),
      steps: steps,
      beginnerCareNotices: notices.isEmpty
          ? bundledBeginnerCareNotices
          : List.unmodifiable(notices),
      announcement: announcement,
    );
  }

  static String _text(dynamic value, int max) {
    if (value is! String || value.trim().isEmpty || value.length > max) {
      throw const FormatException('无效内容字段');
    }
    return value;
  }
}
