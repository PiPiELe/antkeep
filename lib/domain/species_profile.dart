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
const speciesProfiles = [
  SpeciesProfile(
    name: '费氏弓背蚁',
    scientificName: 'Camponotus fedtschenkoi',
    aliases: ['黑金弓背蚁', '黑斑弓背蚁'],
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
  ),
];
