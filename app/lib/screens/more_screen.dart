import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/auth.dart';
import '../core/brand.dart';
import '../widgets/common.dart';
import '../widgets/top_actions.dart';

/// Phone menu for everything that does not fit in the bottom bar.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = AuthState.instance.user ?? {};
    Widget tile(IconData icon, String title, String sub, String path) => ListTile(
          leading: Icon(icon, color: Brand.teal),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(sub),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go(path),
        );
    Widget group(String title, List<Widget> tiles) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
            child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: Brand.slate)),
          ),
          Card(child: Column(children: tiles)),
        ]);
    return Scaffold(
      appBar: AppBar(title: const Text('More'), actions: topActions()),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Center(child: BrandLogo(height: 72, full: true)),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const CircleAvatar(backgroundColor: Brand.tealLight, child: Icon(Icons.person, color: Brand.teal)),
            title: Text('${user['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${user['email'] ?? ''}'),
          ),
        ),
        group('SALES', [
          tile(Icons.request_quote_outlined, 'Quotations', 'Estimates — convert to invoice in one tap', '/quotations'),
          tile(Icons.local_shipping_outlined, 'Delivery Challans', 'Goods sent before billing', '/challans'),
          tile(Icons.assignment_return_outlined, 'Credit Notes', 'Sales returns against invoices', '/credit-notes'),
        ]),
        group('MONEY', [
          tile(Icons.account_balance_wallet_outlined, 'Expenses', 'Kharcha with categories', '/expenses'),
          tile(Icons.bar_chart, 'Reports', 'GST, P&L, customer & item-wise', '/reports'),
          tile(Icons.download_outlined, 'Export / Download', 'All data to Excel, CSV or PDF', '/export'),
        ]),
        group('MASTERS', [
          tile(Icons.inventory_2_outlined, 'Products', 'Items, rates, GST, HSN', '/products'),
          AuthState.instance.isCompanyLogin
              ? tile(Icons.business, 'My Company', 'Logo, GSTIN, bank, numbering', '/companies')
              : tile(Icons.business, 'Companies', 'All firms — details, numbering and logins', '/companies'),
          tile(Icons.tune, 'Units, GST & Lists', 'Units, GST rates, payment modes, expense categories', '/masters'),
          if (AuthState.instance.isAdmin) tile(Icons.group_outlined, 'Users & Logins', 'Who can login', '/users'),
          tile(Icons.settings_outlined, 'Settings', 'Profile and password', '/settings'),
        ]),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: Icon(Icons.logout, color: Colors.red.shade700),
            title: Text('Logout', style: TextStyle(color: Colors.red.shade700)),
            onTap: () async {
              if (await confirm(context, 'Logout?', 'You will need to login again.', ok: 'Logout')) {
                AuthState.instance.logout();
              }
            },
          ),
        ),
      ]),
    );
  }
}
