import 'package:flutter/material.dart';

/// Sales document types. They share one form, one view and one PDF layout.
enum DocType {
  invoice('invoice', 'Invoice', 'Invoices', 'TAX INVOICE', 'Invoice No.:', 'Invoice Date:', 'Sales_Invoice', '/invoices', Icons.receipt_long),
  quotation('quotation', 'Quotation', 'Quotations', 'QUOTATION', 'Quotation No.:', 'Date:', 'Quotation', '/quotations', Icons.request_quote_outlined),
  creditNote('credit_note', 'Credit Note', 'Credit Notes', 'CREDIT NOTE', 'Credit Note No.:', 'Date:', 'Credit_Note', '/credit-notes', Icons.assignment_return_outlined),
  challan('challan', 'Delivery Challan', 'Delivery Challans', 'DELIVERY CHALLAN', 'Challan No.:', 'Date:', 'Delivery_Challan', '/challans', Icons.local_shipping_outlined);

  const DocType(this.key, this.label, this.plural, this.pdfTitle, this.noLabel, this.dateLabel, this.fileWord, this.listPath, this.icon);
  final String key, label, plural, pdfTitle, noLabel, dateLabel, fileWord, listPath;
  final IconData icon;

  bool get isInvoice => this == DocType.invoice;
  bool get canConvert => this == DocType.quotation || this == DocType.challan;

  /// Second date on the document (due date / valid till), or null if none.
  String? get secondDateLabel => switch (this) {
        DocType.invoice => 'Due Date:',
        DocType.quotation => 'Valid Till:',
        _ => null,
      };

  static DocType of(dynamic key) => DocType.values.firstWhere((d) => d.key == '$key', orElse: () => DocType.invoice);
}
