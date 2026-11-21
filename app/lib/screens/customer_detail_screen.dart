import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../widgets/common.dart';
import '../widgets/payment_dialog.dart';
import '../core/brand.dart';

class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({super.key, required this.id});
  final String id;
  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await Api.instance.get('/customers/${widget.id}/statement');
      if (mounted) setState(() => _data = Map<String, dynamic>.from(r));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _open(String path) async {
    await context.push(path);
    _load();
  }

  Future<void> _delete() async {
    final c = _data!['customer'];
    if (!await confirm(context, 'Delete customer?', '${c['name']} will be removed. Customers with invoices are only hidden.', ok: 'Delete', danger: true)) return;
    if (!mounted) return;
    final r = await runBusy(context, () => Api.instance.delete('/customers/${widget.id}'), success: 'Customer removed');
    if (r != null && mounted) context.pop(true);
  }

  Future<void> _reminder() async {
    final c = _data!['customer'];
    final t = _data!['totals'];
    final text = 'Dear ${c['name']},\n\nThis is a reminder that ${rupee(t['balance'])} is pending against your invoices. '
        'Kindly arrange the payment at the earliest.\n\nThank you.';
    final p = waPhone('${c['phone'] ?? ''}');
    await launchUrl(Uri.parse('https://wa.me/$p?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication);
  }

  Future<void> _printStatement() async {
    final d = _data!;
    final c = Map<String, dynamic>.from(d['customer']);
    final t = Map<String, dynamic>.from(d['totals']);
    final ledger = List<Map>.from(d['ledger'] ?? []);
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/roboto-regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/roboto-bold.ttf'));
    final doc = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold));
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (_) => [
        pw.Text('STATEMENT OF ACCOUNT', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.Text('${c['name']}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        if ('${c['billingAddress'] ?? ''}'.isNotEmpty) pw.Text('${c['billingAddress']}', style: const pw.TextStyle(fontSize: 9)),
        if ('${c['gstin'] ?? ''}'.isNotEmpty) pw.Text('GSTIN: ${c['gstin']}', style: const pw.TextStyle(fontSize: 9)),
        pw.Text('Date: ${dmy(today())}', style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          cellAlignments: {3: pw.Alignment.centerRight, 4: pw.Alignment.centerRight, 5: pw.Alignment.centerRight},
          headers: ['Date', 'Particulars', 'Ref', 'Debit', 'Credit', 'Balance'],
          data: [
            for (final e in ledger)
              [dmy(e['date']), '${e['type']}', '${e['ref'] ?? ''}', toD(e['debit']) > 0 ? money(e['debit']) : '', toD(e['credit']) > 0 ? money(e['credit']) : '', money(e['balance'])],
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Balance due: ${rupee(t['balance'])}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        ),
      ],
    ));
    final bytes = await doc.save();
    final name = '${c['name']}'.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: '${name}_Statement.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      appBar: AppBar(
        title: Text(d == null ? 'Customer' : '${d['customer']['name']}'),
        actions: [
          if (d != null) ...[
            IconButton(tooltip: 'Print statement', icon: const Icon(Icons.print), onPressed: _printStatement),
            IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit), onPressed: () => _open('/customers/${widget.id}/edit')),
            IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: _delete),
          ],
        ],
      ),
      floatingActionButton: d == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _open('/invoices/new?customer=${widget.id}'),
              icon: const Icon(Icons.add),
              label: const Text('New Invoice'),
            ),
      body: _error != null && d == null
          ? ErrorView(message: _error!, onRetry: _load)
          : d == null
              ? const LoadingView()
              : RefreshIndicator(onRefresh: _load, child: _body(d)),
    );
  }

  Widget _body(Map<String, dynamic> d) {
    final c = Map<String, dynamic>.from(d['customer']);
    final t = Map<String, dynamic>.from(d['totals']);
    final invoices = List<Map>.from(d['invoices']);
    final ledger = List<Map>.from(d['ledger'] ?? []);
    final cols = MediaQuery.sizeOf(context).width >= 900 ? 3 : 1;
    Widget info(IconData icon, String v) => v.isEmpty
        ? const SizedBox()
        : Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 18, color: Colors.grey.shade600),
              const SizedBox(width: 10),
              Expanded(child: Text(v)),
            ]),
          );
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
      Constrained(
        maxWidth: 1000,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionCard(
            title: 'Details',
            child: Column(children: [
              info(Icons.phone, '${c['phone'] ?? ''}'),
              info(Icons.email_outlined, '${c['email'] ?? ''}'),
              info(Icons.verified_outlined, '${c['gstin'] ?? ''}'.isEmpty ? 'Unregistered (no GSTIN)' : 'GSTIN: ${c['gstin']}   PAN: ${c['pan']}'),
              info(Icons.location_on_outlined, '${c['billingAddress'] ?? ''}'),
              info(Icons.map_outlined, 'State: ${c['state'] ?? ''}'),
              if ('${c['phone'] ?? ''}'.isNotEmpty && toD(t['balance']) > 0)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _reminder,
                    icon: const Icon(Icons.chat, color: Color(0xFF25D366)),
                    label: const Text('Send payment reminder on WhatsApp'),
                  ),
                ),
            ]),
          ),
          GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: cols == 3 ? 2.8 : 4.2,
            children: [
              StatCard(label: 'Total sales', value: rupee(t['sales']), sub: '${t['count']} invoices', icon: Icons.receipt_long, color: Brand.navy),
              StatCard(label: 'Received', value: rupee(t['received']), icon: Icons.payments_outlined, color: Colors.green),
              StatCard(label: 'Balance to receive', value: rupee(t['balance']), sub: toD(t['credit']) > 0 ? 'after credit notes ${rupee(t['credit'])}' : null, icon: Icons.account_balance_wallet, color: Colors.red),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (toD(t['balance']) > 0)
              FilledButton.icon(
                onPressed: () async {
                  if (await receivePayment(context, customer: {...c, 'balance': t['balance']})) _load();
                },
                icon: const Icon(Icons.add_card),
                label: const Text('Receive Payment'),
              ),
            OutlinedButton.icon(onPressed: () => _open('/invoices/new?customer=${widget.id}&type=quotation'), icon: const Icon(Icons.request_quote_outlined), label: const Text('Quotation')),
            OutlinedButton.icon(onPressed: () => _open('/invoices/new?customer=${widget.id}&type=challan'), icon: const Icon(Icons.local_shipping_outlined), label: const Text('Challan')),
            OutlinedButton.icon(onPressed: () => _open('/invoices/new?customer=${widget.id}&type=credit_note'), icon: const Icon(Icons.assignment_return_outlined), label: const Text('Credit Note')),
          ]),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Documents',
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
            child: invoices.isEmpty
                ? const Padding(padding: EdgeInsets.all(24), child: Text('No invoices yet', textAlign: TextAlign.center))
                : Column(children: [
                    for (final inv in invoices)
                      InvoiceTile(inv: inv, byInvoiceNo: true, onTap: () => _open('/invoices/${inv['_id']}')),
                  ]),
          ),
          if (ledger.isNotEmpty)
            SectionCard(
              title: 'Ledger',
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 38,
                  columns: const [
                    DataColumn(label: Text('Date')),
                    DataColumn(label: Text('Particulars')),
                    DataColumn(label: Text('Ref')),
                    DataColumn(label: Text('Debit'), numeric: true),
                    DataColumn(label: Text('Credit'), numeric: true),
                    DataColumn(label: Text('Balance'), numeric: true),
                  ],
                  rows: [
                    for (final e in ledger)
                      DataRow(cells: [
                        DataCell(Text(dmy(e['date']))),
                        DataCell(Text('${e['type']}')),
                        DataCell(Text('${e['ref'] ?? ''}')),
                        DataCell(Text(toD(e['debit']) > 0 ? money(e['debit']) : '')),
                        DataCell(Text(toD(e['credit']) > 0 ? money(e['credit']) : '', style: TextStyle(color: Colors.green.shade700))),
                        DataCell(Text(money(e['balance']), style: const TextStyle(fontWeight: FontWeight.w600))),
                      ]),
                  ],
                ),
              ),
            ),
        ]),
      ),
    ]);
  }
}
