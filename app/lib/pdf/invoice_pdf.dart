import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/format.dart';

/// Builds the tax invoice PDF in the same layout as the reference
/// (OM ICE INDUSTRIES Sales Invoice 290).
class InvoicePdf {
  static pw.Font? _regular, _medium, _bold;

  static Future<void> _loadFonts() async {
    _regular ??= pw.Font.ttf(await rootBundle.load('assets/fonts/roboto-regular.ttf'));
    _medium ??= pw.Font.ttf(await rootBundle.load('assets/fonts/roboto-medium.ttf'));
    _bold ??= pw.Font.ttf(await rootBundle.load('assets/fonts/roboto-bold.ttf'));
  }

  static pw.ImageProvider? _image(dynamic dataUrl) {
    final s = '${dataUrl ?? ''}';
    final i = s.indexOf(',');
    if (!s.startsWith('data:image/') || i < 0) return null;
    try {
      return pw.MemoryImage(base64Decode(s.substring(i + 1)));
    } catch (_) {
      return null;
    }
  }

  static const _grey = PdfColor.fromInt(0xFF555555);
  static const _lightGrey = PdfColor.fromInt(0xFF9A9A9A);
  static const _barGrey = PdfColor.fromInt(0xFFE6E6E6);
  static const _line = PdfColor.fromInt(0xFFDDDDDD);

