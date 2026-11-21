// Same calculation as backend/src/utils/gst.js, used for the live totals
// while an invoice is being typed. The server result is what gets saved.

double round2(num n) => ((n + 2.220446049250313e-16) * 100).round() / 100;

const gstRates = <double>[0, 0.25, 3, 5, 12, 18, 28, 40];
const units = ['KGS', 'NOS', 'PCS', 'BAGS', 'BOX', 'LTR', 'TON', 'MTR', 'DOZ', 'SET'];

class LineCalc {
  LineCalc(this.taxable, this.tax) : amount = round2(taxable + tax);
  final double taxable;
  final double tax;
  final double amount;
}

LineCalc calcLine(double qty, double rate, double gstRate) {
  final taxable = round2(qty * rate);
  return LineCalc(taxable, round2(taxable * gstRate / 100));
}

class TaxRow {
  TaxRow(this.rate, this.taxable, this.cgst, this.sgst, this.igst);
  final double rate, taxable, cgst, sgst, igst;
}

class InvoiceCalc {
  double totalQty = 0, taxable = 0, tax = 0, cgst = 0, sgst = 0, igst = 0, total = 0;
  List<TaxRow> rows = [];
}

InvoiceCalc calcInvoice(List<({double qty, double rate, double gstRate})> lines, {required bool intraState}) {
  final c = InvoiceCalc();
  final byRate = <double, double>{};
  for (final l in lines) {
    final r = calcLine(l.qty, l.rate, l.gstRate);
    c.totalQty += l.qty;
    c.taxable += r.taxable;
    c.tax += r.tax;
    byRate[l.gstRate] = round2((byRate[l.gstRate] ?? 0) + r.taxable);
  }
  final keys = byRate.keys.where((k) => k > 0).toList()..sort();
  for (final rate in keys) {
    final t = byRate[rate]!;
    if (intraState) {
      final half = round2(t * rate / 200);
      c.rows.add(TaxRow(rate, t, half, half, 0));
    } else {
      c.rows.add(TaxRow(rate, t, 0, 0, round2(t * rate / 100)));
    }
  }
  c.totalQty = round2(c.totalQty);
  c.taxable = round2(c.taxable);
  c.tax = round2(c.tax);
  c.cgst = round2(c.rows.fold(0.0, (s, r) => s + r.cgst));
  c.sgst = round2(c.rows.fold(0.0, (s, r) => s + r.sgst));
  c.igst = round2(c.rows.fold(0.0, (s, r) => s + r.igst));
  c.total = round2(c.taxable + c.tax);
  return c;
}
