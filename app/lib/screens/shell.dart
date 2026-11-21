import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/auth.dart';

class _Dest {
  const _Dest(this.path, this.icon, this.selectedIcon, this.label);
  final String path, label;
  final IconData icon, selectedIcon;
}

const _all = [
  _Dest('/', Icons.space_dashboard_outlined, Icons.space_dashboard, 'Dashboard'),
  _Dest('/invoices', Icons.receipt_long_outlined, Icons.receipt_long, 'Invoices'),
  _Dest('/customers', Icons.people_outline, Icons.people, 'Customers'),
  _Dest('/products', Icons.inventory_2_outlined, Icons.inventory_2, 'Products'),
  _Dest('/reports', Icons.bar_chart_outlined, Icons.bar_chart, 'Reports'),
  _Dest('/companies', Icons.business_outlined, Icons.business, 'Companies'),
  _Dest('/settings', Icons.settings_outlined, Icons.settings, 'Settings'),
];

const _mobile = [
  _Dest('/', Icons.space_dashboard_outlined, Icons.space_dashboard, 'Home'),
  _Dest('/invoices', Icons.receipt_long_outlined, Icons.receipt_long, 'Invoices'),
  _Dest('/customers', Icons.people_outline, Icons.people, 'Customers'),
  _Dest('/products', Icons.inventory_2_outlined, Icons.inventory_2, 'Products'),
  _Dest('/more', Icons.menu, Icons.menu_open, 'More'),
];

const _topLevel = {'/', '/invoices', '/customers', '/products', '/reports', '/companies', '/settings', '/users', '/more'};

/// Side menu on wide screens (web/tablet), bottom bar on phones.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  int _index(List<_Dest> dests) {
    for (var i = dests.length - 1; i >= 0; i--) {
      final p = dests[i].path;
      if (p == '/' ? location == '/' : location.startsWith(p)) return i;
    }
    if (dests == _mobile && const ['/reports', '/companies', '/settings', '/users'].any(location.startsWith)) return 4;
    if (location.startsWith('/users')) return 6;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    if (wide) {
      final extended = MediaQuery.sizeOf(context).width >= 1200;
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            extended: extended,
            backgroundColor: Colors.white,
            selectedIndex: _index(_all),
            labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: extended
                  ? const _Brand()
                  : Icon(Icons.receipt_long, color: Theme.of(context).colorScheme.primary, size: 32),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: IconButton(
                    tooltip: 'Logout',
                    icon: const Icon(Icons.logout),
                    onPressed: () => AuthState.instance.logout(),
                  ),
                ),
              ),
            ),
            destinations: [
              for (final d in _all)
                NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: Text(d.label)),
            ],
            onDestinationSelected: (i) => context.go(_all[i].path),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ]),
      );
    }
    final showBar = _topLevel.contains(location);
    return Scaffold(
      body: child,
      bottomNavigationBar: showBar
          ? NavigationBar(
              selectedIndex: _index(_mobile),
              backgroundColor: Colors.white,
              height: 66,
              destinations: [
                for (final d in _mobile) NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label),
              ],
              onDestinationSelected: (i) => context.go(_mobile[i].path),
            )
          : null,
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 220,
        child: Row(children: [
          const SizedBox(width: 16),
          Icon(Icons.receipt_long, color: Theme.of(context).colorScheme.primary, size: 30),
          const SizedBox(width: 10),
          const Text('GST Billing', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ]),
      );
}
