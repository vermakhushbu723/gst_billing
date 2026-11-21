import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/auth.dart';
import '../core/brand.dart';

class _Dest {
  const _Dest(this.path, this.icon, this.label, {this.adminOnly = false});
  final String path, label;
  final IconData icon;
  final bool adminOnly;
}

/// Sidebar menu, grouped.
const _groups = <(String, List<_Dest>)>[
  ('', [_Dest('/', Icons.space_dashboard_outlined, 'Dashboard')]),
  ('SALES', [
    _Dest('/invoices', Icons.receipt_long_outlined, 'Invoices'),
    _Dest('/quotations', Icons.request_quote_outlined, 'Quotations'),
    _Dest('/challans', Icons.local_shipping_outlined, 'Delivery Challans'),
    _Dest('/credit-notes', Icons.assignment_return_outlined, 'Credit Notes'),
  ]),
  ('MONEY', [
    _Dest('/payments', Icons.payments_outlined, 'Payments In'),
    _Dest('/expenses', Icons.account_balance_wallet_outlined, 'Expenses'),
    _Dest('/reports', Icons.bar_chart_outlined, 'Reports'),
  ]),
  ('MASTERS', [
    _Dest('/customers', Icons.people_outline, 'Customers'),
    _Dest('/products', Icons.inventory_2_outlined, 'Products'),
    _Dest('/companies', Icons.business_outlined, 'Companies'),
    _Dest('/masters', Icons.tune, 'Units, GST & Lists'),
    _Dest('/users', Icons.group_outlined, 'Users & Staff', adminOnly: true),
    _Dest('/settings', Icons.settings_outlined, 'Settings'),
  ]),
];

const _mobile = [
  _Dest('/', Icons.space_dashboard_outlined, 'Home'),
  _Dest('/invoices', Icons.receipt_long_outlined, 'Invoices'),
  _Dest('/customers', Icons.people_outline, 'Customers'),
  _Dest('/payments', Icons.payments_outlined, 'Payments'),
  _Dest('/more', Icons.menu, 'More'),
];

const _topLevel = {
  '/', '/invoices', '/quotations', '/challans', '/credit-notes', '/payments', '/expenses', '/customers', '/products',
  '/reports', '/companies', '/masters', '/settings', '/users', '/more',
};

bool _matches(String location, String path) => path == '/' ? location == '/' : location == path || location.startsWith('$path/');

/// Sidebar on wide screens (web/tablet), bottom bar on phones.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 900) {
      return Scaffold(
        body: Row(children: [
          _Sidebar(location: location, compact: width < 1200),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ]),
      );
    }
    final showBar = _topLevel.contains(location);
    var index = _mobile.indexWhere((d) => d.path != '/more' && _matches(location, d.path));
    if (index < 0) index = location == '/' ? 0 : 4;
    return Scaffold(
      body: child,
      bottomNavigationBar: showBar
          ? NavigationBar(
              selectedIndex: index,
              backgroundColor: Colors.white,
              height: 66,
              destinations: [for (final d in _mobile) NavigationDestination(icon: Icon(d.icon), label: d.label)],
              onDestinationSelected: (i) => context.go(_mobile[i].path),
            )
          : null,
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.location, required this.compact});
  final String location;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final admin = AuthState.instance.isAdmin;
    return Container(
      width: compact ? 76 : 228,
      color: Colors.white,
      child: Column(children: [
        Padding(
          padding: EdgeInsets.fromLTRB(compact ? 10 : 22, 12, compact ? 10 : 22, 6),
          child: SizedBox(
            height: 46,
            child: Align(
              alignment: compact ? Alignment.center : Alignment.centerLeft,
              child: compact ? const BrandLogo(height: 30) : const BrandWordmark(size: 21),
            ),
          ),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), children: [
            for (final g in _groups) ...[
              if (g.$1.isNotEmpty)
                Padding(
                  padding: EdgeInsets.fromLTRB(compact ? 0 : 12, 12, 0, 4),
                  child: compact
                      ? const Divider(height: 1)
                      : Text(g.$1, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1, color: Brand.slate)),
                ),
              for (final d in g.$2)
                if (!d.adminOnly || admin) _item(context, d),
            ],
          ]),
        ),
        if (!compact)
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 8, 22, 14),
            child: Text(Brand.tagline, style: TextStyle(fontSize: 11, color: Brand.slate)),
          ),
      ]),
    );
  }

  Widget _item(BuildContext context, _Dest d) {
    final selected = _matches(location, d.path);
    final color = selected ? Brand.teal : Brand.slate;
    final tile = Material(
      color: selected ? Brand.goldLight : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => context.go(d.path),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12, vertical: 8),
          child: compact
              ? Center(child: Icon(d.icon, color: color))
              : Row(children: [
                  Icon(d.icon, color: color, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(d.label,
                        style: TextStyle(fontSize: 14, color: selected ? Brand.teal : Brand.navy, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
                  ),
                ]),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: compact ? Tooltip(message: d.label, child: tile) : tile,
    );
  }
}
