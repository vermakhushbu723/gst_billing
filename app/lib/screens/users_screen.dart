import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/auth.dart';
import '../core/brand.dart';
import '../core/companies.dart';
import '../widgets/common.dart';
import '../widgets/top_actions.dart';

/// Logins. The main admin sees every login and can create company logins;
/// a company admin manages only their own company's logins.
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key, this.company});

  /// Show only this company's logins (from Companies → Logins).
  final String? company;
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<Map>? _users;
  String? _error;
  late String _filter = widget.company ?? 'all';

  bool get _super => AuthState.instance.isSuperAdmin;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      await Companies.instance.ensure();
      final r = await Api.instance.get('/users', {'company': _super ? _filter : null});
      if (mounted) setState(() => _users = List<Map>.from(r));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  String _roleLabel(Map u) => u['company'] == null ? (u['role'] == 'admin' ? 'Main Admin' : 'Staff (all companies)') : (u['role'] == 'admin' ? 'Company Admin' : 'Staff');

  Future<void> _edit([Map? u]) async {
    final name = TextEditingController(text: '${u?['name'] ?? ''}');
    final email = TextEditingController(text: '${u?['email'] ?? ''}');
    final phone = TextEditingController(text: '${u?['phone'] ?? ''}');
    final password = TextEditingController();
    var role = '${u?['role'] ?? (u == null && _super ? 'admin' : 'staff')}';
    var active = u?['active'] != false;
    // '' = main login for all companies (main admin only)
    var company = u != null ? '${u['company'] ?? ''}' : (_filter != 'all' ? _filter : (Companies.instance.list.isNotEmpty ? '${Companies.instance.list.first['_id']}' : ''));
    final isSelf = u != null && u['id'] == AuthState.instance.user?['id'];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(u == null ? 'Add login' : 'Edit login'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (_super && !isSelf) ...[
                  DropdownButtonFormField<String>(
                    initialValue: company,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Login for', prefixIcon: Icon(Icons.business_outlined)),
                    items: [
                      for (final c in Companies.instance.list)
                        DropdownMenuItem(value: '${c['_id']}', child: Text('${c['name']}', overflow: TextOverflow.ellipsis)),
                      const DropdownMenuItem(value: '', child: Text('ALL COMPANIES (main login)')),
                    ],
                    onChanged: (v) => set(() => company = v ?? company),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 6),
                    child: Text(
                      company.isEmpty ? 'Can see and manage every company.' : 'Will see only ${Companies.instance.nameOf(company)} data.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ),
                ],
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
                const SizedBox(height: 12),
                TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email (login id)')),
                const SizedBox(height: 12),
                TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile (can also be used to login)')),
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: InputDecoration(labelText: u == null ? 'Password (min 6)' : 'New password (leave empty to keep)'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: [
                    DropdownMenuItem(value: 'admin', child: Text(company.isEmpty && _super ? 'Main Admin — everything' : 'Company Admin — full access to the company')),
                    const DropdownMenuItem(value: 'staff', child: Text('Staff — billing, payments, customers')),
                  ],
                  onChanged: isSelf ? null : (v) => role = v ?? role,
                ),
                if (u != null && !isSelf)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active (can login)'),
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
    final body = <String, dynamic>{
      'name': name.text.trim(),
      'email': email.text.trim(),
      'phone': phone.text.trim(),
      'role': role,
      if (password.text.isNotEmpty) 'password': password.text,
      if (u != null) 'active': active,
      if (_super && !isSelf) 'loginCompany': company.isEmpty ? null : company,
    };
    await runBusy(
      context,
      () => u == null ? Api.instance.post('/users', body) : Api.instance.put('/users/${u['id']}', body),
      success: 'Login saved',
    );
    _load();
  }

  Future<void> _delete(Map u) async {
    if (!await confirm(context, 'Delete login?', '${u['name']} will not be able to login any more.', ok: 'Delete', danger: true)) return;
    if (!mounted) return;
    await runBusy(context, () => Api.instance.delete('/users/${u['id']}'), success: 'Login deleted');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final users = _users;
    // group by company for the main admin
    final groups = <String, List<Map>>{};
    for (final u in users ?? <Map>[]) {
      final key = u['company'] == null ? '' : '${u['company']}';
      groups.putIfAbsent(key, () => []).add(u);
    }
    final keys = groups.keys.toList()..sort((a, b) => a.isEmpty ? -1 : (b.isEmpty ? 1 : Companies.instance.nameOf(a).compareTo(Companies.instance.nameOf(b))));
    return Scaffold(
      appBar: AppBar(title: const Text('Users & Logins'), actions: topActions()),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.person_add_alt), label: const Text('Add Login')),
      body: _error != null && users == null
          ? ErrorView(message: _error!, onRetry: _load)
          : users == null
              ? const LoadingView()
              : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
                  Constrained(
                    maxWidth: 860,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (_super) ...[
                        Card(
                          color: Brand.goldLight,
                          child: const Padding(
                            padding: EdgeInsets.all(14),
                            child: Text(
                              'Each company can have its own login. A company login sees only that company\'s invoices, customers, payments, expenses and reports.',
                              style: TextStyle(color: Brand.navy),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(children: [
                            for (final c in [('all', 'All logins'), for (final co in Companies.instance.list) ('${co['_id']}', '${co['name']}')])
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(c.$2),
                                  selected: _filter == c.$1,
                                  onSelected: (_) {
                                    setState(() => _filter = c.$1);
                                    _load();
                                  },
                                ),
                              ),
                          ]),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (users.isEmpty)
                        EmptyView(
                          icon: Icons.group_outlined,
                          text: 'No logins yet for this company',
                          action: FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Add login')),
                        ),
                      for (final k in keys) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                          child: Text(
                            k.isEmpty ? 'MAIN LOGINS (ALL COMPANIES)' : Companies.instance.nameOf(k).toUpperCase(),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: Brand.slate),
                          ),
                        ),
                        Card(
                          child: Column(children: [
                            for (final u in groups[k]!)
                              ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: u['active'] == false ? Colors.grey.shade300 : Brand.tealLight,
                                  child: Icon(u['role'] == 'admin' ? Icons.admin_panel_settings : Icons.person, color: Brand.teal),
                                ),
                                title: Text('${u['name']}${u['active'] == false ? ' (disabled)' : ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text('${u['email']}${'${u['phone'] ?? ''}'.isNotEmpty ? ' • ${u['phone']}' : ''}\n${_roleLabel(u)}'),
                                isThreeLine: true,
                                onTap: () => _edit(u),
                                trailing: u['id'] == AuthState.instance.user?['id']
                                    ? const Chip(label: Text('You'))
                                    : IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(u)),
                              ),
                          ]),
                        ),
                      ],
                    ]),
                  ),
                ]),
    );
  }
}
