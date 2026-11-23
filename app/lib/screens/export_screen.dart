import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/brand.dart';
import '../core/companies.dart';
import '../core/export.dart';
import '../core/format.dart';
import '../core/save_file_io.dart' if (dart.library.js_interop) '../core/save_file_web.dart' as saver;
import '../widgets/common.dart';
import '../widgets/company_selector.dart';
import '../widgets/period_filter.dart';
import '../widgets/top_actions.dart';

/// Download any data as Excel, CSV or PDF.
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key, this.initialType});
  final String? initialType;
  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  late String _type = widget.initialType ?? 'sales';
  Period _period = Period.preset('month');
  bool _allDates = false;
  bool _busy = false;
  ExportReport? _preview;
  String? _error;

  static const _icons = <String, IconData>{
    'sales': Icons.receipt_long_outlined,
    'quotations': Icons.request_quote_outlined,
    'challans': Icons.local_shipping_outlined,
    'credit_notes': Icons.assignment_return_outlined,
    'payments': Icons.payments_outlined,
    'expenses': Icons.account_balance_wallet_outlined,
    'customers': Icons.people_outline,
    'products': Icons.inventory_2_outlined,
    'customer_sales': Icons.person_search_outlined,
    'item_sales': Icons.category_outlined,
    'gst': Icons.percent,
    'all': Icons.all_inbox_outlined,
  };

  @override
  void initState() {
    super.initState();
    Companies.instance.ensure().then((_) => _loadPreview());
  }

  String get _from => _allDates ? '' : _period.from;
  String get _to => _allDates ? '' : _period.to;

  Future<void> _loadPreview() async {
    if (_type == 'all') {
      setState(() => _preview = null);
      return;
    }
    setState(() => _error = null);
    try {
      final r = await Exporter.fetch(_type, company: Companies.instance.selected, from: _from, to: _to);
      if (mounted) setState(() => _preview = r);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  String _fileBase(ExportReport r) {
    final who = r.companyName.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), '').toLowerCase();
    final what = _type == 'all' ? 'all_data' : (_type == 'sales' ? 'invoice_report' : '${_type}_report');
    final when = _allDates ? '' : '_${_from}_to_$_to';
    return '${who}_$what$when';
  }

  Future<void> _download(String format) async {
    setState(() => _busy = true);
    try {
      final company = Companies.instance.selected;
      final types = _type == 'all' ? [for (final t in exportTypes) t.$1] : [_type];
      final reports = <ExportReport>[];
      for (final t in types) {
        reports.add(await Exporter.fetch(t, company: company, from: _from, to: _to));
      }
      late Uint8List bytes;
      late String mime, ext;
      switch (format) {
        case 'xlsx':
          bytes = Exporter.xlsx(reports);
          mime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
          ext = 'xlsx';
        case 'csv':
          bytes = Exporter.csv(reports);
          mime = 'text/csv';
          ext = 'csv';
        default:
          bytes = await Exporter.pdf(reports);
          mime = 'application/pdf';
          ext = 'pdf';
      }
      await saver.saveBytes(bytes, '${_fileBase(reports.first)}.$ext', mime);
      if (mounted) showSnack(context, 'Downloaded ${reports.length > 1 ? '${reports.length} reports' : reports.first.title}');
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final options = [...exportTypes, ('all', 'All data (every report)')];
    final picker = SectionCard(
      title: '1. Choose data',
      child: Column(children: [
        for (final o in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Material(
              color: _type == o.$1 ? Brand.goldLight : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  setState(() => _type = o.$1);
                  _loadPreview();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    Icon(_icons[o.$1], size: 20, color: _type == o.$1 ? Brand.teal : Brand.slate),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(o.$2, style: TextStyle(fontWeight: _type == o.$1 ? FontWeight.w700 : FontWeight.w500, color: Brand.navy)),
                    ),
                    if (o.$1 == 'sales')
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Brand.tealLight, borderRadius: BorderRadius.circular(6)),
                        child: const Text('CSV format', style: TextStyle(fontSize: 10, color: Brand.teal, fontWeight: FontWeight.w700)),
                      ),
                    if (_type == o.$1) const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.check_circle, color: Brand.teal, size: 20)),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );

    final filters = SectionCard(
      title: '2. Company & dates',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CompanySelector(onChanged: _loadPreview),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _allDates,
          title: const Text('All dates (complete data)'),
          onChanged: (v) {
            setState(() => _allDates = v);
            _loadPreview();
          },
        ),
        if (!_allDates)
          PeriodFilter(value: _period, onChanged: (p) {
            setState(() => _period = p);
            _loadPreview();
          }),
      ]),
    );

    Widget fmtButton(String f, IconData icon, String label, String sub, Color color) => Expanded(
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _busy ? null : () => _download(f),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                child: Column(children: [
                  Icon(icon, color: color, size: 32),
                  const SizedBox(height: 6),
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w800, color: Brand.navy)),
                  Text(sub, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ]),
              ),
            ),
          ),
        );

    final download = SectionCard(
      title: '3. Download',
      child: Column(children: [
        Row(children: [
          fmtButton('xlsx', Icons.grid_on, 'Excel', '.xlsx', const Color(0xFF1D6F42)),
          fmtButton('csv', Icons.description_outlined, 'CSV', 'opens in Excel', Brand.teal),
          fmtButton('pdf', Icons.picture_as_pdf_outlined, 'PDF', 'print / share', Colors.red.shade700),
        ]),
        if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
      ]),
    );

    final preview = SectionCard(
      title: _type == 'all' ? 'All data' : 'Preview',
      child: _type == 'all'
          ? Text('Excel: one sheet per report. CSV and PDF: all reports one after another.\n\nReports: ${exportTypes.map((t) => t.$2).join(', ')}.',
              style: TextStyle(color: Colors.grey.shade700))
          : _error != null
              ? Text(_error!, style: TextStyle(color: Colors.red.shade700))
              : _preview == null
                  ? const Padding(padding: EdgeInsets.all(20), child: LoadingView())
                  : _previewTable(_preview!),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Export / Download'), actions: topActions()),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Constrained(
          maxWidth: 1200,
          child: wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 360, child: picker),
                  const SizedBox(width: 12),
                  Expanded(child: Column(children: [filters, download, preview])),
                ])
              : Column(children: [picker, filters, download, preview]),
        ),
      ]),
    );
  }

  Widget _previewTable(ExportReport r) {
    final shown = r.rows.take(8).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 16, runSpacing: 6, children: [
        Text(r.companyName, style: const TextStyle(fontWeight: FontWeight.w700)),
        Text('Dated: ${r.dated}', style: TextStyle(color: Colors.grey.shade700)),
        Text('${r.totalLabel}: ${r.type == 'products' ? r.total : rupee(r.total)}', style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.teal)),
        Text('${r.rows.length} rows', style: TextStyle(color: Colors.grey.shade700)),
      ]),
      const SizedBox(height: 10),
      if (r.rows.isEmpty)
        Text('No records for this selection.', style: TextStyle(color: Colors.grey.shade600))
      else
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 36,
            dataRowMinHeight: 34,
            dataRowMaxHeight: 40,
            columns: [for (final c in r.columns) DataColumn(label: Text(c.label), numeric: c.number)],
            rows: [
              for (final row in shown)
                DataRow(cells: [
                  for (final v in row)
                    DataCell(ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 260),
                      child: Text(v is num ? money(v) : '${v ?? ''}', overflow: TextOverflow.ellipsis),
                    )),
                ]),
            ],
          ),
        ),
      if (r.rows.length > shown.length)
        Padding(padding: const EdgeInsets.only(top: 8), child: Text('…and ${r.rows.length - shown.length} more rows in the download', style: TextStyle(color: Colors.grey.shade600))),
    ]);
  }
}
