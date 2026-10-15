import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'backup_data.dart';

/// A readable copy of the local tables. ZIP remains the restorable backup.
class ExcelExport {
  ExcelExport._();

  static const _sheetNames = <String, String>{
    'colonies': '蚁群',
    'care_records': '养蚁日记',
    'milestones': '里程碑',
    'memorials': '英灵殿',
    'nest_entries': '巢体记录',
    'winter_cycles': '越冬记录',
    'flight_observations': '婚飞观察',
    'wild_catch_records': '野采记录',
    'care_tasks': '养护待办',
    'feeder_records': '饲料记录',
    'inventory_items': '物品',
  };
  static const _fieldNames = <String, String>{
    'id': '记录ID',
    'colony_id': '蚁群ID',
    'name': '名称',
    'species': '品种',
    'type': '类型',
    'record_type': '记录类型',
    'task_type': '待办类型',
    'occurred_at': '发生时间',
    'created_at': '创建时间',
    'updated_at': '更新时间',
    'acquired_at': '入手日期',
    'archived': '已归档',
    'notes': '备注',
    'note': '备注',
    'description': '说明',
    'quantity': '数量',
    'group_name': '分组',
    'purchase_price_cents': '购入价（分）',
    'photos_json': '照片路径',
    'cover_photo_path': '封面照片路径',
  };

  static Uint8List encode(Map<String, dynamic> data) {
    BackupData.validate(data);
    final tables = data.entries.toList();
    final sheetNames = <String>[
      '导出说明',
      ...tables.map((e) => _sheetNames[e.key] ?? e.key),
    ];
    if (sheetNames.toSet().length != sheetNames.length ||
        sheetNames.any((name) => name.length > 31)) {
      throw const FormatException('Excel 工作表名称无效。');
    }
    final archive = Archive();
    void add(String name, String contents) {
      final bytes = utf8.encode(contents);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    add('[Content_Types].xml', _contentTypes(sheetNames.length));
    add(
      '_rels/.rels',
      '<?xml version="1.0" encoding="UTF-8"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
          '</Relationships>',
    );
    add('xl/workbook.xml', _workbook(sheetNames));
    add('xl/_rels/workbook.xml.rels', _workbookRels(sheetNames.length));
    add(
      'xl/styles.xml',
      '<?xml version="1.0" encoding="UTF-8"?>'
          '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
          '<fonts count="2"><font><sz val="11"/><name val="Aptos"/></font>'
          '<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Aptos"/></font></fonts>'
          '<fills count="2"><fill><patternFill patternType="none"/></fill>'
          '<fill><patternFill patternType="solid"><fgColor rgb="FF405F4B"/><bgColor indexed="64"/></patternFill></fill></fills>'
          '<borders count="1"><border/></borders>'
          '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
          '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
          '<xf numFmtId="0" fontId="1" fillId="1" borderId="0" xfId="0" applyFont="1" applyFill="1"/></cellXfs>'
          '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
          '</styleSheet>',
    );

    final overview = <List<Object?>>[
      ['蚁记数据导出', 'Excel 用于查看和整理；完整恢复请使用 ZIP 备份。'],
      ['导出时间', DateTime.now().toIso8601String()],
      ['照片', '仅保留记录中的照片路径，不包含照片文件。'],
      ['字段', '表头括号中是数据库原字段名；0 表示否，1 表示是。'],
      ['数据表', '记录数'],
      for (final entry in tables)
        [_sheetNames[entry.key] ?? entry.key, (entry.value as List).length],
    ];
    add('xl/worksheets/sheet1.xml', _worksheet(overview, headerRow: 5));
    for (var index = 0; index < tables.length; index++) {
      final rows = (tables[index].value as List).cast<Map>();
      if (rows.length >= 1048576) {
        throw FormatException('${sheetNames[index + 1]}记录数超过 Excel 单表上限。');
      }
      final columns = <String>{};
      for (final row in rows) {
        columns.addAll(row.keys.cast<String>());
      }
      if (columns.length > 16384) {
        throw FormatException('${sheetNames[index + 1]}字段数超过 Excel 单表上限。');
      }
      final headers = columns.isEmpty ? <String>['暂无记录'] : columns.toList();
      add(
        'xl/worksheets/sheet${index + 2}.xml',
        _worksheet([
          [
            for (final header in headers)
              _fieldNames.containsKey(header)
                  ? '${_fieldNames[header]} ($header)'
                  : header,
          ],
          for (final row in rows) [for (final column in headers) row[column]],
        ], filter: rows.isNotEmpty),
      );
    }
    return ZipEncoder().encodeBytes(archive);
  }

  static String _contentTypes(int count) =>
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
      '${List.generate(count, (i) => '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>').join()}'
      '</Types>';

  static String _workbook(List<String> names) =>
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheets>${List.generate(names.length, (i) => '<sheet name="${_escape(names[i])}" sheetId="${i + 1}" r:id="rId${i + 1}"/>').join()}</sheets>'
      '</workbook>';

  static String _workbookRels(int count) =>
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '${List.generate(count, (i) => '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>').join()}'
      '<Relationship Id="rId${count + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
      '</Relationships>';

  static String _worksheet(
    List<List<Object?>> rows, {
    int headerRow = 1,
    bool filter = false,
  }) {
    final columnCount = rows.fold<int>(
      0,
      (count, row) => row.length > count ? row.length : count,
    );
    final xml = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<sheetViews><sheetView workbookViewId="0">'
      '${filter ? '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>' : ''}'
      '</sheetView></sheetViews>'
      '<sheetFormatPr defaultRowHeight="18"/>'
      '<cols><col min="1" max="$columnCount" width="24" customWidth="1"/></cols>'
      '<sheetData>',
    );
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      xml.write('<row r="${rowIndex + 1}">');
      for (
        var columnIndex = 0;
        columnIndex < rows[rowIndex].length;
        columnIndex++
      ) {
        final value = rows[rowIndex][columnIndex];
        if (value == null) continue;
        final cell = '${_column(columnIndex)}${rowIndex + 1}';
        final style = rowIndex + 1 == headerRow ? ' s="1"' : '';
        if (value is bool) {
          xml.write('<c r="$cell"$style t="b"><v>${value ? 1 : 0}</v></c>');
        } else if (value is num &&
            value.isFinite &&
            (value is! int || value.abs() < 1000000000000000)) {
          xml.write('<c r="$cell"$style><v>$value</v></c>');
        } else {
          final string = value.toString();
          if (string.length > 32767) {
            throw const FormatException('有文字超过 Excel 单元格的长度上限。');
          }
          final safe = _escape(string);
          xml.write(
            '<c r="$cell"$style t="inlineStr"><is><t xml:space="preserve">$safe</t></is></c>',
          );
        }
      }
      xml.write('</row>');
    }
    xml.write('</sheetData>');
    if (filter) {
      xml.write(
        '<autoFilter ref="A1:${_column(columnCount - 1)}${rows.length}"/>',
      );
    }
    xml.write('</worksheet>');
    return xml.toString();
  }

  static String _column(int index) {
    var number = index + 1;
    var result = '';
    while (number > 0) {
      number--;
      result = String.fromCharCode(65 + number % 26) + result;
      number ~/= 26;
    }
    return result;
  }

  static String _escape(String value) => value
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
