import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/auth.dart';
import '../widgets/common.dart';

/// Phone menu for the screens that do not fit in the bottom bar.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = AuthState.instance.user ?? {};
    Widget tile(IconData icon, String title, String sub, VoidCallback onTap) => ListTile(
          leading: Icon(icon),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(sub),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        );
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text('${user['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${user['email'] ?? ''}'),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(children: [
            tile(Icons.bar_chart, 'Reports', 'Sales register, GST summary, export', () => context.push('/reports')),
            tile(Icons.business, 'Companies', 'Your 5 firms — logo, GSTIN, bank, terms', () => context.push('/companies')),
            if (AuthState.instance.isAdmin) tile(Icons.group_outlined, 'Users & staff', 'Who can login', () => context.push('/users')),
            tile(Icons.settings_outlined, 'Settings', 'Profile and password', () => context.push('/settings')),
          ]),
        ),
        const SizedBox(height: 8),
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
