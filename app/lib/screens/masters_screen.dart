import 'package:flutter/material.dart';

import '../core/auth.dart';
import '../core/brand.dart';
import '../core/format.dart';
import '../core/masters.dart';
import '../widgets/common.dart';

/// Editable lists used across the app: units, GST rates, payment modes, expense categories.
class MastersScreen extends StatefulWidget {
  const MastersScreen({super.key});
  @override
  State<MastersScreen> createState() => _MastersScreenState();
}

class _MastersScreenState extends State<MastersScreen> {
  bool _loading = true;
  String? _error;

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
      await Masters.instance.load();
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save(String key, List<dynamic> values) async {
    await runBusy(context, () => Masters.instance.save({key: values}), success: 'Saved');
    if (mounted) setState(() {});
  }

  Future<void> _add(String key, String title, List<dynamic> current, {bool number = false}) async {
    final c = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add $title'),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: number ? TextCapitalization.none : TextCapitalization.words,
          keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
          decoration: InputDecoration(labelText: title, suffixText: number ? '%' : null),
          onSubmitted: (t) => Navigator.pop(ctx, t),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Add')),
        ],
      ),
    );
    final t = (v ?? '').trim();
    if (t.isEmpty) return;
    if (number) {
      final n = double.tryParse(t);
      if (n == null || n < 0 || n > 100) {
        if (mounted) showSnack(context, 'Enter a rate between 0 and 100', error: true);
        return;
      }
      await _save(key, [...current, n]);
    } else {
      await _save(key, [...current, key == 'units' ? t.toUpperCase() : t]);
    }
  }

  Future<void> _remove(String key, List<dynamic> current, dynamic value) async {
    if (current.length <= 1) return showSnack(context, 'Keep at least one value', error: true);
    await _save(key, current.where((e) => e != value).toList());
  }

  @override
  Widget build(BuildContext context) {
    final admin = AuthState.instance.isAdmin;
    final m = Masters.instance;
    Widget section(String key, String title, String help, IconData icon, List<dynamic> values, String Function(dynamic) label, {bool number = false}) =>
        SectionCard(
          title: title,
          trailing: admin
              ? TextButton.icon(onPressed: () => _add(key, title, values, number: number), icon: const Icon(Icons.add), label: const Text('Add'))
              : null,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(help, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final v in values)
                InputChip(
                  avatar: Icon(icon, size: 16, color: Brand.teal),
                  label: Text(label(v)),
                  backgroundColor: Brand.tealLight,
                  onDeleted: admin ? () => _remove(key, values, v) : null,
                ),
            ]),
          ]),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Masters')),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Constrained(
                    maxWidth: 860,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (!admin)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text('Only admin can change these lists.', style: TextStyle(color: Colors.grey.shade700)),
                        ),
                      section('units', 'Units', 'Shown in products and invoice items (KGS, NOS, BAGS…).', Icons.straighten, m.units, (v) => '$v'),
                      section('gstRates', 'GST rates', 'Rates you can pick for products and invoice items.', Icons.percent, m.gstRates, (v) => pct(v), number: true),
                      section('paymentModes', 'Payment modes', 'Used when receiving payments and recording expenses.', Icons.payments_outlined, m.paymentModes, (v) => '$v'),
                      section('expenseCategories', 'Expense categories', 'Categories for the Expenses screen and P&L report.', Icons.category_outlined, m.expenseCategories, (v) => '$v'),
                    ]),
                  ),
                ]),
    );
  }
}
