import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/auth.dart';
import '../widgets/common.dart';
import '../widgets/top_actions.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<Map>? _users;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await Api.instance.get('/users');
      if (mounted) setState(() => _users = List<Map>.from(r));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _edit([Map? u]) async {
    final name = TextEditingController(text: '${u?['name'] ?? ''}');
    final email = TextEditingController(text: '${u?['email'] ?? ''}');
    final phone = TextEditingController(text: '${u?['phone'] ?? ''}');
    final password = TextEditingController();
    var role = '${u?['role'] ?? 'staff'}';
    var active = u?['active'] != false;
    final isSelf = u != null && u['id'] == AuthState.instance.user?['id'];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(u == null ? 'Add user' : 'Edit user'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
                const SizedBox(height: 12),
                TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email (login id)')),
                const SizedBox(height: 12),
                TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile')),
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: InputDecoration(labelText: u == null ? 'Password' : 'New password (leave empty to keep)'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: const [
                    DropdownMenuItem(value: 'staff', child: Text('Staff — billing only')),
                    DropdownMenuItem(value: 'admin', child: Text('Admin — everything')),
                  ],
                  onChanged: isSelf ? null : (v) => role = v ?? role,
                ),
                if (u != null && !isSelf)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active'),
                    value: active,
                    onChanged: (v) => set(() => active = v),
                  ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final body = {
      'name': name.text.trim(),
      'email': email.text.trim(),
      'phone': phone.text.trim(),
      'role': role,
      if (password.text.isNotEmpty) 'password': password.text,
      if (u != null) 'active': active,
    };
    await runBusy(
      context,
      () => u == null ? Api.instance.post('/users', body) : Api.instance.put('/users/${u['id']}', body),
      success: 'User saved',
    );
    _load();
  }

  Future<void> _delete(Map u) async {
    if (!await confirm(context, 'Delete user?', '${u['name']} will not be able to login.', ok: 'Delete', danger: true)) return;
    if (!mounted) return;
    await runBusy(context, () => Api.instance.delete('/users/${u['id']}'), success: 'User deleted');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Users & staff'), actions: topActions()),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.person_add_alt), label: const Text('Add User')),
      body: _error != null && _users == null
          ? ErrorView(message: _error!, onRetry: _load)
          : _users == null
              ? const LoadingView()
              : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
                  Constrained(
                    maxWidth: 800,
                    child: Card(
                      child: Column(children: [
                        for (final u in _users!)
                          ListTile(
                            leading: CircleAvatar(child: Icon(u['role'] == 'admin' ? Icons.admin_panel_settings : Icons.person)),
                            title: Text('${u['name']}${u['active'] == false ? ' (disabled)' : ''}'),
                            subtitle: Text('${u['email']} • ${u['role']}'),
                            onTap: () => _edit(u),
                            trailing: u['id'] == AuthState.instance.user?['id']
                                ? const Chip(label: Text('You'))
                                : IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(u)),
                          ),
                      ]),
                    ),
                  ),
                ]),
    );
  }
}
