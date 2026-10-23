import 'package:antkeep/online/competition_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('points explain baseline eligibility and exclude adopted ants', () {
    final rule = competitionScoreRule({
      'scoreMode': 'POINTS',
      'queenBasePoints': 5,
      'workerGrowthPoints': 4,
      'broodGrowthPoints': 3,
    });
    expect(rule, contains('仅报名时无工蚁及卵幼蛹获基础 5 分'));
    expect(rule, contains('亲工工蚁净增 4 分/只'));
    expect(rule, contains('卵及亲工幼蛹茧净增 3 分/只'));
    expect(rule, contains('合工不计分'));
  });

  test('explicit zero points and legacy brood flag keep their meaning', () {
    expect(
      competitionScoreRule({
        'queenBasePoints': 0,
        'workerGrowthPoints': 0,
        'broodGrowthPoints': 0,
      }),
      contains('基础 0 分；亲工工蚁净增 0 分/只；卵及亲工幼蛹茧净增 0 分/只'),
    );
    expect(
      competitionScoreRule({'broodPointsEnabled': false}),
      contains('卵及亲工幼蛹茧净增 0 分/只'),
    );
    expect(competitionScoreRule({}), contains('卵及亲工幼蛹茧净增 1 分/只'));
    expect(
      competitionScoreRule({
        'broodPointsEnabled': false,
        'broodGrowthPoints': 3,
      }),
      contains('卵及亲工幼蛹茧净增 3 分/只'),
    );
  });

  test(
    'growth rankings count the appropriate own population from baseline',
    () {
      expect(
        competitionScoreRule({'scoreMode': 'WORKER_GROWTH'}),
        '按报名后亲工工蚁的净增长排名；合工不计分。',
      );
      expect(
        competitionScoreRule({'scoreMode': 'TOTAL_GROWTH'}),
        '按报名后亲工工蚁、卵及亲工幼蛹茧的合计净增长排名；合工不计分。',
      );
    },
  );
}
