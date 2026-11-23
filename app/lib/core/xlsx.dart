import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// One cell: text, number, or a bold heading.
class XCell {
  const XCell(this.value, {this.bold = false});
  final Object? value;
  final bool bold;
}

class XSheet {
  XSheet(this.name, this.rows, {this.widths = const {}});
  final String name;
  final List<List<XCell>> rows;

  /// Column index → width in characters.
  final Map<int, double> widths;
}

/// Minimal .xlsx writer (Office Open XML in a zip). Numbers stay numbers in Excel.
class Xlsx {
  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

  static String _col(int i) {
    var n = i + 1, s = '';
    while (n > 0) {
      final r = (n - 1) % 26;
      s = String.fromCharCode(65 + r) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }

  static String _sheetName(String n, Set<String> used) {
    var s = n.replaceAll(RegExp(r'[\[\]\*\?/\\:]'), ' ').trim();
    if (s.isEmpty) s = 'Sheet';
    if (s.length > 31) s = s.substring(0, 31);
    var out = s, i = 2;
    while (used.contains(out.toLowerCase())) {
      final suffix = ' ($i)';
      out = (s.length + suffix.length > 31 ? s.substring(0, 31 - suffix.length) : s) + suffix;
      i++;
    }
    used.add(out.toLowerCase());
    return out;
  }

  // styles: 0 normal text, 1 bold text, 2 number 0.00, 3 bold number 0.00
  static const _styles = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<numFmts count="1"><numFmt numFmtId="164" formatCode="#,##0.00"/></numFmts>
<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>
<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>
<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="4">
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
<xf numFmtId="164" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/>
</cellXfs>
<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>''';

  static String _sheetXml(XSheet sheet) {
    final b = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">');
    if (sheet.widths.isNotEmpty) {
      b.write('<cols>');
      final keys = sheet.widths.keys.toList()..sort();
      for (final k in keys) {
        b.write('<col min="${k + 1}" max="${k + 1}" width="${sheet.widths[k]!.toStringAsFixed(1)}" customWidth="1"/>');
      }
      b.write('</cols>');
    }
    b.write('<sheetData>');
    for (var r = 0; r < sheet.rows.length; r++) {
      b.write('<row r="${r + 1}">');
      final row = sheet.rows[r];
      for (var c = 0; c < row.length; c++) {
        final cell = row[c];
        final v = cell.value;
        final ref = '${_col(c)}${r + 1}';
        if (v == null || (v is String && v.isEmpty)) continue;
        if (v is num) {
          b.write('<c r="$ref" s="${cell.bold ? 3 : 2}"><v>$v</v></c>');
        } else {
          b.write('<c r="$ref" t="inlineStr" s="${cell.bold ? 1 : 0}"><is><t xml:space="preserve">${_esc('$v')}</t></is></c>');
        }
      }
      b.write('</row>');
    }
    b.write('</sheetData></worksheet>');
    return b.toString();
  }

  static Uint8List build(List<XSheet> sheets) {
    final used = <String>{};
    final names = [for (final s in sheets) _sheetName(s.name, used)];
    final a = Archive();
    void add(String path, String content) {
      final bytes = utf8.encode(content);
      a.addFile(ArchiveFile.bytes(path, bytes));
    }

    add('[Content_Types].xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '${[for (var i = 0; i < sheets.length; i++) '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
        '</Types>');
    add('_rels/.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>');
    add('xl/workbook.xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets>${[for (var i = 0; i < sheets.length; i++) '<sheet name="${_esc(names[i])}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}</sheets>'
        '</workbook>');
    add('xl/_rels/workbook.xml.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '${[for (var i = 0; i < sheets.length; i++) '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>'].join()}'
        '<Relationship Id="rId${sheets.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>');
    add('xl/styles.xml', _styles);
    for (var i = 0; i < sheets.length; i++) {
      add('xl/worksheets/sheet${i + 1}.xml', _sheetXml(sheets[i]));
    }
    return Uint8List.fromList(ZipEncoder().encode(a));
  }
}
