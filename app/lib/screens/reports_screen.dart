import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/api.dart';
import '../core/companies.dart';
import '../core/format.dart';
import '../core/save_file_io.dart' if (dart.library.js_interop) '../core/save_file_web.dart' as saver;
import '../widgets/common.dart';
import '../widgets/company_selector.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _period = 'month';
  late String _from, _to;
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _setPeriod('month');
  }

  void _setPeriod(String p) {
    final now = DateTime.now();
    final fyStart = now.month >= 4 ? now.year : now.year - 1;
    switch (p) {
      case 'month':
        _from = ymdOf(DateTime(now.year, now.month, 1));
        _to = ymdOf(DateTime(now.year, now.month + 1, 0));
      case 'last':
        _from = ymdOf(DateTime(now.year, now.month - 1, 1));
        _to = ymdOf(DateTime(now.year, now.month, 0));
      case 'fy':
        _from = '$fyStart-04-01';
        _to = '${fyStart + 1}-03-31';
      case 'lastfy':
        _from = '${fyStart - 1}-04-01';
        _to = '$fyStart-03-31';
    }
    _period = p;
    _load();
  }

  Future<void> _custom() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: parseYmd(_from)!, end: parseYmd(_to)!),
    );
    if (r == null) return;
    _from = ymdOf(r.start);
    _to = ymdOf(r.end);
    _period = 'custom';
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Companies.instance.ensure();
      final r = await Api.instance.get('/reports/sales', {'company': Companies.instance.selected, 'from': _from, 'to': _to});
      if (mounted) setState(() => _data = Map<String, dynamic>.from(r));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _companyLabel => Companies.instance.selected == 'all' ? 'All companies' : Companies.instance.nameOf(Companies.instance.selected);

  Future<void> _exportCsv() async {
    final rows = List<Map>.from(_data!['rows']);
    String esc(dynamic v) {
      final s = '${v ?? ''}';
      return s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
    }

    final b = StringBuffer('Date,Invoice No,Company,Customer,GSTIN,Place of Supply,Taxable,CGST,SGST,IGST,Total Tax,Total,Received,Balance,Status\n');
    for (final r in rows) {
      b.writeln([
        dmy(r['invoiceDate']), invNo(r), r['companySnapshot']?['name'], r['billTo']?['name'], r['billTo']?['gstin'], r['placeOfSupply'],
        r['taxableAmount'], r['cgst'], r['sgst'], r['igst'], r['totalTax'], r['total'], r['receivedAmount'], r['balance'], r['status'],
      ].map(esc).join(','));
    }
    final t = _data!['totals'];
    b.writeln(['', '', '', 'TOTAL', '', '', t['taxable'], t['cgst'], t['sgst'], t['igst'], t['tax'], t['total'], t['received'], t['balance'], ''].map(esc).join(','));
    final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(b.toString())]);
    await saver.saveBytes(bytes, 'Sales_Register_${_from}_to_$_to.csv', 'text/csv');
  }

  Future<void> _print() async {
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/roboto-regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/roboto-bold.ttf'));
    final rows = List<Map>.from(_data!['rows']);
    final t = Map<String, dynamic>.from(_data!['totals']);
    final rates = List<Map>.from(_data!['rateSummary']);
    final doc = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold));
    final s = pw.TextStyle(fontSize: 8);
    final h = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      build: (_) => [
        pw.Text('Sales Register — $_companyLabel', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.Text('Period: ${dmy(_from)} to ${dmy(_to)}'),
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(
          headerStyle: h,
          cellStyle: s,
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          cellAlignments: {for (var i = 5; i <= 11; i++) i: pw.Alignment.centerRight},
          headers: ['Date', 'Inv No', 'Customer', 'GSTIN', 'Company', 'Taxable', 'CGST', 'SGST', 'IGST', 'Total', 'Received', 'Balance'],
          data: [
            for (final r in rows)
              [
                dmy(r['invoiceDate']), invNo(r), '${r['billTo']?['name'] ?? ''}', '${r['billTo']?['gstin'] ?? ''}', '${r['companySnapshot']?['name'] ?? ''}',
                money(r['taxableAmount']), money(r['cgst']), money(r['sgst']), money(r['igst']), money(r['total']), money(r['receivedAmount']), money(r['balance']),
              ],
            ['', '', 'TOTAL (${t['count']})', '', '', money(t['taxable']), money(t['cgst']), money(t['sgst']), money(t['igst']), money(t['total']), money(t['received']), money(t['balance'])],
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Text('GST rate-wise summary', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.TableHelper.fromTextArray(
          headerStyle: h,
          cellStyle: s,
          headers: ['GST Rate', 'Taxable', 'CGST', 'SGST', 'IGST'],
          data: [for (final r in rates) [pct(r['rate']), money(r['taxable']), money(r['cgst']), money(r['sgst']), money(r['igst'])]],
        ),
      ],
    ));
    final bytes = await doc.save();
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'Sales_Register_${_from}_to_$_to.pdf');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          if (_data != null) ...[
            IconButton(tooltip: 'Print / PDF', icon: const Icon(Icons.print), onPressed: _print),
            IconButton(tooltip: 'Export Excel (CSV)', icon: const Icon(Icons.table_view), onPressed: _exportCsv),
          ],
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Constrained(
          maxWidth: 1200,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CompanySelector(onChanged: _load),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (final p in const [('month', 'This month'), ('last', 'Last month'), ('fy', 'This FY'), ('lastfy', 'Last FY')])
                ChoiceChip(label: Text(p.$2), selected: _period == p.$1, onSelected: (_) => _setPeriod(p.$1)),
              ChoiceChip(
                avatar: const Icon(Icons.date_range, size: 18),
                label: Text(_period == 'custom' ? '${dmy(_from)} - ${dmy(_to)}' : 'Custom'),
                selected: _period == 'custom',
                onSelected: (_) => _custom(),
              ),
            ]),
            const SizedBox(height: 6),
            Text('${dmy(_from)} to ${dmy(_to)}', style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 12),
            if (_loading && _data == null)
              const Padding(padding: EdgeInsets.all(40), child: LoadingView())
            else if (_error != null && _data == null)
              ErrorView(message: _error!, onRetry: _load)
            else if (_data != null)
              ..._report(),
          ]),
        ),
      ]),
    );
  }

  List<Widget> _report() {
    final t = Map<String, dynamic>.from(_data!['totals']);
    final rates = List<Map>.from(_data!['rateSummary']);
    final rows = List<Map>.from(_data!['rows']);
    final b2b = _data!['b2b'], b2c = _data!['b2c'];
    final w = MediaQuery.sizeOf(context).width;
    final cols = w >= 1100 ? 4 : 2;
    return [
      if (_loading) const LinearProgressIndicator(),
      GridView.count(
        crossAxisCount: cols,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: cols == 4 ? 2.6 : (w < 420 ? 1.55 : 2.2),
        children: [
          StatCard(label: 'Total sales', value: rupeeShort(t['total']), sub: '${t['count']} invoices', icon: Icons.receipt_long, color: Colors.indigo),
          StatCard(label: 'Taxable value', value: rupeeShort(t['taxable']), icon: Icons.summarize_outlined, color: Colors.blue),
          StatCard(label: 'Total GST', value: rupeeShort(t['tax']), sub: 'C ${rupeeShort(t['cgst'])} • S ${rupeeShort(t['sgst'])} • I ${rupeeShort(t['igst'])}', icon: Icons.percent, color: Colors.teal),
          StatCard(label: 'Pending', value: rupeeShort(t['balance']), sub: 'Received ${rupeeShort(t['received'])}', icon: Icons.account_balance_wallet, color: Colors.red),
        ],
      ),
      const SizedBox(height: 12),
      SectionCard(
        title: 'GST rate-wise summary (for GSTR-1 / 3B)',
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 40,
            columns: const [
              DataColumn(label: Text('GST rate')),
              DataColumn(label: Text('Taxable'), numeric: true),
              DataColumn(label: Text('CGST'), numeric: true),
              DataColumn(label: Text('SGST'), numeric: true),
              DataColumn(label: Text('IGST'), numeric: true),
            ],
            rows: [
              for (final r in rates)
                DataRow(cells: [
                  DataCell(Text(pct(r['rate']))),
                  DataCell(Text(money(r['taxable']))),
                  DataCell(Text(money(r['cgst']))),
                  DataCell(Text(money(r['sgst']))),
                  DataCell(Text(money(r['igst']))),
                ]),
              DataRow(cells: [
                const DataCell(Text('TOTAL', style: TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Text(money(t['taxable']), style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Text(money(t['cgst']), style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Text(money(t['sgst']), style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Text(money(t['igst']), style: const TextStyle(fontWeight: FontWeight.w700))),
              ]),
            ],
          ),
        ),
      ),
      SectionCard(
        title: 'B2B / B2C',
        child: Column(children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('B2B (customers with GSTIN)'),
            subtitle: Text('${b2b['count']} invoices'),
            trailing: Text('${money(b2b['taxable'])}  +  GST ${money(b2b['tax'])}'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('B2C (unregistered)'),
            subtitle: Text('${b2c['count']} invoices'),
            trailing: Text('${money(b2c['taxable'])}  +  GST ${money(b2c['tax'])}'),
          ),
        ]),
      ),
      SectionCard(
        title: 'Sales register',
        trailing: TextButton.icon(onPressed: _exportCsv, icon: const Icon(Icons.download), label: const Text('CSV')),
        child: rows.isEmpty
            ? const Padding(padding: EdgeInsets.all(20), child: Text('No invoices in this period', textAlign: TextAlign.center))
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 40,
                  showCheckboxColumn: false,
                  columns: const [
                    DataColumn(label: Text('Date')),
                    DataColumn(label: Text('Inv No')),
                    DataColumn(label: Text('Customer')),
                    DataColumn(label: Text('GSTIN')),
                    DataColumn(label: Text('Taxable'), numeric: true),
                    DataColumn(label: Text('CGST'), numeric: true),
                    DataColumn(label: Text('SGST'), numeric: true),
                    DataColumn(label: Text('IGST'), numeric: true),
                    DataColumn(label: Text('Total'), numeric: true),
                    DataColumn(label: Text('Balance'), numeric: true),
                  ],
                  rows: [
                    for (final r in rows)
                      DataRow(
                        onSelectChanged: (_) => context.push('/invoices/${r['_id']}'),
                        cells: [
                          DataCell(Text(dmy(r['invoiceDate']))),
                          DataCell(Text(invNo(r))),
                          DataCell(ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 220),
                            child: Text('${r['billTo']?['name'] ?? ''}', overflow: TextOverflow.ellipsis),
                          )),
                          DataCell(Text('${r['billTo']?['gstin'] ?? ''}')),
                          DataCell(Text(money(r['taxableAmount']))),
                          DataCell(Text(money(r['cgst']))),
                          DataCell(Text(money(r['sgst']))),
                          DataCell(Text(money(r['igst']))),
                          DataCell(Text(money(r['total']), style: const TextStyle(fontWeight: FontWeight.w600))),
                          DataCell(Text(money(r['balance']), style: TextStyle(color: toD(r['balance']) > 0 ? Colors.red.shade700 : null))),
                        ],
                      ),
                  ],
                ),
              ),
      ),
    ];
  }
}
