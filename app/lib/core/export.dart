import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'api.dart';
import 'format.dart';
import 'xlsx.dart';

/// A report from `/api/export/:type`.
class ExportReport {
  ExportReport(Map<String, dynamic> j)
      : type = '${j['type']}',
        title = '${j['title']}',
        companyName = '${j['companyName'] ?? ''}',
        phone = '${j['phone'] ?? ''}',
        from = '${j['from'] ?? ''}',
        to = '${j['to'] ?? ''}',
        totalLabel = '${j['totalLabel'] ?? 'Total'}',
        total = j['total'] as num? ?? 0,
        columns = [for (final c in j['columns'] as List) (label: '${c['label']}', number: c['type'] == 'number')],
        rows = [for (final r in j['rows'] as List) List<Object?>.from(r as List)];

  final String type, title, companyName, phone, from, to, totalLabel;
  final num total;
  final List<({String label, bool number})> columns;
  final List<List<Object?>> rows;

  String get dated => from.isEmpty && to.isEmpty ? 'All dates' : '${dmy(from)} - ${dmy(to)}';
}

/// What can be exported (key = API type).
const exportTypes = <(String, String)>[
  ('sales', 'Sales Summary (invoices)'),
  ('quotations', 'Quotations'),
  ('challans', 'Delivery Challans'),
  ('credit_notes', 'Credit Notes (Sales Returns)'),
  ('payments', 'Payments Received'),
  ('expenses', 'Expenses'),
  ('customers', 'Customers / Parties'),
  ('products', 'Products / Items'),
  ('customer_sales', 'Customer-wise Sales'),
  ('item_sales', 'Item-wise Sales'),
  ('gst', 'GST Summary'),
];

class Exporter {
  static Future<ExportReport> fetch(String type, {required String company, String from = '', String to = '', String? gst}) async {
    final r = await Api.instance.get('/export/$type', {'company': company, 'from': from, 'to': to, 'gst': gst});
    return ExportReport(Map<String, dynamic>.from(r));
  }

  /// Numbers the way the reference report writes them: 3528.0, 92562.15
  static String pyNum(num v) {
    final d = v.toDouble();
    if (d == d.roundToDouble()) return '${d.toInt()}.0';
    return d.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '.0');
  }

  static String _csvCell(Object? v) {
    final s = v is num ? pyNum(v) : '${v ?? ''}';
    return s.contains(RegExp(r'[",\n\r]')) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  static void _csvSection(StringBuffer b, ExportReport r) {
    b
      ..writeln(r.title)
      ..writeln('Dated: ${r.dated}')
      ..writeln(r.companyName)
      ..writeln('Phone No: ${r.phone}')
      ..writeln('${r.totalLabel}: ${pyNum(r.total)}')
      ..writeln()
      ..writeln()
      ..writeln(r.columns.map((c) => _csvCell(c.label)).join(','));
    for (final row in r.rows) {
      b.writeln(row.map(_csvCell).join(','));
    }
  }

  /// Same layout as rai_ice_depot_invoice_report.csv (header block, two blank lines, table).
  static Uint8List csv(List<ExportReport> reports) {
    final first = reports.first;
    final b = StringBuffer()
      ..writeln('Company Name: ${first.companyName}')
      ..writeln('Phone No: ${first.phone}')
      ..writeln()
      ..writeln();
    for (var i = 0; i < reports.length; i++) {
      if (i > 0) {
        b
          ..writeln()
          ..writeln();
      }
      _csvSection(b, reports[i]);
    }
    return Uint8List.fromList(utf8.encode(b.toString()));
  }

  static Uint8List xlsx(List<ExportReport> reports) {
    final sheets = <XSheet>[];
    for (final r in reports) {
      final rows = <List<XCell>>[
        [XCell('Company Name: ${r.companyName}', bold: true)],
        [XCell('Phone No: ${r.phone}')],
        [],
        [XCell(r.title, bold: true)],
        [XCell('Dated: ${r.dated}')],
        [XCell('${r.totalLabel}:', bold: true), XCell(r.total, bold: true)],
        [],
        [for (final c in r.columns) XCell(c.label, bold: true)],
        for (final row in r.rows) [for (final v in row) XCell(v)],
      ];
      // width from the longest value in each column (capped)
      final widths = <int, double>{};
      for (var c = 0; c < r.columns.length; c++) {
        var w = r.columns[c].label.length.toDouble();
        for (final row in r.rows.take(500)) {
          if (c < row.length) {
            final v = row[c];
            final len = v is num ? money(v).length : '${v ?? ''}'.length;
            if (len > w) w = len.toDouble();
          }
        }
        widths[c] = (w + 2).clamp(8, 60).toDouble();
      }
      final name = exportTypes.firstWhere((t) => t.$1 == r.type, orElse: () => (r.type, r.title)).$2;
      sheets.add(XSheet(name, rows, widths: widths));
    }
    return Xlsx.build(sheets);
  }

  static Future<Uint8List> pdf(List<ExportReport> reports) async {
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/roboto-regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/roboto-bold.ttf'));
    final doc = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold), title: reports.first.title, creator: 'mybillwill');
    for (final r in reports) {
      final wide = r.columns.length > 6;
      final fontSize = r.columns.length > 8 ? 7.0 : 8.5;
      String cell(Object? v) => v is num ? money(v) : '${v ?? ''}';
      doc.addPage(pw.MultiPage(
        pageFormat: wide ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('mybillwill • Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
        ),
        build: (_) => [
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(r.companyName, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
                if (r.phone.isNotEmpty) pw.Text('Phone No: ${r.phone}', style: const pw.TextStyle(fontSize: 9)),
                pw.SizedBox(height: 6),
                pw.Text(r.title, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#0E6E70'))),
                pw.Text('Dated: ${r.dated}', style: const pw.TextStyle(fontSize: 9)),
              ]),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: pw.BoxDecoration(color: PdfColor.fromHex('#FBF1D8'), borderRadius: pw.BorderRadius.circular(4)),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text(r.totalLabel, style: const pw.TextStyle(fontSize: 8)),
                pw.Text(r.type == 'products' ? '${r.total}' : money(r.total), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
              ]),
            ),
          ]),
          pw.SizedBox(height: 10),
          if (r.rows.isEmpty)
            pw.Text('No records for this period.', style: const pw.TextStyle(fontSize: 9))
          else
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontSize: fontSize, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#0E6E70')),
              cellStyle: pw.TextStyle(fontSize: fontSize),
              oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF5F7F7)),
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              cellAlignments: {for (var i = 0; i < r.columns.length; i++) if (r.columns[i].number) i: pw.Alignment.centerRight},
              headers: [for (final c in r.columns) c.label],
              data: [for (final row in r.rows) [for (final v in row) cell(v)]],
            ),
        ],
      ));
    }
    return doc.save();
  }
}
