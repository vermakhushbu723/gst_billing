import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../core/api.dart';
import '../core/auth.dart';
import '../core/format.dart';
import '../core/invoice_actions.dart';
import '../widgets/common.dart';
import 'invoice_form_screen.dart' show paymentModes;

class InvoiceViewScreen extends StatefulWidget {
  const InvoiceViewScreen({super.key, required this.id});
  final String id;
  @override
  State<InvoiceViewScreen> createState() => _InvoiceViewScreenState();
}

class _InvoiceViewScreenState extends State<InvoiceViewScreen> {
  Map<String, dynamic>? _inv;
  Uint8List? _pdf;
  String? _error;
  String _copy = 'ORIGINAL';
  int _pdfVersion = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final inv = Map<String, dynamic>.from(await Api.instance.get('/invoices/${widget.id}'));
      final pdf = await InvoiceActions.pdf(inv, copy: _copy);
      if (mounted) {
        setState(() {
          _inv = inv;
          _pdf = pdf;
          _pdfVersion++;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _rebuildPdf() async {
    final pdf = await InvoiceActions.pdf(_inv!, copy: _copy);
    if (mounted) {
      setState(() {
        _pdf = pdf;
        _pdfVersion++;
      });
    }
  }

  void _apply(dynamic r) {
    if (r is Map) {
      _inv = Map<String, dynamic>.from(r);
      _rebuildPdf();
    }
  }

  // ---------- actions ----------

  Future<void> _whatsapp() async {
    final inv = _inv!, pdf = _pdf!;
    final phone = TextEditingController(text: '${inv['billTo']?['phone'] ?? ''}');
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Send invoice on WhatsApp', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Send PDF file (choose WhatsApp chat)'),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await InvoiceActions.shareFile(inv, pdf);
              } catch (e) {
                if (mounted) showSnack(context, '$e', error: true);
              }
            },
          ),
          const SizedBox(height: 6),
          Text(
            kIsWeb ? 'Works in mobile browsers. On a computer the PDF is downloaded instead.' : 'Opens the share sheet — pick WhatsApp and the chat.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const Divider(height: 32),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Customer WhatsApp number', prefixIcon: Icon(Icons.phone)),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.link),
            label: const Text('Send PDF link to this number'),
            onPressed: () async {
              Navigator.pop(ctx);
              await runBusy(context, () => InvoiceActions.whatsappLink(context, inv, pdf, phone.text));
            },
          ),
          const SizedBox(height: 6),
          Text('Uploads the PDF and opens WhatsApp with a download link.', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        ]),
      ),
    );
  }

  Future<void> _addPayment() async {
    final inv = _inv!;
    final amount = TextEditingController(text: toD(inv['balance']).toStringAsFixed(2));
    final note = TextEditingController();
    var date = today();
    var mode = 'Cash';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Record payment'),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Balance due: ${rupee(inv['balance'])}'),
              const SizedBox(height: 14),
              TextField(
                controller: amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: const InputDecoration(labelText: 'Amount (₹)'),
              ),
              const SizedBox(height: 12),
              DateField(label: 'Date', value: date, onChanged: (v) => set(() => date = v)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: mode,
                decoration: const InputDecoration(labelText: 'Mode'),
                items: [for (final m in paymentModes) DropdownMenuItem(value: m, child: Text(m))],
                onChanged: (v) => mode = v ?? mode,
              ),
              const SizedBox(height: 12),
              TextField(controller: note, decoration: const InputDecoration(labelText: 'Note / Ref no.')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final r = await runBusy(
      context,
      () => Api.instance.post('/invoices/${widget.id}/payments', {
        'amount': double.tryParse(amount.text) ?? 0,
        'date': date,
        'mode': mode,
        'note': note.text.trim(),
      }),
      success: 'Payment saved',
    );
    _apply(r);
  }

  Future<void> _deletePayment(Map p) async {
    if (!await confirm(context, 'Delete payment?', '${rupee(p['amount'])} on ${dmy(p['date'])} will be removed.', ok: 'Delete', danger: true)) return;
    if (!mounted) return;
    _apply(await runBusy(context, () => Api.instance.delete('/invoices/${widget.id}/payments/${p['_id']}')));
  }

  Future<void> _menu(String v) async {
    final inv = _inv!;
    switch (v) {
      case 'edit':
        await context.push('/invoices/${widget.id}/edit');
        _load();
      case 'duplicate':
        await context.push('/invoices/new?from=${widget.id}');
      case 'cancel':
        if (await confirm(context, 'Cancel invoice?', 'Invoice ${invNo(inv)} will be marked CANCELLED and left out of reports.', ok: 'Cancel invoice', danger: true) &&
            mounted) {
          _apply(await runBusy(context, () => Api.instance.post('/invoices/${widget.id}/cancel'), success: 'Invoice cancelled'));
        }
      case 'restore':
        _apply(await runBusy(context, () => Api.instance.post('/invoices/${widget.id}/restore'), success: 'Invoice restored'));
      case 'delete':
        if (await confirm(context, 'Delete invoice?', 'Invoice ${invNo(inv)} will be deleted permanently.', ok: 'Delete', danger: true) && mounted) {
          final r = await runBusy(context, () => Api.instance.delete('/invoices/${widget.id}'), success: 'Invoice deleted');
          if (r != null && mounted) context.pop(true);
        }
      case 'copytext':
        await Clipboard.setData(ClipboardData(text: InvoiceActions.message(inv)));
        if (mounted) showSnack(context, 'Invoice summary copied');
    }
  }

  @override
  Widget build(BuildContext context) {
    final inv = _inv;
    return Scaffold(
      appBar: AppBar(
        title: Text(inv == null ? 'Invoice' : 'Invoice #${invNo(inv)}'),
        actions: [
          if (inv != null)
            PopupMenuButton<String>(
              onSelected: _menu,
              itemBuilder: (_) => [
                if (inv['status'] != 'cancelled') const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit), title: Text('Edit'))),
                const PopupMenuItem(value: 'duplicate', child: ListTile(leading: Icon(Icons.copy), title: Text('Duplicate as new'))),
                const PopupMenuItem(value: 'copytext', child: ListTile(leading: Icon(Icons.text_snippet_outlined), title: Text('Copy summary text'))),
                if (inv['status'] != 'cancelled')
                  const PopupMenuItem(value: 'cancel', child: ListTile(leading: Icon(Icons.block), title: Text('Cancel invoice')))
                else
                  const PopupMenuItem(value: 'restore', child: ListTile(leading: Icon(Icons.restore), title: Text('Restore invoice'))),
                if (AuthState.instance.isAdmin)
                  const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline, color: Colors.red), title: Text('Delete'))),
              ],
            ),
        ],
      ),
      body: _error != null && inv == null
          ? ErrorView(message: _error!, onRetry: _load)
          : inv == null || _pdf == null
              ? const LoadingView()
              : LayoutBuilder(builder: (context, c) {
                  if (c.maxWidth >= 1000) {
                    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: _preview()),
                      const VerticalDivider(width: 1),
                      SizedBox(width: 380, child: ListView(padding: const EdgeInsets.all(16), children: _details())),
                    ]);
                  }
                  return DefaultTabController(
                    length: 2,
                    child: Column(children: [
                      Material(
                        color: Colors.white,
                        child: Column(children: [
                          Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 4), child: _actionBar()),
                          const TabBar(tabs: [Tab(text: 'PDF Preview'), Tab(text: 'Details & Payments')]),
                        ]),
                      ),
                      Expanded(
                        child: TabBarView(children: [
                          _preview(),
                          ListView(padding: const EdgeInsets.all(16), children: _details(withActions: false)),
                        ]),
                      ),
                    ]),
                  );
                }),
    );
  }

  Widget _preview() => PdfPreview(
        key: ValueKey(_pdfVersion),
        build: (_) async => _pdf!,
        useActions: false,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        maxPageWidth: 760,
        pdfFileName: invoiceFileName(_inv!),
        scrollViewDecoration: const BoxDecoration(color: Color(0xFFE9ECF2)),
      );

  Widget _actionBar() {
    Widget btn(IconData icon, String label, VoidCallback onTap, {Color? color}) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilledButton.tonalIcon(
            style: color == null ? null : FilledButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
            onPressed: onTap,
            icon: Icon(icon, size: 18),
            label: Text(label),
          ),
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        btn(Icons.print, 'Print', () => InvoiceActions.printPdf(_inv!, _pdf!)),
        btn(Icons.chat, 'WhatsApp', _whatsapp, color: const Color(0xFF25D366)),
        btn(kIsWeb ? Icons.download : Icons.share, kIsWeb ? 'Download' : 'Share PDF', () => InvoiceActions.download(_inv!, _pdf!)),
        if (_inv!['status'] != 'cancelled' && toD(_inv!['balance']) > 0) btn(Icons.payments_outlined, 'Payment', _addPayment),
        DropdownButton<String>(
          value: _copy,
          underline: const SizedBox(),
          items: const [
            DropdownMenuItem(value: 'ORIGINAL', child: Text('Original')),
            DropdownMenuItem(value: 'DUPLICATE', child: Text('Duplicate')),
            DropdownMenuItem(value: 'TRIPLICATE', child: Text('Triplicate')),
          ],
          onChanged: (v) {
            setState(() => _copy = v ?? _copy);
            _rebuildPdf();
          },
        ),
      ]),
    );
  }

  List<Widget> _details({bool withActions = true}) {
    final inv = _inv!;
    final payments = List<Map>.from(inv['payments'] ?? []);
    Widget row(String l, String v, {bool strong = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(l, style: TextStyle(color: Colors.grey.shade700))),
            Text(v, style: TextStyle(fontWeight: strong ? FontWeight.w800 : FontWeight.w600, color: color)),
          ]),
        );
    return [
      if (withActions) ...[_actionBar(), const SizedBox(height: 12)],
      SectionCard(
        title: '${inv['billTo']?['name'] ?? ''}',
        trailing: StatusChip(inv['status']),
        child: Column(children: [
          row('Company', '${inv['companySnapshot']?['name'] ?? ''}'),
          row('Invoice date', dmy(inv['invoiceDate'])),
          if ('${inv['dueDate'] ?? ''}'.isNotEmpty) row('Due date', dmy(inv['dueDate'])),
          row('Place of supply', '${inv['placeOfSupply'] ?? ''}'),
          const Divider(),
          row('Taxable amount', rupee(inv['taxableAmount'])),
          if (toD(inv['igst']) > 0) row('IGST', rupee(inv['igst'])) else ...[
            row('CGST', rupee(inv['cgst'])),
            row('SGST', rupee(inv['sgst'])),
          ],
          row('Total', rupee(inv['total']), strong: true),
          row('Received', rupee(inv['receivedAmount']), color: Colors.green.shade700),
          row('Balance', rupee(inv['balance']), strong: true, color: toD(inv['balance']) > 0 ? Colors.red.shade700 : null),
        ]),
      ),
      SectionCard(
        title: 'Payments',
        trailing: inv['status'] != 'cancelled' && toD(inv['balance']) > 0
            ? TextButton.icon(onPressed: _addPayment, icon: const Icon(Icons.add), label: const Text('Add'))
            : null,
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        child: payments.isEmpty
            ? Padding(padding: const EdgeInsets.all(8), child: Text('No payment received yet', style: TextStyle(color: Colors.grey.shade600)))
            : Column(children: [
                for (final p in payments)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.payments_outlined, color: Colors.green),
                    title: Text(rupee(p['amount']), style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text([dmy(p['date']), p['mode'], p['note']].where((e) => '${e ?? ''}'.isNotEmpty).join(' • ')),
                    trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _deletePayment(p)),
                  ),
              ]),
      ),
      if ('${inv['customer'] ?? ''}'.isNotEmpty)
        OutlinedButton.icon(
          onPressed: () => context.push('/customers/${inv['customer']}'),
          icon: const Icon(Icons.person_outline),
          label: const Text('Open customer ledger'),
        ),
    ];
  }
}
