import 'dart:convert';
import 'dart:io';

import 'package:antkeep/domain/imported_species_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'catalog merges exact duplicates and keeps ambiguous search candidates',
    () {
      final audit = jsonDecode(
        File('docs/data/antden-species-import.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final accepted = audit['accepted'] as List<dynamic>;
      final excluded = audit['excluded'] as List<dynamic>;
      final options = importedSpeciesOptions.values
          .expand((names) => names)
          .toList();
      expect(options, hasLength(710));
      expect(options.toSet(), hasLength(options.length));
      expect(accepted, hasLength(772));
      expect(excluded, isEmpty);
      expect(audit['mergedDuplicates'], hasLength(2));
      expect(options.where((name) => name == '大眼响蚁'), hasLength(1));
      expect(options.where((name) => name == '宾氏长齿蚁'), hasLength(1));
      expect(
        {...accepted, ...excluded}.map((row) => row['id']).toSet(),
        hasLength(772),
      );
      for (final row in accepted) {
        final name = row['displayName'] as String;
        if (row['existing'] != true) {
          expect(importedSpeciesOptions[row['category']], contains(name));
        }
        expect(importedSpeciesAliases[row['scientificName']] ?? name, name);
      }
      for (final row in excluded) {
        expect(options, isNot(contains(row['name'])));
        expect(
          importedSpeciesAliases.containsKey(row['scientificName']),
          isFalse,
        );
      }
      expect(importedSpeciesAliases['Messor ebeninus'], '乌檀收获蚁');
      expect(importedSpeciesAliases['Camponotus fedtschenkoi'], '费氏弓背蚁（黑金弓背蚁）');
      expect(importedSpeciesAliases.containsKey('拟黑多刺蚁'), isFalse);
      expect(importedSpeciesAliases.containsKey('无颚齿收获蚁'), isFalse);
      expect(importedSpeciesSearchAliases['肩角弓背蚁'], hasLength(2));
      expect(
        importedSpeciesSearchAliases['拟黑多刺蚁'],
        containsAll(['拟黑多刺蚁', '双齿多刺蚁']),
      );
      expect(importedSpeciesAliases['Myrmecia sp.17'], 'SP17牛蚁（未定种）');
      for (final alias in importedSpeciesSearchAliases.keys) {
        expect(importedSpeciesAliases.containsKey(alias), isFalse);
      }
    },
  );
}
