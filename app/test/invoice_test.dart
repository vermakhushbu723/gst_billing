import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
