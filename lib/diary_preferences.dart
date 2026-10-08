import 'domain/population_forecast.dart';

enum DiaryPreset {
  daily('日常'),
  full('完整'),
  compact('紧凑'),
  custom('自定义');

  const DiaryPreset(this.label);
  final String label;
}

/// Presentation only: these choices never change stored records or colony rules.
class DiaryDisplay {
  const DiaryDisplay({
    this.counts = true,
    this.environment = true,
    this.photos = true,
    this.fullNotes = true,
    this.populationExpanded = false,
    this.mortalityExpanded = false,
    this.includeBrood = false,
    this.forecast = false,
    this.horizon = ForecastHorizon.month,
  });

  final bool counts, environment, photos, fullNotes;
  final bool populationExpanded, mortalityExpanded, includeBrood, forecast;
  final ForecastHorizon horizon;

  static DiaryDisplay forPreset(DiaryPreset preset) => switch (preset) {
    DiaryPreset.daily => const DiaryDisplay(counts: false),
    DiaryPreset.compact => const DiaryDisplay(
      counts: false,
      environment: false,
      photos: false,
      fullNotes: false,
    ),
    _ => const DiaryDisplay(),
  };

  DiaryDisplay copyWith({
    bool? counts,
    bool? environment,
    bool? photos,
    bool? fullNotes,
    bool? populationExpanded,
    bool? mortalityExpanded,
    bool? includeBrood,
    bool? forecast,
    ForecastHorizon? horizon,
  }) => DiaryDisplay(
    counts: counts ?? this.counts,
    environment: environment ?? this.environment,
    photos: photos ?? this.photos,
    fullNotes: fullNotes ?? this.fullNotes,
    populationExpanded: populationExpanded ?? this.populationExpanded,
    mortalityExpanded: mortalityExpanded ?? this.mortalityExpanded,
    includeBrood: includeBrood ?? this.includeBrood,
    forecast: forecast ?? this.forecast,
    horizon: horizon ?? this.horizon,
  );

  Map<String, Object> toJson() => {
    'counts': counts,
    'environment': environment,
    'photos': photos,
    'fullNotes': fullNotes,
    'populationExpanded': populationExpanded,
    'mortalityExpanded': mortalityExpanded,
    'includeBrood': includeBrood,
    'forecast': forecast,
    'horizon': horizon.name,
  };

  factory DiaryDisplay.fromJson(Map<String, dynamic> value) {
    bool flag(String key, bool fallback) =>
        value[key] is bool ? value[key] as bool : fallback;
    return DiaryDisplay(
      counts: flag('counts', true),
      environment: flag('environment', true),
      photos: flag('photos', true),
      fullNotes: flag('fullNotes', true),
      populationExpanded: flag('populationExpanded', false),
      mortalityExpanded: flag('mortalityExpanded', false),
      includeBrood: flag('includeBrood', false),
      forecast: flag('forecast', false),
      horizon: ForecastHorizon.values.firstWhere(
        (item) => item.name == value['horizon'],
        orElse: () => ForecastHorizon.month,
      ),
    );
  }
}

class DiaryPreferences {
  const DiaryPreferences({
    this.preset = DiaryPreset.full,
    this.custom = const DiaryDisplay(),
    this.incremental = true,
  });
  final DiaryPreset preset;
  final DiaryDisplay custom;
  final bool incremental;
  DiaryDisplay get display =>
      preset == DiaryPreset.custom ? custom : DiaryDisplay.forPreset(preset);

  DiaryPreferences select(DiaryPreset value) =>
      DiaryPreferences(preset: value, custom: custom, incremental: incremental);
  DiaryPreferences customize(DiaryDisplay value) => DiaryPreferences(
    preset: DiaryPreset.custom,
    custom: value,
    incremental: incremental,
  );
  DiaryPreferences withIncremental(bool value) =>
      DiaryPreferences(preset: preset, custom: custom, incremental: value);
  Map<String, Object> toJson() => {
    'preset': preset.name,
    'custom': custom.toJson(),
    'incremental': incremental,
  };
  factory DiaryPreferences.fromJson(Map<String, dynamic> value) =>
      DiaryPreferences(
        preset: DiaryPreset.values.firstWhere(
          (item) => item.name == value['preset'],
          orElse: () => DiaryPreset.full,
        ),
        custom: value['custom'] is Map<String, dynamic>
            ? DiaryDisplay.fromJson(value['custom'] as Map<String, dynamic>)
            : const DiaryDisplay(),
        incremental: value['incremental'] is bool
            ? value['incremental'] as bool
            : true,
      );
}
