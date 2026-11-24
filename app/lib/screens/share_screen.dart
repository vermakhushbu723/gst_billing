import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../core/api.dart';
import '../core/brand.dart';
import '../core/docs.dart';
import '../core/format.dart';
import '../core/save_file_io.dart' if (dart.library.js_interop) '../core/save_file_web.dart' as saver;
import '../pdf/invoice_pdf.dart';
import '../widgets/common.dart';

/// Public page for an invoice link (used in reports and messages). No login needed.
class ShareScreen extends StatefulWidget {
  const ShareScreen({super.key, required this.token});
  final String token;
  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> {
  Map<String, dynamic>? _inv;
  Uint8List? _pdf;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = Map<String, dynamic>.from(await Api.instance.get('/public/invoice/${widget.token}'));
      final inv = Map<String, dynamic>.from(r['invoice']);
      final pdf = await InvoicePdf.build(inv, Map<String, dynamic>.from(r['company'] ?? {}));
      if (mounted) {
        setState(() {
          _inv = inv;
          _pdf = pdf;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final inv = _inv;
    final type = DocType.of(inv?['docType']);
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const BrandLogo(height: 28),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              inv == null ? 'Invoice' : '${type.labelFor(isGstDoc(inv))} #${invNo(inv)} — ${inv['companySnapshot']?['name'] ?? ''}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
        actions: [
          if (_pdf != null) ...[
            IconButton(
              tooltip: 'Print',
              icon: const Icon(Icons.print),
              onPressed: () => Printing.layoutPdf(onLayout: (_) async => _pdf!, name: invoiceFileName(inv!)),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: () => saver.saveBytes(_pdf!, invoiceFileName(inv!), 'application/pdf'),
                icon: const Icon(Icons.download),
                label: const Text('Download PDF'),
              ),
            ),
          ],
        ],
      ),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : _pdf == null
              ? const LoadingView()
              : Column(children: [
                  Container(
                    width: double.infinity,
                    color: Brand.goldLight,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Wrap(spacing: 20, runSpacing: 4, children: [
                      Text('${inv!['billTo']?['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.navy)),
                      Text('Date: ${dmy(inv['invoiceDate'])}'),
                      Text('Amount: ${rupee(inv['total'])}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (type.isInvoice) Text('Balance: ${rupee(inv['balance'])}', style: TextStyle(color: toD(inv['balance']) > 0 ? Colors.red.shade700 : Colors.green.shade700)),
                    ]),
                  ),
                  Expanded(
                    child: PdfPreview(
                      build: (_) async => _pdf!,
                      useActions: false,
                      canChangePageFormat: false,
                      canChangeOrientation: false,
                      canDebug: false,
                      maxPageWidth: 760,
                      scrollViewDecoration: const BoxDecoration(color: Brand.tealLight),
                    ),
                  ),
                ]),
    );
  }
}
