import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/api.dart';
import '../core/auth.dart';
import '../core/companies.dart';
import '../core/format.dart';
import '../widgets/common.dart';
import '../widgets/company_selector.dart';
import '../widgets/payment_dialog.dart';
import '../core/brand.dart';
import '../widgets/top_actions.dart';
import '../core/tax_mode.dart';
import '../core/docs.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
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
      final r = await Api.instance.get('/reports/dashboard', {'company': Companies.instance.selected, 'gst': TaxMode.instance.param});
      if (mounted) setState(() => _data = Map<String, dynamic>.from(r));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _open(String path) async {
    await context.push(path);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final name = '${AuthState.instance.user?['name'] ?? ''}';
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          if (MediaQuery.sizeOf(context).width < 900) ...[const BrandLogo(height: 30), const SizedBox(width: 10)],
          Flexible(child: Text('Hello, $name', overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: MediaQuery.sizeOf(context).width < 600
                ? IconButton(tooltip: 'Export / Download', onPressed: () => context.go('/export'), icon: const Icon(Icons.download_outlined))
                : OutlinedButton.icon(
                    onPressed: () => context.go('/export'),
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Export / Download'),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                  ),
          ),if (MediaQuery.sizeOf(context).width >= 600) IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
          ...topActions(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open('/invoices/new?gst=${TaxMode.instance.gst ? 1 : 0}'),
        icon: const Icon(Icons.add),
        label: Text('New ${DocType.invoice.labelFor(TaxMode.instance.gst)}'),
      ),
      body: _error != null && _data == null
          ? ErrorView(message: _error!, onRetry: _load)
          : _data == null
              ? const LoadingView()
              : RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    final d = _data!;
    final w = MediaQuery.sizeOf(context).width;
    final cols = w >= 1100 ? 4 : 2;
    final months = List<Map>.from(d['months'] ?? []);
    final recent = List<Map>.from(d['recent'] ?? []);
    final topDue = List<Map>.from(d['topDue'] ?? []);
    final stats = [
      StatCard(label: "Today's Sales", value: rupeeShort(d['today']['total']), sub: '${d['today']['count']} invoices', icon: Icons.today, color: Brand.teal),
      StatCard(label: 'This Month', value: rupeeShort(d['month']['total']), sub: '${d['month']['count']} invoices', icon: Icons.calendar_month, color: Brand.navy),
      StatCard(label: 'Outstanding', value: rupeeShort(d['outstanding']), sub: 'to be received', icon: Icons.account_balance_wallet, color: Colors.red),
      TaxMode.instance.gst
          ? StatCard(label: 'GST This Month', value: rupeeShort(d['month']['tax']), sub: 'CGST + SGST + IGST', icon: Icons.percent, color: Brand.gold)
          : StatCard(label: 'Bills (all time)', value: '${d['allTime']?['count'] ?? 0}', sub: 'without GST', icon: Icons.receipt_outlined, color: Brand.gold),
      StatCard(label: 'Received This Month', value: rupeeShort(d['receivedMonth']), sub: 'payments in', icon: Icons.south_west, color: Colors.green.shade700),
      StatCard(label: 'Expenses This Month', value: rupeeShort(d['monthExpense']), sub: 'kharcha', icon: Icons.north_east, color: Colors.deepOrange),
      StatCard(
        label: 'Profit This Month',
        value: rupeeShort(toD(d['month']['total']) - toD(d['month']['tax']) - toD(d['monthExpense'])),
        sub: 'sales (without GST) − expenses',
        icon: Icons.trending_up,
        color: Brand.teal,
      ),
      StatCard(label: 'Open Quotations', value: '${d['openQuotations'] ?? 0}', sub: 'not yet converted', icon: Icons.request_quote_outlined, color: Brand.navy),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Constrained(
          maxWidth: 1200,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CompanySelector(onChanged: _load),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: cols == 4 ? 2.6 : (w < 420 ? 1.55 : 2.2),
              children: stats,
            ),
            const SizedBox(height: 16),
            Wrap(spacing: 10, runSpacing: 10, children: [
              _quick(Icons.receipt_long, 'New ${DocType.invoice.labelFor(TaxMode.instance.gst)}', () => _open('/invoices/new?gst=${TaxMode.instance.gst ? 1 : 0}')),
              _quick(Icons.request_quote_outlined, DocType.quotation.labelFor(TaxMode.instance.gst), () => _open('/invoices/new?type=quotation&gst=${TaxMode.instance.gst ? 1 : 0}')),
              _quick(Icons.local_shipping_outlined, 'Delivery Challan', () => _open('/invoices/new?type=challan&gst=${TaxMode.instance.gst ? 1 : 0}')),
              _quick(Icons.add_card, 'Receive Payment', () async {
                if (await receivePayment(context)) _load();
              }),
              _quick(Icons.north_east, 'Add Expense', () => context.go('/expenses')),
              _quick(Icons.person_add_alt, 'Add Customer', () => _open('/customers/new')),
              _quick(Icons.add_box_outlined, 'Add Product', () => _open('/products/new')),
              _quick(Icons.bar_chart, 'Reports', () => context.go('/reports')),
              _quick(Icons.download_outlined, 'Export / Download', () => context.go('/export')),
            ]),
            const SizedBox(height: 16),
            SectionCard(title: 'Sales vs Expenses — last 6 months', child: _Bars(months: months)),
            LayoutBuilder(builder: (context, c) {
              final recentCard = SectionCard(
                title: 'Recent documents',
                trailing: TextButton(onPressed: () => context.go('/invoices'), child: const Text('View all')),
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                child: recent.isEmpty
                    ? const Padding(padding: EdgeInsets.all(24), child: Text('No invoices yet', textAlign: TextAlign.center))
                    : Column(children: [
                        for (final inv in recent) InvoiceTile(inv: inv, onTap: () => _open('/invoices/${inv['_id']}')),
                      ]),
              );
              final dueCard = SectionCard(
                title: 'Highest pending payments',
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                child: topDue.isEmpty
                    ? const Padding(padding: EdgeInsets.all(24), child: Text('No pending payments', textAlign: TextAlign.center))
                    : Column(children: [
                        for (final t in topDue)
                          ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.person, size: 20)),
                            title: Text('${t['name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: Text(rupee(t['balance']), style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w700)),
                            onTap: () => _open('/customers/${t['customer']}'),
                          ),
                      ]),
              );
              if (c.maxWidth >= 900) {
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 3, child: recentCard),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: dueCard),
                ]);
              }
              return Column(children: [recentCard, dueCard]);
            }),
          ]),
        ),
      ],
    );
  }

  Widget _quick(IconData icon, String label, VoidCallback onTap) => ActionChip(
        avatar: Icon(icon, size: 18),
        label: Text(label),
        onPressed: onTap,
        backgroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      );
}

