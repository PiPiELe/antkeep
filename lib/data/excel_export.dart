import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'backup_archive.dart';
import 'backup_data.dart';

/// An AntKeep workbook; a companion ZIP can carry its original photos.
class ExcelExport {
  ExcelExport._();

  static const maxInputBytes = 32 * 1024 * 1024;

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
    'photo_path': '里程碑照片路径',
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
      ['蚁记数据导出', 'Excel 可恢复记录；完整恢复照片请使用 ZIP 备份。'],
      ['导出时间', DateTime.now().toIso8601String()],
      ['照片', '仅保留路径供查看；从 Excel 恢复时会清除照片关联。'],
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

  /// Reads an AntKeep workbook, including copies resaved with shared strings.
  /// Photo paths are retained only when a companion package supplies originals.
  static Map<String, dynamic> decode(
    Uint8List bytes, {
    bool keepPhotoPaths = false,
  }) {
    if (bytes.length > maxInputBytes) {
      throw const FormatException('Excel 文件超过 32 MB 的导入上限。');
    }
    BackupArchive.preflightZip(
      bytes,
      entryLimit: 64,
      fileLimit: 64 * 1024 * 1024,
      totalLimit: 96 * 1024 * 1024,
    );
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final parts = <String, ArchiveFile>{};
    for (final file in archive.files.where((file) => file.isFile)) {
      if (file.isSymbolicLink || parts.containsKey(file.name)) {
        throw const FormatException('Excel 文件包含重复或不支持的内容。');
      }
      parts[file.name] = file;
    }
    XmlDocument read(String name) {
      final content = parts[name]?.readBytes();
      if (content == null) throw const FormatException('不是蚁记导出的 Excel 文件。');
      final source = utf8.decode(content);
      if (source.contains('<!DOCTYPE') || source.contains('<!ENTITY')) {
        throw const FormatException('Excel 文件包含不支持的 XML 声明。');
      }
      return XmlDocument.parse(source);
    }

    try {
      final workbook = read('xl/workbook.xml');
      final relationships = read('xl/_rels/workbook.xml.rels');
      final targets = <String, String>{};
      for (final relation in relationships.findAllElements(
        'Relationship',
        namespace: '*',
      )) {
        final id = relation.getAttribute('Id');
        final target = relation.getAttribute('Target');
        if (id == null || target == null) continue;
        final name = target.startsWith('/')
            ? target.substring(1)
            : 'xl/$target';
        if (RegExp(r'^xl/worksheets/[A-Za-z0-9_-]+\.xml$').hasMatch(name)) {
          targets[id] = name;
        }
      }
      final sheets = <String, String>{};
      for (final sheet in workbook.findAllElements('sheet', namespace: '*')) {
        final name = sheet.getAttribute('name');
        final id = sheet.getAttribute('id', namespace: '*');
        if (name == null ||
            id == null ||
            targets[id] == null ||
            sheets.containsKey(name)) {
          throw const FormatException('Excel 工作表目录无效。');
        }
        sheets[name] = targets[id]!;
      }
      if (sheets.length != _sheetNames.length + 1 ||
          !sheets.keys.toSet().containsAll({'导出说明', ..._sheetNames.values})) {
        throw const FormatException('Excel 缺少蚁记导出的数据表。');
      }
      final shared = <String>[];
      if (parts.containsKey('xl/sharedStrings.xml')) {
        for (final entry in read(
          'xl/sharedStrings.xml',
        ).findAllElements('si', namespace: '*')) {
          shared.add(
            entry
                .findAllElements('t', namespace: '*')
                .map((text) => text.innerText)
                .join(),
          );
        }
      }
      final overview = _rows(read(sheets['导出说明']!), shared);
      if (overview.isEmpty || overview.first[0] != '蚁记数据导出') {
        throw const FormatException('不是蚁记导出的 Excel 文件。');
      }
      final data = <String, dynamic>{};
      for (final entry in _sheetNames.entries) {
        final rows = _rows(read(sheets[entry.value]!), shared);
        if (rows.isEmpty) throw FormatException('${entry.value}缺少字段表头。');
        final header = rows.first;
        if (header.length == 1 && header[0] == '暂无记录') {
          if (rows.length != 1) throw FormatException('${entry.value}表头无效。');
          data[entry.key] = <Map<String, Object?>>[];
          continue;
        }
        if (header.isEmpty || header.length > 16384) {
          throw FormatException('${entry.value}表头无效。');
        }
        final fields = <String>[];
        for (
          var index = 0;
          index <= header.keys.reduce((a, b) => a > b ? a : b);
          index++
        ) {
          final label = header[index];
          if (label is! String || label.isEmpty) {
            throw FormatException('${entry.value}表头有空字段。');
          }
          final suffix = RegExp(r'\(([^()]*)\)$').firstMatch(label);
          final field = suffix?.group(1) ?? label;
          if (field.isEmpty || fields.contains(field)) {
            throw FormatException('${entry.value}表头有重复字段。');
          }
          fields.add(field);
        }
        final records = <Map<String, Object?>>[];
        for (final cells in rows.skip(1)) {
          if (cells.isEmpty) continue;
          if (cells.keys.any((index) => index >= fields.length)) {
            throw FormatException('${entry.value}含有表头之外的数据。');
          }
          records.add({
            for (var index = 0; index < fields.length; index++)
              fields[index]: cells[index],
          });
        }
        data[entry.key] = records;
      }
      if (!keepPhotoPaths) clearPhotoPaths(data);
      BackupData.validate(data);
      return data;
    } on XmlException catch (_) {
      throw const FormatException('Excel 文件结构无效。');
    }
  }