  /// [company] is the full company record (with logo/signature images).
  /// Text details come from the invoice's own snapshot so old invoices never change.
  static Future<Uint8List> build(Map inv, Map company, {String copy = 'ORIGINAL'}) async {
    await _loadFonts();
    final c = Map<String, dynamic>.from(inv['companySnapshot'] ?? company);
    final bank = Map<String, dynamic>.from(c['bank'] ?? {});
    final billTo = Map<String, dynamic>.from(inv['billTo'] ?? {});
    final shipTo = Map<String, dynamic>.from(inv['shipTo'] ?? {});
    final items = List<Map>.from(inv['items'] ?? []);
    final taxRows = List<Map>.from(inv['taxSummary'] ?? []);
    final terms = List<String>.from((c['terms'] ?? []).map((e) => '$e'));
    final logo = _image(company['logo']);
    final signature = _image(company['signature']);
    final accent = PdfColor.fromHex(_hex(c['color'] ?? company['color']));
    final cancelled = inv['status'] == 'cancelled';

    // fontNormal must be set too, otherwise copyWith(font:) is ignored by the pdf package.
    pw.TextStyle st(pw.Font? f, {double size = 9.5, PdfColor color = PdfColors.black}) =>
        pw.TextStyle(font: f, fontNormal: f, fontSize: size, color: color, lineSpacing: 1.5);
    final base = st(_regular);
    final medium = st(_medium);
    final bold = st(_bold);
    final small = st(_regular, size: 7.5, color: _lightGrey);

    pw.Widget rich(String label, String value, {pw.TextStyle? style}) => pw.RichText(
          text: pw.TextSpan(style: style ?? base, children: [
            pw.TextSpan(text: '$label ', style: (style ?? base).copyWith(font: _bold, fontNormal: _bold)),
            pw.TextSpan(text: value),
          ]),
        );

    final companyAddress = [c['address'], c['city'], c['state'], c['pincode']]
        .map((e) => '${e ?? ''}'.trim())
        .where((e) => e.isNotEmpty)
        .join(', ');

    // ---------- Header ----------
    final topRow = pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Row(children: [
          pw.Text('TAX INVOICE', style: medium.copyWith(fontSize: 10)),
          pw.SizedBox(width: 8),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: _lightGrey, width: 0.8)),
            child: pw.Text(copy, style: base.copyWith(fontSize: 9.5, color: _lightGrey)),
          ),
          if (cancelled) ...[
            pw.SizedBox(width: 8),
            pw.Text('CANCELLED', style: bold.copyWith(color: PdfColors.red, fontSize: 10)),
          ],
        ]),
        pw.Text('${c['tagline'] ?? ''}'.toUpperCase(), style: medium.copyWith(fontSize: 10)),
      ],
    );

    final header = pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logo != null) ...[
          pw.Container(width: 92, height: 74, alignment: pw.Alignment.center, child: pw.Image(logo, fit: pw.BoxFit.contain)),
          pw.SizedBox(width: 16),
        ],
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('${c['name'] ?? ''}', style: st(_bold, size: 21)),
            pw.SizedBox(height: 4),
            if (companyAddress.isNotEmpty) pw.Text(companyAddress, style: base),
            pw.Row(children: [
              if ('${c['mobile'] ?? ''}'.isNotEmpty) ...[rich('Mobile:', '${c['mobile']}'), pw.SizedBox(width: 18)],
              if ('${c['gstin'] ?? ''}'.isNotEmpty) rich('GSTIN:', '${c['gstin']}'),
            ]),
            if ('${c['email'] ?? ''}'.isNotEmpty) rich('Email:', '${c['email']}'),
          ]),
        ),
      ],
    );

    final infoBar = pw.Container(
      color: _barGrey,
      padding: const pw.EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      child: pw.Column(children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          rich('Invoice No.:', invNo(inv), style: base.copyWith(fontSize: 10)),
          rich('Invoice Date:', dmy(inv['invoiceDate']), style: base.copyWith(fontSize: 10)),
          '${inv['dueDate'] ?? ''}'.isNotEmpty
              ? rich('Due Date:', dmy(inv['dueDate']), style: base.copyWith(fontSize: 10))
              : pw.SizedBox(),
        ]),
        if ('${inv['vehicleNo'] ?? ''}'.isNotEmpty || '${inv['poNumber'] ?? ''}'.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            '${inv['poNumber'] ?? ''}'.isNotEmpty ? rich('PO No.:', '${inv['poNumber']}') : pw.SizedBox(),
            '${inv['vehicleNo'] ?? ''}'.isNotEmpty ? rich('Vehicle No.:', '${inv['vehicleNo']}') : pw.SizedBox(),
          ]),
        ],
      ]),
    );

    pw.Widget labelLine(String label, String value) => value.trim().isEmpty
        ? pw.SizedBox()
        : pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('$label  ', style: base),
            pw.Expanded(child: pw.Text(value, style: base)),
          ]);

    final parties = pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('BILL TO', style: medium.copyWith(fontSize: 10)),
            pw.SizedBox(height: 5),
            pw.Text('${billTo['name'] ?? ''}', style: bold.copyWith(fontSize: 10)),
            pw.SizedBox(height: 2),
            if ('${billTo['address'] ?? ''}'.isNotEmpty) pw.Text('${billTo['address']}', style: base),
            labelLine('GSTIN:', '${billTo['gstin'] ?? ''}'),
            labelLine('PAN Number:', '${billTo['pan'] ?? ''}'),
            if ('${billTo['gstin'] ?? ''}'.isEmpty) labelLine('Mobile:', '${billTo['phone'] ?? ''}'),
            labelLine('Place of Supply:', '${inv['placeOfSupply'] ?? ''}'),
          ]),
        ),
        pw.SizedBox(width: 24),
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('SHIP TO', style: medium.copyWith(fontSize: 10)),
            pw.SizedBox(height: 5),
            pw.Text('${shipTo['name'] ?? billTo['name'] ?? ''}', style: bold.copyWith(fontSize: 10)),
            pw.SizedBox(height: 2),
            pw.Text('${shipTo['address'] ?? billTo['address'] ?? ''}', style: base),
          ]),
        ),
      ],
    );

    // ---------- Items ----------
    const widths = {
      0: pw.FlexColumnWidth(4.3),
      1: pw.FlexColumnWidth(1.7),
      2: pw.FlexColumnWidth(1.3),
      3: pw.FlexColumnWidth(1.7),
      4: pw.FlexColumnWidth(1.8),
    };
    pw.Widget cell(pw.Widget child, {bool right = false}) => pw.Container(
          padding: const pw.EdgeInsets.fromLTRB(9, 8, 9, 8),
          alignment: right ? pw.Alignment.topRight : pw.Alignment.topLeft,
          child: child,
        );

    final headStyle = medium.copyWith(fontSize: 10);
    final itemTable = pw.Table(
      columnWidths: widths,
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(color: PdfColors.black, width: 0.8),
              bottom: pw.BorderSide(color: PdfColors.black, width: 1.6),
            ),
          ),
          children: [
            cell(pw.Text('ITEMS', style: headStyle)),
            cell(pw.Text('QTY.', style: headStyle), right: true),
            cell(pw.Text('RATE', style: headStyle), right: true),
            cell(pw.Text('TAX', style: headStyle), right: true),
            cell(pw.Text('AMOUNT', style: headStyle), right: true),
          ],
        ),
        for (final it in items)
          pw.TableRow(
            decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.8))),
            children: [
              cell(pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('${it['name'] ?? ''}', style: base),
                if ('${it['description'] ?? ''}'.isNotEmpty) pw.Text('${it['description']}', style: st(_regular, size: 7.5, color: _grey)),
                if ('${it['hsn'] ?? ''}'.isNotEmpty) pw.Text('HSN: ${it['hsn']}', style: small),
              ])),
              cell(pw.Text('${qtyStr(it['qty'])} ${it['unit'] ?? ''}'.trim(), style: base), right: true),
              cell(pw.Text(rateStr(it['rate']), style: base), right: true),
              cell(
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
                  pw.Text(money(it['tax']), style: base),
                  pw.Text('(${pct(it['gstRate'])})', style: small),
                ]),
                right: true,
              ),
              cell(pw.Text(money(it['amount']), style: base), right: true),
            ],
          ),
      ],
    );

    final subtotal = pw.Table(
      columnWidths: widths,
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(color: PdfColors.black, width: 1.6),
              bottom: pw.BorderSide(color: PdfColors.black, width: 1.6),
            ),
          ),
          children: [
            cell(pw.Text('SUBTOTAL', style: bold)),
            cell(pw.Text(qtyStr(inv['totalQty']), style: bold), right: true),
            cell(pw.SizedBox()),
            cell(pw.Text(rupee(inv['totalTax']), style: bold), right: true),
            cell(pw.Text(rupee(inv['total']), style: bold), right: true),
          ],
        ),
      ],
    );

    // ---------- Footer: bank + terms | totals + words + signatures ----------
    pw.Widget bankRow(String label, String value) => value.trim().isEmpty
        ? pw.SizedBox()
        : pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 1),
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.SizedBox(width: 80, child: pw.Text(label, style: base)),
              pw.Expanded(child: pw.Text(value, style: base)),
            ]),
          );

    final hasBank = [bank['accountName'], bank['accountNo'], bank['ifsc'], bank['bankName']].any((e) => '${e ?? ''}'.isNotEmpty);
    final left = pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      if (hasBank) ...[
        pw.Text('BANK DETAILS', style: bold),
        pw.SizedBox(height: 2),
        bankRow('Name:', '${bank['accountName'] ?? ''}'),
        bankRow('IFSC Code:', '${bank['ifsc'] ?? ''}'),
        bankRow('Account No:', '${bank['accountNo'] ?? ''}'),
        bankRow('Bank:', [bank['bankName'], bank['branch']].where((e) => '${e ?? ''}'.isNotEmpty).join('\n')),
        bankRow('UPI ID:', '${bank['upiId'] ?? ''}'),
        pw.SizedBox(height: 16),
      ],
      if ('${inv['notes'] ?? ''}'.trim().isNotEmpty) ...[
        pw.Text('NOTES', style: bold),
        pw.Text('${inv['notes']}', style: base),
        pw.SizedBox(height: 12),
      ],
      if (terms.isNotEmpty) ...[
        pw.Text('TERMS AND CONDITIONS', style: bold),
        for (var i = 0; i < terms.length; i++) pw.Text('${i + 1}. ${terms[i]}', style: base),
      ],
    ]);

    pw.Widget totalRow(String label, String value, {bool strong = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 0.5),
          child: pw.Row(children: [
            pw.Expanded(child: pw.Text(label, textAlign: pw.TextAlign.right, style: strong ? bold : base)),
            pw.SizedBox(width: 105, child: pw.Text(value, textAlign: pw.TextAlign.right, style: strong ? bold : base)),
          ]),
        );

    final received = toD(inv['receivedAmount']);
    final right = pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
      pw.Container(
        width: 190,
        child: pw.Column(children: [
          totalRow('Taxable Amount', rupee(inv['taxableAmount'])),
          for (final t in taxRows)
            if (inv['intraState'] != false) ...[
              totalRow('CGST @${pct(toD(t['rate']) / 2)}', rupee(t['cgst'])),
              totalRow('SGST @${pct(toD(t['rate']) / 2)}', rupee(t['sgst'])),
            ] else
              totalRow('IGST @${pct(t['rate'])}', rupee(t['igst'])),
          pw.Divider(color: PdfColors.black, thickness: 0.8, height: 8),
          totalRow('Total Amount', rupee(inv['total']), strong: true),
          pw.Divider(color: PdfColors.black, thickness: 0.8, height: 8),
          totalRow('Received Amount', received == 0 ? '₹ 0' : rupee(received)),
          if (received > 0) totalRow('Balance Amount', rupee(inv['balance'])),
        ]),
      ),
      pw.SizedBox(height: 18),
      pw.Text('Total Amount (in words)', style: medium),
      pw.Text(amountInWords(inv['total']), style: base, textAlign: pw.TextAlign.right),
    ]);

    final signatures = pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
      pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
      pw.SizedBox(height: 14),
      pw.Container(
        width: 140,
        height: 60,
        alignment: pw.Alignment.centerRight,
        child: signature != null ? pw.Image(signature, fit: pw.BoxFit.contain) : pw.SizedBox(),
      ),
      pw.SizedBox(height: 6),
      pw.Text('AUTHORISED SIGNATORY FOR', style: bold),
      pw.Text('${c['name'] ?? ''}', style: base),
      pw.SizedBox(height: 10),
      pw.Container(
        width: 215,
        height: 66,
        decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.black, width: 0.8)),
      ),
      pw.SizedBox(height: 10),
      pw.Text("Receiver's Signature", style: bold),
      ]),
    ]);

    final doc = pw.Document(
      title: 'Tax Invoice ${invNo(inv)}',
      author: '${c['name'] ?? ''}',
      creator: 'GST Billing',
      theme: pw.ThemeData.withFont(base: _regular, bold: _bold),
    );
    final emptyRows = items.length < 3 ? (3 - items.length) * 14.0 + 26 : 18.0;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 22, 28, 24),
        footer: (ctx) => ctx.pagesCount > 1
            ? pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: small),
              )
            : pw.SizedBox(),
        build: (ctx) => [
          topRow,
          pw.SizedBox(height: 18),
          header,
          pw.SizedBox(height: 22),
          pw.Container(height: 5.5, color: accent),
          infoBar,
          pw.SizedBox(height: 12),
          parties,
          pw.SizedBox(height: 14),
          itemTable,
          pw.SizedBox(height: emptyRows),
          subtotal,
          pw.SizedBox(height: 10),
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(child: left),
            pw.SizedBox(width: 20),
            pw.Expanded(child: right),
          ]),
          signatures,
        ],
      ),
    );
    return doc.save();
  }

  static String _hex(dynamic v) {
    final s = '${v ?? ''}';
    return RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(s) ? s : '#000000';
  }
}
