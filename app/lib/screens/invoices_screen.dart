import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/api.dart';
import '../core/companies.dart';
import '../core/docs.dart';
import '../core/format.dart';
import '../widgets/common.dart';
import '../widgets/company_selector.dart';

class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key, this.docType = DocType.invoice});
  final DocType docType;
  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  final List<Map> _items = [];
  int _page = 1, _pages = 1, _total = 0;
  double _sumTotal = 0, _sumBalance = 0;
  DocType get _type => widget.docType;
  String get _newPath => '/invoices/new${_type.isInvoice ? '' : '?type=${_type.key}'}';
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
        'type': _type.key,
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
        _sumTotal = toD(r['sumTotal']);
        _sumBalance = toD(r['sumBalance']);
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<(String, String)> get _statuses => switch (_type) {
        DocType.invoice => const [('all', 'All'), ('due', 'Unpaid'), ('paid', 'Paid'), ('cancelled', 'Cancelled')],
        DocType.creditNote => const [('all', 'All'), ('issued', 'Issued'), ('cancelled', 'Cancelled')],
        _ => const [('all', 'All'), ('open', 'Open'), ('converted', 'Converted'), ('cancelled', 'Cancelled')],
      };

  Future<void> _open(String path) async {
    await context.push(path);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${_type.plural}${_total > 0 ? ' ($_total)' : ''}')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(_newPath),
        icon: const Icon(Icons.add),
        label: Text('New ${_type.label}'),
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
                  for (final s in _statuses)
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
          if (_total > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(children: [
                Text('Total: ', style: TextStyle(color: Colors.grey.shade700)),
                Text(rupee(_sumTotal), style: const TextStyle(fontWeight: FontWeight.w700)),
                if (_type.isInvoice) ...[
                  const SizedBox(width: 16),
                  Text('Pending: ', style: TextStyle(color: Colors.grey.shade700)),
                  Text(rupee(_sumBalance), style: TextStyle(fontWeight: FontWeight.w700, color: Colors.red.shade700)),
                ],
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
        text: 'No ${_type.plural.toLowerCase()} found',
        action: FilledButton.icon(onPressed: () => _open(_newPath), icon: const Icon(Icons.add), label: Text('Create ${_type.label.toLowerCase()}')),
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
