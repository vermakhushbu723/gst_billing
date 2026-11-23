import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../widgets/common.dart';
import '../widgets/company_selector.dart';
import '../core/companies.dart';
import '../widgets/top_actions.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});
  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  List<Map>? _items;
  String? _error;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      await Companies.instance.ensure();
      final r = await Api.instance.get('/products', {'company': Companies.instance.selected});
      if (mounted) setState(() => _items = List<Map>.from(r));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _open(String path) async {
    await context.push(path);
    _load();
  }

  Future<void> _delete(Map p) async {
    if (!await confirm(context, 'Delete product?', '${p['name']} will be removed from the list. Old invoices are not affected.', ok: 'Delete', danger: true)) {
      return;
    }
    if (!mounted) return;
    await runBusy(context, () => Api.instance.delete('/products/${p['_id']}'), success: 'Product deleted');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = (_items ?? []).where((p) => _q.isEmpty || '${p['name']}'.toLowerCase().contains(_q.toLowerCase())).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Products / Items'), actions: topActions()),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open('/products/new'),
        icon: const Icon(Icons.add),
        label: const Text('Add Product'),
      ),
      body: Constrained(
        maxWidth: 1000,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: CompanySelector(onChanged: _load),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search products'),
              onChanged: (v) => setState(() => _q = v.trim()),
            ),
          ),
          Expanded(
            child: _error != null && _items == null
                ? ErrorView(message: _error!, onRetry: _load)
                : _items == null
                    ? const LoadingView()
                    : items.isEmpty
                        ? EmptyView(
                            icon: Icons.inventory_2_outlined,
                            text: 'No products',
                            action: FilledButton.icon(onPressed: () => _open('/products/new'), icon: const Icon(Icons.add), label: const Text('Add product')),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.only(bottom: 96),
                              itemCount: items.length,
                              separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
                              itemBuilder: (_, i) {
                                final p = items[i];
                                return Material(
                                  color: Colors.white,
                                  child: ListTile(
                                    onTap: () => _open('/products/${p['_id']}/edit'),
                                    leading: const CircleAvatar(child: Icon(Icons.inventory_2_outlined, size: 20)),
                                    title: Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                                    subtitle: Text([
                                      'GST ${pct(p['gstRate'])}',
                                      if (Companies.instance.selected == 'all' && !Companies.instance.locked) Companies.instance.nameOf('${p['company']}'),
                                      if ('${p['hsn'] ?? ''}'.isNotEmpty) 'HSN ${p['hsn']}',
                                    ].join(' • ')),
                                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                      Text('${rupee(p['rate'])} / ${p['unit']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                                      IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(p)),
                                    ]),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ]),
      ),
    );
  }
}
