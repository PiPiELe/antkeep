import 'dart:convert';

import 'package:antkeep/data/excel_export.dart';
import 'package:antkeep/domain/models.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Excel export keeps every table and treats user text as text', () {
    final now = DateTime(2026, 10, 15);
    final colony = Colony(
      id: 'colony-1',
      name: '=SUM(1,2) & <蚁群>',
      createdAt: now,
      updatedAt: now,
    );
    final bytes = ExcelExport.encode({
      'colonies': [colony.toMap()],
      'care_records': <Map<String, Object?>>[],
      'milestones': <Map<String, Object?>>[],
      'inventory_items': <Map<String, Object?>>[],
    });
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    String part(String name) =>
        utf8.decode(archive.findFile(name)!.readBytes()!);

    expect(part('xl/workbook.xml'), contains('name="蚁群"'));
    expect(part('xl/workbook.xml'), contains('name="养蚁日记"'));
    expect(part('xl/workbook.xml'), contains('name="物品"'));
    expect(part('xl/worksheets/sheet1.xml'), contains('完整恢复照片请使用 ZIP 备份'));
    final colonies = part('xl/worksheets/sheet2.xml');
    expect(
      colonies,
      contains('<t xml:space="preserve">=SUM(1,2) &amp; &lt;蚁群&gt;</t>'),
    );
    expect(colonies, contains('<t xml:space="preserve">名称 (name)</t>'));
    expect(colonies, contains('<autoFilter ref="A1:'));
    expect(part('xl/worksheets/sheet3.xml'), contains('暂无记录'));
  });

  test('Excel import restores all records while removing photo references', () {
    final now = DateTime(2026, 10, 15);
    final data = <String, dynamic>{
      'memorials': <Map<String, Object?>>[],
      'colonies': [
        Colony(
          id: 'colony-1',
          name: '蚁群 & 1',
          coverPhotoPath: 'cover.jpg',
          createdAt: now,
          updatedAt: now,
        ).toMap(),
      ],
      'nest_entries': <Map<String, Object?>>[],
      'winter_cycles': <Map<String, Object?>>[],
      'flight_observations': <Map<String, Object?>>[],
      'wild_catch_records': <Map<String, Object?>>[],
      'care_records': [
        CareRecord(
          id: 'record-1',
          colonyId: 'colony-1',
          type: CareRecordType.observation,
          occurredAt: now,
          createdAt: now,
          note: '温度 < 25',
          photos: const ['diary.jpg'],
        ).toMap(),
      ],
      'milestones': <Map<String, Object?>>[],
      'care_tasks': <Map<String, Object?>>[],
      'feeder_records': <Map<String, Object?>>[],
      'inventory_items': <Map<String, Object?>>[],
    };
    final restored = ExcelExport.decode(ExcelExport.encode(data));
    expect((restored['colonies'] as List).single['name'], '蚁群 & 1');
    expect((restored['colonies'] as List).single['cover_photo_path'], isNull);
    expect((restored['care_records'] as List).single['note'], '温度 < 25');
    expect((restored['care_records'] as List).single['photos_json'], '[]');
    expect(restored.keys, containsAll(data.keys));
  });
}