  static void clearPhotoPaths(Map<String, dynamic> data) {
    for (final row in (data['colonies'] as List).cast<Map<String, Object?>>()) {
      row['cover_photo_path'] = null;
    }
    for (final table in ['care_records', 'wild_catch_records']) {
      for (final row
          in (data[table] as List? ?? const []).cast<Map<String, Object?>>()) {
        row['photos_json'] = '[]';
      }
    }
    for (final row
        in (data['milestones'] as List? ?? const [])
            .cast<Map<String, Object?>>()) {
      row['photo_path'] = null;
    }
  }

  static List<Map<int, Object?>> _rows(
    XmlDocument document,
    List<String> shared,
  ) {
    final rows = <Map<int, Object?>>[];
    final sheetData = document
        .findAllElements('sheetData', namespace: '*')
        .firstOrNull;
    if (sheetData == null) throw const FormatException('Excel 缺少工作表数据。');
    var lastRow = 0;
    for (final row in sheetData.findElements('row', namespace: '*')) {
      final number = int.tryParse(row.getAttribute('r') ?? '');
      if (number == null ||
          number <= lastRow ||
          number > 1048576 ||
          rows.length >= 100000) {
        throw const FormatException('Excel 行号无效或记录过多。');
      }
      lastRow = number;
      final cells = <int, Object?>{};
      for (final cell in row.findElements('c', namespace: '*')) {
        final address = cell.getAttribute('r') ?? '';
        final match = RegExp(r'^([A-Z]+)([1-9][0-9]*)$').firstMatch(address);
        if (match == null ||
            int.parse(match.group(2)!) != number ||
            cell.findElements('f', namespace: '*').isNotEmpty) {
          throw const FormatException('Excel 单元格位置或公式无效。');
        }
        var column = 0;
        for (final code in match.group(1)!.codeUnits) {
          column = column * 26 + code - 64;
        }
        column--;
        if (column >= 16384 || cells.containsKey(column)) {
          throw const FormatException('Excel 列号无效或重复。');
        }
        final type = cell.getAttribute('t');
        final value = cell
            .findElements('v', namespace: '*')
            .firstOrNull
            ?.innerText;
        Object? decoded;
        if (type == 'inlineStr') {
          decoded = cell
              .findAllElements('t', namespace: '*')
              .map((text) => text.innerText)
              .join();
        } else if (type == 's') {
          final index = int.tryParse(value ?? '');
          if (index == null || index < 0 || index >= shared.length) {
            throw const FormatException('Excel 共享文字索引无效。');
          }
          decoded = shared[index];
        } else if (type == 'str' || type == 'd') {
          decoded = value;
        } else if (type == 'b') {
          if (value != '0' && value != '1') {
            throw const FormatException('Excel 布尔值无效。');
          }
          decoded = int.parse(value!);
        } else if (type == null || type == 'n') {
          if (value != null) {
            final number = num.tryParse(value);
            if (number == null || !number.isFinite) {
              throw const FormatException('Excel 数字无效。');
            }
            decoded =
                number is double &&
                    number.abs() < 1000000000000000 &&
                    number == number.roundToDouble()
                ? number.toInt()
                : number;
          }
        } else {
          throw const FormatException('Excel 包含不支持的单元格类型。');
        }
        if (decoded != null) cells[column] = decoded;
      }
      rows.add(cells);
    }
    return rows;
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
