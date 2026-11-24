import 'package:intl/intl.dart';

final _money = NumberFormat('#,##,##0.00', 'en_IN');
final _int = NumberFormat('#,##,##0', 'en_IN');

double toD(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

/// 97190.26 -> "97,190.26"
String money(dynamic v) => _money.format(toD(v));

/// 97190.26 -> "₹ 97,190.26"
String rupee(dynamic v) => '₹ ${money(v)}';

/// Whole rupees without paise, for compact cards: "₹ 97,190"
String rupeeShort(dynamic v) => '₹ ${_int.format(toD(v).round())}';

/// 31377.0 -> "31377", 2.5 -> "2.5"
String qtyStr(dynamic v) {
  final d = toD(v);
  if (d == d.roundToDouble()) return d.toInt().toString();
  return d.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

/// Rate as on the invoice: 2.95 -> "2.95", 1500 -> "1,500"
String rateStr(dynamic v) {
  final d = toD(v);
  if (d == d.roundToDouble()) return _int.format(d);
  return money(d);
}

String pct(dynamic v) => '${qtyStr(v)}%';

/// "2026-10-01" -> "01/10/2026"
String dmy(dynamic ymd) {
  final s = '${ymd ?? ''}';
  if (s.length < 10) return '';
  return '${s.substring(8, 10)}/${s.substring(5, 7)}/${s.substring(0, 4)}';
}

String ymdOf(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
DateTime? parseYmd(dynamic s) => DateTime.tryParse('${s ?? ''}');
String today() => ymdOf(DateTime.now());

String invNo(Map inv) => '${inv['invoicePrefix'] ?? ''}${inv['invoiceNo'] ?? ''}';

String monthLabel(String ym) {
  final d = DateTime.tryParse('$ym-01');
  return d == null ? ym : DateFormat('MMM').format(d);
}

/// File name in the same style as the reference: GUJARAT_MILK_PRODUCTS_LIMITED_Sales_Invoice_290.pdf
String invoiceFileName(Map inv) {
  final party = '${inv['billTo']?['name'] ?? 'Invoice'}'
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  final plain = inv['gst'] == false;
  final word = switch ('${inv['docType'] ?? 'invoice'}') {
    'quotation' => plain ? 'Estimate' : 'Quotation',
    'credit_note' => plain ? 'Sales_Return' : 'Credit_Note',
    'challan' => 'Delivery_Challan',
    _ => plain ? 'Bill' : 'Sales_Invoice',
  };
  return '${party}_${word}_${invNo(inv)}.pdf';
}

/// Digits for wa.me: adds India code to 10 digit numbers.
String waPhone(String? phone) {
  var d = (phone ?? '').replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('0') && d.length == 11) d = d.substring(1);
  if (d.length == 10) d = '91$d';
  return d;
}

const _ones = [
  '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve',
  'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen',
];
const _tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];

String _two(int n) => n < 20 ? _ones[n] : '${_tens[n ~/ 10]}${n % 10 > 0 ? ' ${_ones[n % 10]}' : ''}';

String _three(int n) {
  final h = n ~/ 100, r = n % 100;
  final parts = <String>[];
  if (h > 0) parts.add('${_ones[h]} Hundred');
  if (r > 0) parts.add(_two(r));
  return parts.join(' ');
}

String _indian(int n) {
  if (n == 0) return 'Zero';
  final parts = <String>[];
  final crore = n ~/ 10000000;
  n %= 10000000;
  final lakh = n ~/ 100000;
  n %= 100000;
  final thousand = n ~/ 1000;
  n %= 1000;
  if (crore > 0) parts.add('${_indian(crore)} Crore');
  if (lakh > 0) parts.add('${_two(lakh)} Lakh');
  if (thousand > 0) parts.add('${_two(thousand)} Thousand');
  if (n > 0) parts.add(_three(n));
  return parts.join(' ');
}

/// 97190.26 -> "Ninety Seven Thousand One Hundred Ninety Rupees and Twenty Six Paise"
String amountInWords(dynamic amount) {
  final p = (toD(amount) * 100).round();
  final rupees = p ~/ 100, paise = p % 100;
  var s = '${_indian(rupees)} Rupees';
  if (paise > 0) s += ' and ${_two(paise)} Paise';
  return s;
}
