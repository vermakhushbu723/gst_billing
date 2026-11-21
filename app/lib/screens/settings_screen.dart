import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/api.dart';
import '../core/auth.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _name = TextEditingController(text: '${AuthState.instance.user?['name'] ?? ''}');
  late final _phone = TextEditingController(text: '${AuthState.instance.user?['phone'] ?? ''}');
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    for (final c in [_name, _phone, _current, _new, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (_name.text.trim().isEmpty) return showSnack(context, 'Name is required', error: true);
    await runBusy(context, () => AuthState.instance.updateProfile(_name.text.trim(), _phone.text.trim()), success: 'Profile saved');
  }

  Future<void> _changePassword() async {
    if (_new.text.length < 6) return showSnack(context, 'New password must be at least 6 characters', error: true);
    if (_new.text != _confirm.text) return showSnack(context, 'Passwords do not match', error: true);
    final r = await runBusy(
      context,
      () => Api.instance.post('/auth/change-password', {'currentPassword': _current.text, 'newPassword': _new.text}),
      success: 'Password changed',
    );
    if (r != null) {
      _current.clear();
      _new.clear();
      _confirm.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthState.instance.user ?? {};
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Constrained(
          maxWidth: 700,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionCard(
              title: 'My profile',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('${user['email']} • ${user['role'] == 'admin' ? 'Admin' : 'Staff'}', style: TextStyle(color: Colors.grey.shade700)),
                const SizedBox(height: 12),
                TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
                const SizedBox(height: 12),
                TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile')),
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: _saveProfile, child: const Text('Save profile'))),
              ]),
            ),
            SectionCard(
              title: 'Change password',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(controller: _current, obscureText: true, decoration: const InputDecoration(labelText: 'Current password')),
                const SizedBox(height: 12),
                TextField(controller: _new, obscureText: true, decoration: const InputDecoration(labelText: 'New password')),
                const SizedBox(height: 12),
                TextField(controller: _confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm new password')),
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: _changePassword, child: const Text('Change password'))),
              ]),
            ),
            Card(
              child: Column(children: [
                if (AuthState.instance.isAdmin)
                  ListTile(
                    leading: const Icon(Icons.group_outlined),
                    title: const Text('Users & staff'),
                    subtitle: const Text('Who can login to this billing app'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/users'),
                  ),
                ListTile(
                  leading: const Icon(Icons.business_outlined),
                  title: const Text('Companies'),
                  subtitle: const Text('Logo, address, GSTIN, bank, terms, invoice numbers'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/companies'),
                ),
                ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: const Text('Server'),
                  subtitle: Text(Api.baseUrl),
                ),
                ListTile(
                  leading: Icon(Icons.logout, color: Colors.red.shade700),
                  title: Text('Logout', style: TextStyle(color: Colors.red.shade700)),
                  onTap: () async {
                    if (await confirm(context, 'Logout?', 'You will need to login again.', ok: 'Logout')) {
                      AuthState.instance.logout();
                    }
                  },
                ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}
