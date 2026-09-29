import 'dart:math';

class BeginnerCareNotice {
  const BeginnerCareNotice({
    required this.id,
    required this.title,
    required this.description,
  });

  final String id;
  final String title;
  final String description;
}

const bundledBeginnerCareNotices = [
  BeginnerCareNotice(
    id: 'beginner-care.quiet',
    title: '尽量减少打扰',
    description: '新入手、繁殖期或状态不稳定的蚁群尤其需要安静环境；除必要的投喂、补水和观察外，尽量少开巢、少搬动。',
  ),
  BeginnerCareNotice(
    id: 'beginner-care.temperature',
    title: '注意饲养温度',
    description: '先了解所养品种适宜的温度范围，避免暴晒、骤冷骤热和长时间贴近热源；温度异常时优先让环境恢复稳定。',
  ),
  BeginnerCareNotice(
    id: 'beginner-care.water',
    title: '定期检查供水',
    description: '观察水源余量和巢内干湿变化，按品种与巢体需要补水；避免积水，也不要只凭巢壁是否起雾判断湿度。',
  ),
  BeginnerCareNotice(
    id: 'beginner-care.feeding',
    title: '投喂先少量，再观察',
    description: '根据品种、群落规模和实际取食情况调整食物种类与分量；不要把其他品种的食谱直接照搬给自己的蚁群。',
  ),
  BeginnerCareNotice(
    id: 'beginner-care.clean',
    title: '及时清理食物残渣',
    description: '定期检查活动区，及时移走变质食物与可取出的残渣；清理时尽量减少对巢内蚁群的干扰。',
  ),
  BeginnerCareNotice(
    id: 'beginner-care.escape',
    title: '开盖前先检查防逃',
    description: '投喂和清理前检查盖子、连接管与防逃设施；操作结束后确认接口与盖子已关好。',
  ),
  BeginnerCareNotice(
    id: 'beginner-care.species',
    title: '先了解品种，再调整环境',
    description: '不同品种的温湿度、食性和季节节律可能不同；调整饲养方式前先确认品种与可靠的饲养资料。',
  ),
  BeginnerCareNotice(
    id: 'beginner-care.records',
    title: '记录变化，不必反复开巢',
    description: '结合必要的养护记录投喂、补水和观察结果；数量不确定时可以留空或标为估计，不必为精确计数反复打扰蚁群。',
  ),
];

BeginnerCareNotice randomBeginnerCareNotice({
  List<BeginnerCareNotice> notices = bundledBeginnerCareNotices,
  BeginnerCareNotice? previous,
  Random? random,
}) {
  final available = notices.isEmpty ? bundledBeginnerCareNotices : notices;
  final alternatives = available
      .where((notice) => notice.id != previous?.id)
      .toList();
  final candidates = alternatives.isEmpty ? available : alternatives;
  return candidates[(random ?? Random()).nextInt(candidates.length)];
}
