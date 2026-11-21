import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../widgets/common.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});
  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  List<Map>? _items;
  String? _error;
  String _q = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await Api.instance.get('/customers', {'q': _q});
      if (mounted) setState(() => _items = List<Map>.from(r));
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
    final totalDue = (_items ?? []).fold<double>(0, (s, c) => s + toD(c['balance']));
    return Scaffold(
      appBar: AppBar(title: const Text('Customers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open('/customers/new'),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Add Customer'),
      ),
      body: Constrained(
        maxWidth: 1000,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search name, mobile or GSTIN'),
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 350), () {
                  _q = v.trim();
                  _load();
                });
              },
            ),
          ),
          if (_items != null && _items!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(children: [
                Text('${_items!.length} customers', style: TextStyle(color: Colors.grey.shade700)),
                const Spacer(),
                Text('Total to receive: ', style: TextStyle(color: Colors.grey.shade700)),
                Text(rupee(totalDue), style: TextStyle(fontWeight: FontWeight.w700, color: Colors.red.shade700)),
              ]),
            ),
          Expanded(child: _list()),
        ]),
      ),
    );
  }

  Widget _list() {
    if (_error != null && _items == null) return ErrorView(message: _error!, onRetry: _load);
    if (_items == null) return const LoadingView();
    if (_items!.isEmpty) {
      return EmptyView(
        icon: Icons.people_outline,
        text: _q.isEmpty ? 'No customers yet' : 'No customer matches "$_q"',
        action: FilledButton.icon(onPressed: () => _open('/customers/new'), icon: const Icon(Icons.add), label: const Text('Add customer')),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: _items!.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
        itemBuilder: (_, i) {
          final c = _items![i];
          final due = toD(c['balance']);
          return Material(
            color: Colors.white,
            child: ListTile(
              onTap: () => _open('/customers/${c['_id']}'),
              leading: CircleAvatar(child: Text('${c['name']}'.isEmpty ? '?' : '${c['name']}'[0].toUpperCase())),
              title: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                [c['gstin'], c['phone'], c['state']].where((e) => '${e ?? ''}'.isNotEmpty).join(' • '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(rupee(due), style: TextStyle(fontWeight: FontWeight.w700, color: due > 0 ? Colors.red.shade700 : Colors.green.shade700)),
                Text(due > 0 ? 'to receive' : 'settled', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ]),
            ),
          );
        },
      ),
    );
  }
}
