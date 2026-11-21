import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../widgets/common.dart';

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

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      appBar: AppBar(
        title: Text(d == null ? 'Customer' : '${d['customer']['name']}'),
        actions: [
          if (d != null) ...[
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
              StatCard(label: 'Total sales', value: rupee(t['sales']), sub: '${t['count']} invoices', icon: Icons.receipt_long, color: Colors.indigo),
              StatCard(label: 'Received', value: rupee(t['received']), icon: Icons.payments_outlined, color: Colors.green),
              StatCard(label: 'Balance to receive', value: rupee(t['balance']), icon: Icons.account_balance_wallet, color: Colors.red),
            ],
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Invoices',
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
            child: invoices.isEmpty
                ? const Padding(padding: EdgeInsets.all(24), child: Text('No invoices yet', textAlign: TextAlign.center))
                : Column(children: [
                    for (final inv in invoices)
                      InvoiceTile(inv: inv, byInvoiceNo: true, onTap: () => _open('/invoices/${inv['_id']}')),
                  ]),
          ),
        ]),
      ),
    ]);
  }
}
