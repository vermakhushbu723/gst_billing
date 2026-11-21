import 'package:flutter/material.dart';

import '../core/format.dart';

void showSnack(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? Colors.red.shade700 : null,
    ));
}

Future<bool> confirm(BuildContext context, String title, String message, {String ok = 'Yes', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: Colors.red.shade700) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r == true;
}

/// Runs [task] with a blocking progress dialog; shows errors as a snackbar.
Future<T?> runBusy<T>(BuildContext context, Future<T> Function() task, {String? success}) async {
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(canPop: false, child: Center(child: CircularProgressIndicator())),
  );
  try {
    final r = await task();
    nav.pop();
    if (success != null && context.mounted) showSnack(context, success);
    return r;
  } catch (e) {
    nav.pop();
    if (context.mounted) showSnack(context, '$e', error: true);
    return null;
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off, size: 48, color: Colors.grey.shade500),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
          ]),
        ),
      );
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ]),
        ),
      );
}

/// Centers content with a max width so forms look right on the web.
class Constrained extends StatelessWidget {
  const Constrained({super.key, required this.child, this.maxWidth = 860});
  final Widget child;
  final double maxWidth;
  @override
  Widget build(BuildContext context) =>
      Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child));
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, required this.child, this.trailing, this.padding = const EdgeInsets.all(16)});
  final String? title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: padding,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (title != null) ...[
              Row(children: [
                Expanded(child: Text(title!, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                ?trailing,
              ]),
              const SizedBox(height: 12),
            ],
            child,
          ]),
        ),
      );
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final String? status;
  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'paid' => ('PAID', Colors.green.shade700),
      'partial' => ('PARTIAL', Colors.orange.shade800),
      'cancelled' => ('CANCELLED', Colors.grey.shade600),
      _ => ('UNPAID', Colors.red.shade700),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, required this.icon, required this.color, this.sub});
  final String label, value;
  final String? sub;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                ),
                if (sub != null) Text(sub!, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
              ]),
            ),
          ]),
        ),
      );
}

/// One invoice row used in lists.
class InvoiceTile extends StatelessWidget {
  const InvoiceTile({super.key, required this.inv, required this.onTap, this.showCompany = true, this.byInvoiceNo = false});
  final Map inv;
  final VoidCallback onTap;
  final bool showCompany;

  /// Title "Invoice #290" instead of the customer name (customer ledger).
  final bool byInvoiceNo;
  @override
  Widget build(BuildContext context) {
    final cancelled = inv['status'] == 'cancelled';
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: const Icon(Icons.receipt_long, size: 20),
      ),
      title: Text(byInvoiceNo ? 'Invoice #${invNo(inv)}' : '${inv['billTo']?['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.w600, decoration: cancelled ? TextDecoration.lineThrough : null)),
      subtitle: Text(
        '${byInvoiceNo ? '' : '#${invNo(inv)} • '}${dmy(inv['invoiceDate'])}${showCompany ? ' • ${inv['companySnapshot']?['name'] ?? ''}' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(rupee(inv['total']), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        StatusChip(inv['status']),
      ]),
    );
  }
}

/// Searchable picker dialog for customers/products.
Future<Map<String, dynamic>?> pickFromList(
  BuildContext context, {
  required String title,
  required Future<List<Map<String, dynamic>>> Function(String q) load,
  required String Function(Map<String, dynamic>) label,
  String Function(Map<String, dynamic>)? subtitle,
  String? addLabel,
  Future<Map<String, dynamic>?> Function()? onAdd,
}) async {
  final r = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => _PickerDialog(title: title, load: load, label: label, subtitle: subtitle, addLabel: addLabel, onAdd: onAdd),
  );
  // "Add new" closes the dialog first, so the form page opens on top.
  if (r != null && r['__add__'] == true) return onAdd?.call();
  return r;
}

class _PickerDialog extends StatefulWidget {
  const _PickerDialog({required this.title, required this.load, required this.label, this.subtitle, this.addLabel, this.onAdd});
  final String title;
  final Future<List<Map<String, dynamic>>> Function(String q) load;
  final String Function(Map<String, dynamic>) label;
  final String Function(Map<String, dynamic>)? subtitle;
  final String? addLabel;
  final Future<Map<String, dynamic>?> Function()? onAdd;
  @override
  State<_PickerDialog> createState() => _PickerDialogState();
}

class _PickerDialogState extends State<_PickerDialog> {
  List<Map<String, dynamic>>? _items;
  String? _error;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final q = _q;
      final r = await widget.load(q);
      if (mounted && q == _q) setState(() => _items = r);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(children: [
              Expanded(child: Text(widget.title, style: Theme.of(context).textTheme.titleLarge)),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search'),
              onChanged: (v) {
                _q = v;
                _load();
              },
            ),
          ),
          if (widget.onAdd != null)
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: Text(widget.addLabel ?? 'Add new'),
              onTap: () => Navigator.pop(context, <String, dynamic>{'__add__': true}),
            ),
          const Divider(height: 1),
          Expanded(
            child: _error != null
                ? Center(child: Text(_error!))
                : _items == null
                    ? const LoadingView()
                    : _items!.isEmpty
                        ? const Center(child: Text('Nothing found'))
                        : ListView.separated(
                            itemCount: _items!.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final it = _items![i];
                              final sub = widget.subtitle?.call(it) ?? '';
                              return ListTile(
                                title: Text(widget.label(it)),
                                subtitle: sub.isEmpty ? null : Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis),
                                onTap: () => Navigator.pop(context, it),
                              );
                            },
                          ),
          ),
        ]),
      ),
    );
  }
}

/// A date field that opens a date picker. Value is YYYY-MM-DD.
class DateField extends StatelessWidget {
  const DateField({super.key, required this.label, required this.value, required this.onChanged, this.clearable = false});
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final bool clearable;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: parseYmd(value) ?? DateTime.now(),
            firstDate: DateTime(2015),
            lastDate: DateTime(2100),
          );
          if (d != null) onChanged(ymdOf(d));
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: clearable && value.isNotEmpty
                ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => onChanged(''))
                : const Icon(Icons.calendar_today, size: 18),
          ),
          child: Text(value.isEmpty ? '—' : dmy(value)),
        ),
      );
}
