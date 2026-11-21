import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/gst.dart' show paymentModes;
import 'common.dart';

/// "Payment In": customer pays an amount, the server settles the oldest unpaid
/// invoices first. Returns true when saved.
Future<bool> receivePayment(BuildContext context, {Map<String, dynamic>? customer}) async {
  var cust = customer;
  if (cust == null) {
    cust = await pickFromList(
      context,
      title: 'Payment from which customer?',
      load: (q) async => List<Map<String, dynamic>>.from((await Api.instance.get('/customers', {'q': q}) as List).map((e) => Map<String, dynamic>.from(e)))
          .where((c) => toD(c['balance']) > 0)
          .toList(),
      label: (c) => '${c['name']}',
      subtitle: (c) => 'Pending ${rupee(c['balance'])}',
    );
    if (cust == null || !context.mounted) return false;
  }
  final due = toD(cust['balance']);
  final amount = TextEditingController(text: due > 0 ? due.toStringAsFixed(2) : '');
  final note = TextEditingController();
  var date = today();
  var mode = paymentModes.first;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('Receive payment'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${cust!['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              if (due > 0) Text('Pending: ${rupee(due)}', style: TextStyle(color: Colors.red.shade700)),
              const SizedBox(height: 14),
              TextField(
                controller: amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: const InputDecoration(labelText: 'Amount received (₹)'),
              ),
              const SizedBox(height: 12),
              DateField(label: 'Date', value: date, onChanged: (v) => set(() => date = v)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: mode,
                decoration: const InputDecoration(labelText: 'Mode'),
                items: [for (final m in paymentModes) DropdownMenuItem(value: m, child: Text(m))],
                onChanged: (v) => mode = v ?? mode,
              ),
              const SizedBox(height: 12),
              TextField(controller: note, decoration: const InputDecoration(labelText: 'Note / UTR / Cheque no.')),
              const SizedBox(height: 10),
              Text('Adjusted against the oldest unpaid invoices first.', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
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
  if (ok != true || !context.mounted) return false;
  final r = await runBusy(
    context,
    () => Api.instance.post('/payments', {
      'customer': cust!['_id'],
      'amount': double.tryParse(amount.text) ?? 0,
      'date': date,
      'mode': mode,
      'note': note.text.trim(),
    }),
  );
  if (r == null || !context.mounted) return false;
  final parts = List<Map>.from(r['allocated']).map((a) => '#${a['invoiceNo']}: ${rupee(a['amount'])}').join(', ');
  showSnack(context, 'Payment saved — $parts');
  return true;
}
