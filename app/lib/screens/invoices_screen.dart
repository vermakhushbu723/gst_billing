import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/api.dart';
import '../core/companies.dart';
import '../core/format.dart';
import '../widgets/common.dart';
import '../widgets/company_selector.dart';

class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key});
  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  final List<Map> _items = [];
  int _page = 1, _pages = 1, _total = 0;
  bool _loading = false;
  String? _error;
  String _status = 'all';
  String _q = '';
  String _from = '', _to = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    _page = 1;
    _items.clear();
    await _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Companies.instance.ensure();
      final r = await Api.instance.get('/invoices', {
        'company': Companies.instance.selected,
        'status': _status,
        'q': _q,
        'from': _from,
        'to': _to,
        'page': _page,
        'limit': 30,
      });
      if (!mounted) return;
      setState(() {
        _items.addAll(List<Map>.from(r['items']));
        _pages = r['pages'];
        _total = r['total'];
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(String path) async {
    await context.push(path);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Invoices${_total > 0 ? ' ($_total)' : ''}')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open('/invoices/new'),
        icon: const Icon(Icons.add),
        label: const Text('New Invoice'),
      ),
      body: Constrained(
        maxWidth: 1000,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CompanySelector(onChanged: _reload),
              const SizedBox(height: 10),
              TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search customer or invoice no.'),
                onChanged: (v) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 400), () {
                    _q = v.trim();
                    _reload();
                  });
                },
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final s in const [('all', 'All'), ('due', 'Unpaid'), ('paid', 'Paid'), ('cancelled', 'Cancelled')])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(s.$2),
                        selected: _status == s.$1,
                        onSelected: (_) {
                          setState(() => _status = s.$1);
                          _reload();
                        },
                      ),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.date_range, size: 18),
                    label: Text(_from.isEmpty ? 'Date range' : '${dmy(_from)} - ${dmy(_to)}'),
                    onPressed: () async {
                      final r = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2015),
                        lastDate: DateTime(2100),
                      );
                      if (r != null) {
                        setState(() {
                          _from = ymdOf(r.start);
                          _to = ymdOf(r.end);
                        });
                        _reload();
                      }
                    },
                  ),
                  if (_from.isNotEmpty)
                    IconButton(
                      tooltip: 'Clear dates',
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() => _from = _to = '');
                        _reload();
                      },
                    ),
                ]),
              ),
            ]),
          ),
          Expanded(child: _list()),
        ]),
      ),
    );
  }

  Widget _list() {
    if (_error != null && _items.isEmpty) return ErrorView(message: _error!, onRetry: _reload);
    if (_loading && _items.isEmpty) return const LoadingView();
    if (_items.isEmpty) {
      return EmptyView(
        icon: Icons.receipt_long,
        text: 'No invoices found',
        action: FilledButton.icon(onPressed: () => _open('/invoices/new'), icon: const Icon(Icons.add), label: const Text('Create invoice')),
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: _items.length + (_page < _pages ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
        itemBuilder: (_, i) {
          if (i == _items.length) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: _loading
                    ? const CircularProgressIndicator()
                    : OutlinedButton(
                        onPressed: () {
                          _page++;
                          _fetch();
                        },
                        child: const Text('Load more'),
                      ),
              ),
            );
          }
          final inv = _items[i];
          return Material(
            color: Colors.white,
            child: InvoiceTile(inv: inv, onTap: () => _open('/invoices/${inv['_id']}')),
          );
        },
      ),
    );
  }
}
