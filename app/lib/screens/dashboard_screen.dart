import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/api.dart';
import '../core/auth.dart';
import '../core/companies.dart';
import '../core/format.dart';
import '../widgets/common.dart';
import '../widgets/company_selector.dart';

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
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      await Companies.instance.ensure();
      final r = await Api.instance.get('/reports/dashboard', {'company': Companies.instance.selected});
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
        title: Text('Hello, $name'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh')],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open('/invoices/new'),
        icon: const Icon(Icons.add),
        label: const Text('New Invoice'),
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
      StatCard(label: "Today's Sales", value: rupeeShort(d['today']['total']), sub: '${d['today']['count']} invoices', icon: Icons.today, color: Colors.blue),
      StatCard(label: 'This Month', value: rupeeShort(d['month']['total']), sub: '${d['month']['count']} invoices', icon: Icons.calendar_month, color: Colors.indigo),
      StatCard(label: 'Outstanding', value: rupeeShort(d['outstanding']), sub: 'to be received', icon: Icons.account_balance_wallet, color: Colors.red),
      StatCard(label: 'GST This Month', value: rupeeShort(d['month']['tax']), sub: 'CGST + SGST + IGST', icon: Icons.percent, color: Colors.teal),
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
              _quick(Icons.receipt_long, 'New Invoice', () => _open('/invoices/new')),
              _quick(Icons.person_add_alt, 'Add Customer', () => _open('/customers/new')),
              _quick(Icons.add_box_outlined, 'Add Product', () => _open('/products/new')),
              _quick(Icons.bar_chart, 'GST Report', () => context.go('/reports')),
            ]),
            const SizedBox(height: 16),
            SectionCard(title: 'Sales — last 6 months', child: _Bars(months: months)),
            LayoutBuilder(builder: (context, c) {
              final recentCard = SectionCard(
                title: 'Recent invoices',
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
    final maxV = months.fold<double>(0, (m, e) => toD(e['total']) > m ? toD(e['total']) : m);
    final color = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: 190,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final m in months)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                FittedBox(child: Text(toD(m['total']) > 0 ? rupeeShort(m['total']) : '', style: const TextStyle(fontSize: 11))),
                const SizedBox(height: 4),
                Container(
                  height: maxV == 0 ? 2 : 2 + 130 * toD(m['total']) / maxV,
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
                ),
                const SizedBox(height: 6),
                Text(monthLabel('${m['month']}'), style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
              ]),
            ),
          ),
      ]),
    );
  }
}
