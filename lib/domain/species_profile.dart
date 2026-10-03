/// Bundled reference material, separate from the keeper's local colony data.
class SpeciesProfile {
  const SpeciesProfile({
    required this.name,
    required this.scientificName,
    required this.aliases,
    required this.difficulty,
    required this.subfamily,
    required this.genus,
    required this.queenSize,
    required this.workerSize,
    required this.workerDifferentiation,
    required this.temperature,
    required this.humidity,
    required this.traits,
    required this.food,
    required this.nesting,
    required this.source,
    required this.sourceUrl,
  });

  final String name;
  final String scientificName;
  final List<String> aliases;
  final int difficulty;
  final String subfamily;
  final String genus;
  final String queenSize;
  final String workerSize;
  final String workerDifferentiation;
  final String temperature;
  final String humidity;
  final List<String> traits;
  final String food;
  final String nesting;
  final String source;
  final Uri sourceUrl;

  bool matches(String query) {
    final keyword = query.trim().toLowerCase();
    return [
      name,
      scientificName,
      ...aliases,
      subfamily,
      genus,
    ].any((value) => value.toLowerCase().contains(keyword));
  }
}

/// Resolve an identity exactly; search substrings must not select a species.
SpeciesProfile? findSpeciesProfile(String name) {
  // The colony picker also stores names as 正式名（俗名）.
  final names = RegExp(r'^(.*?)（([^（）]+)）$').firstMatch(name.trim());
  final normalized = (names?.group(1) ?? name).trim().toLowerCase();
  if (normalized.isEmpty) return null;
  for (final profile in speciesProfiles) {
    if ([
      profile.name,
      profile.scientificName,
      ...profile.aliases,
    ].any((value) => value.toLowerCase() == normalized)) {
      return profile;
    }
  }
  return null;
}

// Transcribed only from the visible portion of the supplied reference image.
// Do not infer missing species data or use these values as colony settings.
final speciesProfiles = [
  SpeciesProfile(
    name: '费氏弓背蚁',
    scientificName: 'Camponotus fedtschenkoi',
    aliases: ['黑金弓背蚁', '红金弓背蚁', '黑斑弓背蚁'],
    difficulty: 3,
    subfamily: '蚁亚科 Formicinae',
    genus: '弓背蚁属 Camponotus',
    queenSize: '12.0–13.0 mm',
    workerSize: '5.8–10.0 mm',
    workerDifferentiation: '有分化',
    temperature: '28.0–32.0 °C',
    humidity: '40.0–60.0 %',
    traits: ['单后制', '无兵蚁', '无螫针'],
    food: '偏甜食',
    nesting: '地下、石块、荒漠',
    source: '根据参考图整理，尚未独立核验。饲养参数仅作资料参考，请结合产地、群体阶段和实际状态调整。',
    sourceUrl: Uri.parse('https://antden.net/antShow/10'),
  ),
  SpeciesProfile(
    name: '猎镰猛蚁',
    scientificName: 'Harpegnathos venator',
    aliases: ['猎镰'],
    difficulty: 4,
    subfamily: '猛蚁亚科 Ponerinae',
    genus: '镰猛蚁属 Harpegnathos',
    queenSize: '待补充',
    workerSize: '待补充',
    workerDifferentiation: '待补充',
    temperature: '24.0–26.0 °C（保守起点）',
    humidity: '巢区持续湿润，避免积水和冷凝；活动区偏干且通风',
    traits: ['半闭锁建群', '善跳跃', '有螫针'],
    food: '建群期也需投喂；以小型养殖昆虫等动物性食物为主，及时清理残饵。',
    nesting: '石膏、Ytong 或湿润土巢均可；需预留活动与捕猎空间。',
    source: '根据此前的饲养咨询整理，作为保守的起始参考。不同产地、群体阶段与巢型会影响实际需求；图片和最新资料可联网查看蚁丘页面。',
    sourceUrl: Uri.parse('https://antden.net/antShow/33'),
  ),
  SpeciesProfile(
    name: '窄颈弓背蚁',
    scientificName: 'Camponotus angusticollis',
    aliases: ['窄颈弓背蚁（窄径）'],
    difficulty: 2,
    subfamily: '蚁亚科 Formicinae',
    genus: '弓背蚁属 Camponotus',
    queenSize: '待补充',
    workerSize: '待补充',
    workerDifferentiation: '待补充',
    temperature: '22.0–25.0 °C（已建群的保守起点）',
    humidity: '保持饮水，并在巢内提供湿度梯度；避免冷凝与整箱加湿。',
    traits: ['弓背蚁', '湿度梯度', '需持续饮水'],
    food: '少量糖水与养殖昆虫蛋白搭配，按幼虫和残饵情况调整。',
    nesting: '巢内保留干湿梯度；细砂可少量提供在活动区，不覆盖幼体。',
    source: '根据此前“重庆来源、北京饲养”的咨询整理。该建议不是对所有产地和季节的固定参数；图片和最新资料可联网查看蚁丘页面。',
    sourceUrl: Uri.parse('https://antden.net/antShow/19'),
  ),
  SpeciesProfile(
    name: '横纹齿猛蚁',
    scientificName: 'Odontoponera transversa',
    aliases: ['横纹齿针蚁', 'O. transversa'],
    difficulty: 3,
    subfamily: '猛蚁亚科 Ponerinae',
    genus: '齿猛蚁属 Odontoponera',
    queenSize: '待补充',
    workerSize: '待补充',
    workerDifferentiation: '待补充',
    temperature: '24.0–28.0 °C（保守起点）',
    humidity: '巢区 60.0–80.0 %，保持通风且无积水',
    traits: ['有螫针', '适合干湿梯度', '双后需观察相处情况'],
    food: '以昆虫蛋白为主，少量补充碳水，并始终提供安全饮水。',
    nesting: '提供巢内干湿梯度；避免长期积水、霉变和频繁打扰。',
    source: '根据此前“双后约 70 工”的咨询整理。市售名称可能存在近似种混用，建议结合来源和外形再次确认；图片和最新资料可联网查看蚁丘页面。',
    sourceUrl: Uri.parse('https://antden.net/antShow/73'),
  ),
];
