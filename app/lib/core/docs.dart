import 'package:flutter/material.dart';

/// Sales document types. They share one form, one view and one PDF layout,
/// and each exists in two flows: with GST and without GST.
enum DocType {
  invoice('invoice', '/invoices', Icons.receipt_long),
  quotation('quotation', '/quotations', Icons.request_quote_outlined),
  creditNote('credit_note', '/credit-notes', Icons.assignment_return_outlined),
  challan('challan', '/challans', Icons.local_shipping_outlined);

  const DocType(this.key, this.listPath, this.icon);
  final String key, listPath;
  final IconData icon;

  bool get isInvoice => this == DocType.invoice;
  bool get canConvert => this == DocType.quotation || this == DocType.challan;

  static const _gst = {
    DocType.invoice: ('Invoice', 'Invoices', 'TAX INVOICE', 'Invoice No.:', 'Sales_Invoice'),
    DocType.quotation: ('Quotation', 'Quotations', 'QUOTATION', 'Quotation No.:', 'Quotation'),
    DocType.creditNote: ('Credit Note', 'Credit Notes', 'CREDIT NOTE', 'Credit Note No.:', 'Credit_Note'),
    DocType.challan: ('Delivery Challan', 'Delivery Challans', 'DELIVERY CHALLAN', 'Challan No.:', 'Delivery_Challan'),
  };
  static const _plain = {
    DocType.invoice: ('Bill', 'Bills', 'BILL', 'Bill No.:', 'Bill'),
    DocType.quotation: ('Estimate', 'Estimates', 'ESTIMATE', 'Estimate No.:', 'Estimate'),
    DocType.creditNote: ('Sales Return', 'Sales Returns', 'SALES RETURN', 'Return No.:', 'Sales_Return'),
    DocType.challan: ('Delivery Challan', 'Delivery Challans', 'DELIVERY CHALLAN', 'Challan No.:', 'Delivery_Challan'),
  };

  (String, String, String, String, String) _names(bool gst) => (gst ? _gst : _plain)[this]!;

  String labelFor(bool gst) => _names(gst).$1;
  String pluralFor(bool gst) => _names(gst).$2;
  String pdfTitleFor(bool gst) => _names(gst).$3;
  String noLabelFor(bool gst) => _names(gst).$4;
  String fileWordFor(bool gst) => _names(gst).$5;

  // GST names (kept for places that do not depend on the flow)
  String get label => labelFor(true);
  String get plural => pluralFor(true);

  String get dateLabel => isInvoice ? 'Invoice Date:' : 'Date:';
  String dateLabelFor(bool gst) => isInvoice ? (gst ? 'Invoice Date:' : 'Bill Date:') : 'Date:';

  /// Second date on the document (due date / valid till), or null if none.
  String? get secondDateLabel => switch (this) {
        DocType.invoice => 'Due Date:',
        DocType.quotation => 'Valid Till:',
        _ => null,
      };

  static DocType of(dynamic key) => DocType.values.firstWhere((d) => d.key == '$key', orElse: () => DocType.invoice);
}

/// A document is "with GST" unless it says otherwise (older documents have no flag).
bool isGstDoc(Map? doc) => doc?['gst'] != false;
