import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/brand.dart';
import '../core/companies.dart';
import '../core/format.dart';
import '../core/gst.dart' show paymentModes;
import '../core/masters.dart';
import '../widgets/common.dart';
import '../widgets/company_selector.dart';
import '../widgets/period_filter.dart';

/// Business expenses (kharcha) per company, with category totals.
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  Period _period = Period.preset('month');
  String _category = 'all';
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      await Companies.instance.ensure();
      await Masters.instance.ensure();
      final r = await Api.instance.get('/expenses', {
        'company': Companies.instance.selected,
        'from': _period.from,
        'to': _period.to,
        'category': _category,
      });
      if (mounted) setState(() => _data = Map<String, dynamic>.from(r));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _edit([Map? e]) async {
    final cats = Masters.instance.expenseCategories;
    var company = '${e?['company'] ?? Companies.instance.defaultId ?? ''}';
    var category = '${e?['category'] ?? cats.first}';
    var mode = '${e?['mode'] ?? paymentModes.first}';
    var date = '${e?['date'] ?? today()}';
    final amount = TextEditingController(text: e == null ? '' : '${e['amount']}');
    final paidTo = TextEditingController(text: '${e?['paidTo'] ?? ''}');
    final note = TextEditingController(text: '${e?['note'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(e == null ? 'Add expense' : 'Edit expense'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  initialValue: Companies.instance.byId(company) != null ? company : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Company'),
                  items: [for (final c in Companies.instance.list) DropdownMenuItem(value: c['_id'] as String, child: Text('${c['name']}', overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => company = v ?? company,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [for (final c in {...cats, category}) DropdownMenuItem(value: c, child: Text(c))],
                  onChanged: (v) => category = v ?? category,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amount,
                  autofocus: e == null,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  decoration: const InputDecoration(labelText: 'Amount (₹)'),
                ),
                const SizedBox(height: 12),
                DateField(label: 'Date', value: date, onChanged: (v) => set(() => date = v)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: mode,
                  decoration: const InputDecoration(labelText: 'Paid by'),
                  items: [for (final m in {...paymentModes, mode}) DropdownMenuItem(value: m, child: Text(m))],
                  onChanged: (v) => mode = v ?? mode,
                ),
                const SizedBox(height: 12),
                TextField(controller: paidTo, decoration: const InputDecoration(labelText: 'Paid to (optional)')),
                const SizedBox(height: 12),
                TextField(controller: note, decoration: const InputDecoration(labelText: 'Note / bill no. (optional)')),
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
      'company': company,
      'category': category,
      'amount': double.tryParse(amount.text) ?? 0,
      'date': date,
      'mode': mode,
      'paidTo': paidTo.text.trim(),
      'note': note.text.trim(),
    };
    await runBusy(context, () => e == null ? Api.instance.post('/expenses', body) : Api.instance.put('/expenses/${e['_id']}', body), success: 'Expense saved');
    _load();
  }

  Future<void> _delete(Map e) async {
    if (!await confirm(context, 'Delete expense?', '${e['category']} ${rupee(e['amount'])} on ${dmy(e['date'])}', ok: 'Delete', danger: true)) return;
    if (!mounted) return;
    await runBusy(context, () => Api.instance.delete('/expenses/${e['_id']}'), success: 'Expense deleted');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = List<Map>.from(_data?['items'] ?? []);
    final byCat = Map<String, dynamic>.from(_data?['byCategory'] ?? {});
    final multi = Companies.instance.selected == 'all';
    return Scaffold(
      appBar: AppBar(title: const Text('Expenses')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Add Expense')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
          Constrained(
            maxWidth: 1000,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              CompanySelector(onChanged: _load),
              const SizedBox(height: 10),
              PeriodFilter(value: _period, onChanged: (p) {
                setState(() => _period = p);
                _load();
              }),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final c in ['all', ...Masters.instance.expenseCategories])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(c == 'all' ? 'All categories' : c),
                        selected: _category == c,
                        onSelected: (_) {
                          setState(() => _category = c);
                          _load();
                        },
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              if (_error != null && _data == null)
                ErrorView(message: _error!, onRetry: _load)
              else if (_data == null)
                const Padding(padding: EdgeInsets.all(40), child: LoadingView())
              else ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Total expenses', style: TextStyle(color: Colors.grey.shade700)),
                      Text(rupee(_data!['total']), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.red.shade700)),
                      if (byCat.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        for (final e in (byCat.entries.toList()..sort((a, b) => toD(b.value).compareTo(toD(a.value)))))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(children: [
                              SizedBox(width: 150, child: Text(e.key, overflow: TextOverflow.ellipsis)),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: toD(_data!['total']) == 0 ? 0 : toD(e.value) / toD(_data!['total']),
                                    minHeight: 8,
                                    color: Brand.gold,
                                    backgroundColor: Brand.goldLight,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox(width: 110, child: Text(rupee(e.value), textAlign: TextAlign.right)),
                            ]),
                          ),
                      ],
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                if (items.isEmpty)
                  const EmptyView(icon: Icons.account_balance_wallet_outlined, text: 'No expenses in this period')
                else
                  Card(
                    child: Column(children: [
                      for (final e in items) ...[
                        ListTile(
                          onTap: () => _edit(e),
                          leading: const CircleAvatar(backgroundColor: Brand.goldLight, child: Icon(Icons.north_east, color: Brand.navy, size: 20)),
                          title: Text('${e['category']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            [dmy(e['date']), e['mode'], e['paidTo'], e['note'], if (multi) Companies.instance.nameOf('${e['company']}')]
                                .where((x) => '${x ?? ''}'.isNotEmpty)
                                .join(' • '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(rupee(e['amount']), style: TextStyle(fontWeight: FontWeight.w700, color: Colors.red.shade700)),
                            IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(e)),
                          ]),
                        ),
                        const Divider(height: 1, indent: 72),
                      ],
                    ]),
                  ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
