String competitionScoreModeLabel(Object? mode) => switch (mode) {
  'WORKER_GROWTH' => '工蚁净增长',
  'TOTAL_GROWTH' => '虫口净增长',
  _ => '积分制',
};

/// Describes the server's ranking rules; scoring remains on the server.
String competitionScoreRule(
  Map<String, dynamic> detail,
) => switch (detail['scoreMode']) {
  'WORKER_GROWTH' => '按报名后亲工工蚁的净增长排名；合工不计分。',
  'TOTAL_GROWTH' => '按报名后亲工工蚁、卵及亲工幼蛹茧的合计净增长排名；合工不计分。',
  _ =>
    '仅报名时无工蚁及卵幼蛹获基础 ${detail['queenBasePoints'] ?? 10} 分；'
        '亲工工蚁净增 ${detail['workerGrowthPoints'] ?? 2} 分/只；'
        '卵及亲工幼蛹茧净增 ${detail['broodGrowthPoints'] ?? (detail['broodPointsEnabled'] == false ? 0 : 1)} 分/只；'
        '合工不计分。',
};
