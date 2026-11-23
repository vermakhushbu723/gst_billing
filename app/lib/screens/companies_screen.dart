import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/api.dart';
import '../core/auth.dart';
import '../core/companies.dart';
import '../widgets/common.dart';
import '../widgets/top_actions.dart';

class CompaniesScreen extends StatefulWidget {
  const CompaniesScreen({super.key});
  @override
  State<CompaniesScreen> createState() => _CompaniesScreenState();
}

class _CompaniesScreenState extends State<CompaniesScreen> {
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Companies.instance.load();
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _open(String path) async {
    await context.push(path);
    _load();
  }

  Future<void> _delete(Map c) async {
    if (!await confirm(context, 'Delete company?', '${c['name']} will be removed. If it has invoices it is only deactivated.', ok: 'Delete', danger: true)) {
      return;
    }
    if (!mounted) return;
    final r = await runBusy(context, () => Api.instance.delete('/companies/${c['_id']}'));
    if (r != null && mounted) showSnack(context, '${r['message'] ?? 'Company deleted'}');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final admin = AuthState.instance.isAdmin;
    final superAdmin = AuthState.instance.isSuperAdmin;
    final list = Companies.instance.list;
    return Scaffold(
      appBar: AppBar(title: Text(superAdmin ? 'Companies (${list.length})' : 'My Company'), actions: topActions()),
      floatingActionButton: superAdmin
          ? FloatingActionButton.extended(onPressed: () => _open('/companies/new'), icon: const Icon(Icons.add_business), label: const Text('Add Company'))
          : null,
      body: _loading && list.isEmpty
          ? const LoadingView()
          : _error != null && list.isEmpty
              ? ErrorView(message: _error!, onRetry: _load)
              : list.isEmpty
                  ? const EmptyView(icon: Icons.business, text: 'No companies yet')
                  : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
                      Constrained(
                        maxWidth: 1000,
                        child: Column(children: [
                          for (final c in list)
                            Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                contentPadding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                                onTap: admin ? () => _open('/companies/${c['_id']}/edit') : null,
                                leading: CircleAvatar(
                                  radius: 24,
                                  backgroundColor: _color(c['color']).withValues(alpha: 0.12),
                                  child: Icon(Icons.business, color: _color(c['color'])),
                                ),
                                title: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: Text(
                                  [
                                    if ('${c['gstin'] ?? ''}'.isNotEmpty) 'GSTIN ${c['gstin']}',
                                    'Next invoice: ${c['invoicePrefix'] ?? ''}${c['nextInvoiceNo']}',
                                    if ('${c['mobile'] ?? ''}'.isNotEmpty) c['mobile'],
                                    if (superAdmin) '${c['logins'] ?? 0} login${c['logins'] == 1 ? '' : 's'}',
                                  ].join(' • '),
                                ),
                                trailing: admin
                                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                                        TextButton.icon(
                                          onPressed: () => _open('/users?company=${c['_id']}'),
                                          icon: const Icon(Icons.key_outlined, size: 18),
                                          label: Text(superAdmin ? 'Logins' : 'Staff logins'),
                                        ),
                                        IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit), onPressed: () => _open('/companies/${c['_id']}/edit')),
                                        if (superAdmin) IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: () => _delete(c)),
                                      ])
                                    : null,
                              ),
                            ),
                          if (!admin)
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text('Only admin can change company details.', style: TextStyle(color: Colors.grey.shade600)),
                            ),
                          if (superAdmin)
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                'Tip: use "Logins" to give each company its own login. That login will see only that company\'s data.',
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                            ),
                        ]),
                      ),
                    ]),
    );
  }

  Color _color(dynamic hex) {
    final s = '${hex ?? ''}'.replaceFirst('#', '');
    return s.length == 6 ? Color(int.parse('FF$s', radix: 16)) : Colors.black;
  }
}
