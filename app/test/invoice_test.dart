import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gst_billing/core/export.dart';
import 'package:gst_billing/core/format.dart';
import 'package:gst_billing/core/gst.dart';
import 'package:gst_billing/pdf/invoice_pdf.dart';

/// The reference invoice (OM ICE INDUSTRIES, Sales Invoice 290) as the API returns it.
final referenceInvoice = {
  '_id': 'x',
  'invoiceNo': 290,
  'invoicePrefix': '',
  'invoiceDate': '2026-10-01',
  'dueDate': '2026-10-15',
  'status': 'unpaid',
  'intraState': true,
  'placeOfSupply': 'Maharashtra',
  'companySnapshot': {
    'name': 'OM ICE INDUSTRIES',
    'tagline': 'PURE RO TREATED ICE CUBES',
    'address': 'A/8, GIRIRAJ INDUSTRIAL ESTATE, MAHAKALI CAVES ROAD, ANDHERI - EAST, Mumbai Suburban, Maharashtra',
    'city': 'Mumbai',
    'state': 'Maharashtra',
    'pincode': '400092',
    'mobile': '7831888888',
    'email': 'omiceindustries2001@gmail.com',
    'gstin': '27AAEFO6474A1ZC',
    'bank': {
      'accountName': 'Om ice industries',
      'ifsc': 'IBKL0452JSB',
      'accountNo': '004012056003502',
      'bankName': 'Jain Sahakari Bank, Jain Sahakari Bank',
      'branch': 'IMPS',
    },
    'terms': ['Goods once sold will not be taken back or exchanged', 'All disputes are subject to Mumbai jurisdiction only'],
  },
  'billTo': {
    'name': 'GUJARAT MILK PRODUCTS LIMITED',
    'address': '17AB, GOVERNMENT INDUSTRIAL ESTATES, HINDUSTAN NAKA, CHARKOP, KANDIVALI WEST, Mumbai City, Maharashtra, Mumbai, Maharashtra, 400067',
    'gstin': '27AABCG0233H1Z2',
    'pan': 'AABCG0233H',
  },
  'shipTo': {
    'name': 'GUJARAT MILK PRODUCTS LIMITED',
    'address': '17AB, GOVERNMENT INDUSTRIAL ESTATES, HINDUSTAN NAKA, CHARKOP, KANDIVALI WEST, Mumbai City, Maharashtra, Mumbai, Maharashtra, 400067',
  },
  'items': [
    {'name': 'ICE CUBES EDIBLE', 'unit': 'KGS', 'qty': 31377, 'rate': 2.95, 'gstRate': 5, 'taxable': 92562.15, 'tax': 4628.11, 'amount': 97190.26},
  ],
  'taxSummary': [
    {'rate': 5, 'taxable': 92562.15, 'cgst': 2314.05, 'sgst': 2314.05, 'igst': 0},
  ],
  'totalQty': 31377,
  'taxableAmount': 92562.15,
  'totalTax': 4628.11,
  'cgst': 2314.05,
  'sgst': 2314.05,
  'igst': 0,
  'total': 97190.26,
  'receivedAmount': 0,
  'balance': 97190.26,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('GST calculation matches the reference invoice', () {
    final c = calcInvoice([(qty: 31377, rate: 2.95, gstRate: 5)], intraState: true);
    expect(c.taxable, 92562.15);
    expect(c.tax, 4628.11);
    expect(c.cgst, 2314.05);
    expect(c.sgst, 2314.05);
    expect(c.total, 97190.26);
    final i = calcInvoice([(qty: 100, rate: 10, gstRate: 18)], intraState: false);
    expect(i.igst, 180);
    expect(i.total, 1180);
  });

  test('formatting', () {
    expect(amountInWords(97190.26), 'Ninety Seven Thousand One Hundred Ninety Rupees and Twenty Six Paise');
    expect(amountInWords(12500000), 'One Crore Twenty Five Lakh Rupees');
    expect(amountInWords(0), 'Zero Rupees');
    expect(money(97190.26), '97,190.26');
    expect(money(1234567.5), '12,34,567.50');
    expect(dmy('2026-10-01'), '01/10/2026');
    expect(qtyStr(31377.0), '31377');
    expect(invoiceFileName(referenceInvoice), 'GUJARAT_MILK_PRODUCTS_LIMITED_Sales_Invoice_290.pdf');
    expect(waPhone('98765 43210'), '919876543210');
  });

  test('sales CSV export matches the reference report exactly', () async {
    final ref = File(r'C:\Users\Lenovo\Downloads\rai_ice_depot_invoice_report.csv');
    if (!ref.existsSync()) return; // reference only on the developer machine
    final refText = ref.readAsStringSync();
    // rebuild the same report from the reference rows
    final lines = refText.split('\n');
    final headerIdx = lines.indexWhere((l) => l.startsWith('Invoice No,'));
    final rows = <List<Object?>>[];
    for (final l in lines.skip(headerIdx + 1).where((l) => l.isNotEmpty)) {
      final p = l.split(',');
      rows.add([p[0], p[1], p[2], double.parse(p[3]), double.parse(p[4]), p[5], p[6], p[7], p[8], p[9]]);
    }
    final report = ExportReport({
      'type': 'sales',
      'title': 'Sales Summary Report',
      'companyName': 'RAI ICE DEPOT',
      'phone': '9920555557',
      'from': '2026-10-01',
      'to': '2026-10-31',
      'totalLabel': 'Total Sales',
      'total': 63118,
      'columns': [
        for (final c in ['Invoice No', 'Invoice Date', 'Contact Name', 'Amount', 'Remaining Amount', 'Invoice Status', 'Due Date', 'Invoice Link', 'Payment Type', 'Party Category'])
          {'label': c, 'type': c.contains('Amount') ? 'number' : 'text'},
      ],
      'rows': rows,
    });
    expect(utf8.decode(Exporter.csv([report])), refText);
    expect(Exporter.pyNum(3528), '3528.0');
    expect(Exporter.pyNum(92562.15), '92562.15');
    expect(Exporter.pyNum(3528.5), '3528.5');

    final xlsx = Exporter.xlsx([report]);
    File('build/test_export.xlsx').writeAsBytesSync(xlsx);
    final pdf = await Exporter.pdf([report]);
    File('build/test_export.pdf').writeAsBytesSync(pdf);
    expect(String.fromCharCodes(xlsx.sublist(0, 2)), 'PK');
  });

  test('bill without GST: no tax in maths or PDF', () async {
    final c = calcInvoice([(qty: 31377, rate: 2.95, gstRate: 0)], intraState: true);
    expect(c.tax, 0);
    expect(c.total, 92562.15);
    final bill = {
      ...referenceInvoice,
      'gst': false,
      'invoicePrefix': 'B-',
      'invoiceNo': 1,
      'items': [
        {'name': 'ICE CUBES EDIBLE', 'unit': 'KGS', 'qty': 31377, 'rate': 2.95, 'gstRate': 0, 'taxable': 92562.15, 'tax': 0, 'amount': 92562.15},
      ],
      'taxSummary': [],
      'totalTax': 0,
      'cgst': 0,
      'sgst': 0,
      'total': 92562.15,
      'balance': 92562.15,
    };
    expect(invoiceFileName(bill), 'GUJARAT_MILK_PRODUCTS_LIMITED_Bill_B-1.pdf');
    final bytes = await InvoicePdf.build(bill, {});
    File('build/test_bill.pdf').writeAsBytesSync(bytes);
    expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');
  });

  test('builds the invoice PDF', () async {
    // Logo/signature taken from the reference PDF when available (local check only).
    String img(String path) {
      final f = File(path);
      return f.existsSync() ? 'data:image/png;base64,${base64Encode(f.readAsBytesSync())}' : '';
    }

    final company = {'logo': img('build/ref_img0.png'), 'signature': img('build/ref_img1.png')};
    final bytes = await InvoicePdf.build(referenceInvoice, company, copy: 'ORIGINAL');
    expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');
    final out = File('build/test_invoice.pdf')..createSync(recursive: true);
    out.writeAsBytesSync(bytes);
  });
}