class _Bars extends StatelessWidget {
  const _Bars({required this.months});
  final List<Map> months;
  @override
  Widget build(BuildContext context) {
    final maxV = months.fold<double>(0, (m, e) => [m, toD(e['total']), toD(e['expense'])].reduce((a, b) => a > b ? a : b));
    double h(dynamic v) => maxV == 0 ? 2 : 2 + 120 * toD(v) / maxV;
    Widget legend(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 6),
          Text(t, style: const TextStyle(fontSize: 12)),
        ]);
    return Column(children: [
      Row(children: [legend(Brand.teal, 'Sales'), const SizedBox(width: 16), legend(Brand.gold, 'Expenses')]),
      const SizedBox(height: 10),
      SizedBox(
        height: 190,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final m in months)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  FittedBox(child: Text(toD(m['total']) > 0 ? rupeeShort(m['total']) : '', style: const TextStyle(fontSize: 11))),
                  const SizedBox(height: 4),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Expanded(child: Container(height: h(m['total']), decoration: BoxDecoration(color: Brand.teal, borderRadius: BorderRadius.circular(5)))),
                    const SizedBox(width: 3),
                    Expanded(child: Container(height: h(m['expense']), decoration: BoxDecoration(color: Brand.gold, borderRadius: BorderRadius.circular(5)))),
                  ]),
                  const SizedBox(height: 6),
                  Text(monthLabel('${m['month']}'), style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                ]),
              ),
            ),
        ]),
      ),
    ]);
  }
}
