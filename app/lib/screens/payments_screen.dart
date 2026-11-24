import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/api.dart';
import '../core/brand.dart';
import '../core/companies.dart';
import '../core/format.dart';
import '../widgets/common.dart';
import '../widgets/company_selector.dart';
import '../widgets/payment_dialog.dart';
import '../widgets/period_filter.dart';
import '../widgets/top_actions.dart';
import '../core/tax_mode.dart';

/// Payment-In: all money received from customers.
class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});
  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  Period _period = Period.preset('month');
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    TaxMode.instance.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    TaxMode.instance.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      await Companies.instance.ensure();
      final r = await Api.instance.get('/payments', {'company': Companies.instance.selected, 'from': _period.from, 'to': _period.to, 'gst': TaxMode.instance.param});
      if (mounted) setState(() => _data = Map<String, dynamic>.from(r));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _receive() async {
    if (await receivePayment(context)) _load();
  }

  Future<void> _delete(Map p) async {
    if (!await confirm(context, 'Delete payment?', '${rupee(p['amount'])} from ${p['customerName']} (invoice #${invNo(p)}) will be removed.', ok: 'Delete', danger: true)) return;
    if (!mounted) return;
    await runBusy(context, () => Api.instance.delete('/invoices/${p['invoice']}/payments/${p['_id']}'), success: 'Payment deleted');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = List<Map>.from(_data?['items'] ?? []);
    final byMode = Map<String, dynamic>.from(_data?['byMode'] ?? {});
    return Scaffold(
      appBar: AppBar(title: Text('Payments Received — ${TaxMode.instance.label}'), actions: topActions()),
      floatingActionButton: FloatingActionButton.extended(onPressed: _receive, icon: const Icon(Icons.add_card), label: const Text('Receive Payment')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
          Constrained(
            maxWidth: 1000,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              CompanySelector(onChanged: _load),
              const SizedBox(height: 10),
              PeriodFilter(value: _period, onChanged: (p) {
                setState(() => _period = p);
                _load();
              }),
              const SizedBox(height: 12),
              if (_error != null && _data == null)
                ErrorView(message: _error!, onRetry: _load)
              else if (_data == null)
                const Padding(padding: EdgeInsets.all(40), child: LoadingView())
              else ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(spacing: 24, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Total received', style: TextStyle(color: Colors.grey.shade700)),
                        Text(rupee(_data!['total']), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Brand.teal)),
                      ]),
                      for (final e in byMode.entries)
                        Chip(
                          avatar: const Icon(Icons.payments_outlined, size: 16),
                          label: Text('${e.key}: ${rupee(e.value)}'),
                          backgroundColor: Brand.goldLight,
                        ),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                if (items.isEmpty)
                  const EmptyView(icon: Icons.payments_outlined, text: 'No payments in this period')
                else
                  Card(
                    child: Column(children: [
                      for (final p in items) ...[
                        ListTile(
                          leading: const CircleAvatar(backgroundColor: Brand.tealLight, child: Icon(Icons.south_west, color: Brand.teal, size: 20)),
                          title: Text('${p['customerName'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            [dmy(p['date']), p['mode'], 'Inv #${invNo(p)}', p['note']].where((e) => '${e ?? ''}'.isNotEmpty).join(' • '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => context.push('/invoices/${p['invoice']}'),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(rupee(p['amount']), style: TextStyle(fontWeight: FontWeight.w700, color: Colors.green.shade700)),
                            IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(p)),
                          ]),
                        ),
                        const Divider(height: 1, indent: 72),
                      ],
                    ]),
                  ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
