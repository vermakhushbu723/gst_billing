import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../core/api.dart';
import '../core/states.dart';
import '../widgets/common.dart';
import '../widgets/company_selector.dart';
import '../core/companies.dart';
import '../core/masters.dart';

class CustomerFormScreen extends StatefulWidget {
  const CustomerFormScreen({super.key, this.id});
  final String? id;
  @override
  State<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends State<CustomerFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _gstin = TextEditingController();
  final _pan = TextEditingController();
  final _billing = TextEditingController();
  final _shipName = TextEditingController();
  final _shipAddress = TextEditingController();
  final _opening = TextEditingController();
  String _stateCode = '27';
  bool _same = true;
  String? _company;
  String _category = '';
  bool _loading = false, _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Companies.instance.ensure().then((_) {
      if (mounted && widget.id == null) setState(() => _company = Companies.instance.defaultId);
    });
    if (widget.id != null) _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _gstin, _pan, _billing, _shipName, _shipAddress, _opening]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = await Api.instance.get('/customers/${widget.id}');
      _name.text = '${c['name'] ?? ''}';
      _phone.text = '${c['phone'] ?? ''}';
      _email.text = '${c['email'] ?? ''}';
      _gstin.text = '${c['gstin'] ?? ''}';
      _pan.text = '${c['pan'] ?? ''}';
      _billing.text = '${c['billingAddress'] ?? ''}';
      _shipName.text = '${c['shippingName'] ?? ''}';
      _shipAddress.text = '${c['shippingAddress'] ?? ''}';
      _opening.text = (c['openingBalance'] ?? 0) == 0 ? '' : '${c['openingBalance']}';
      _stateCode = '${c['stateCode'] ?? '27'}';
      _same = c['sameAsBilling'] != false;
      _company = c['company'] as String?;
      _category = '${c['category'] ?? ''}';
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  void _onGstin(String v) {
    final g = v.toUpperCase();
    if (g.length >= 2 && indianStates.any((s) => s.$1 == g.substring(0, 2))) {
      setState(() => _stateCode = g.substring(0, 2));
    }
    if (g.length >= 12) _pan.text = g.substring(2, 12);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final body = {
      'company': _company,
      'category': _category,
      'name': _name.text.trim(),
      'phone': _phone.text.trim(),
      'email': _email.text.trim(),
      'gstin': _gstin.text.trim().toUpperCase(),
      'pan': _pan.text.trim().toUpperCase(),
      'billingAddress': _billing.text.trim(),
      'sameAsBilling': _same,
      'shippingName': _same ? '' : _shipName.text.trim(),
      'shippingAddress': _same ? '' : _shipAddress.text.trim(),
      'stateCode': _stateCode,
      'openingBalance': double.tryParse(_opening.text) ?? 0,
    };
    try {
      final r = widget.id == null
          ? await Api.instance.post('/customers', body)
          : await Api.instance.put('/customers/${widget.id}', body);
      if (!mounted) return;
      showSnack(context, 'Customer saved');
      context.pop(Map<String, dynamic>.from(r));
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    Widget pair(Widget a, Widget b) => wide
        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)])
        : Column(children: [a, const SizedBox(height: 12), b]);
    return Scaffold(
      appBar: AppBar(title: Text(widget.id == null ? 'Add Customer' : 'Edit Customer')),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : Form(
                  key: _form,
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    Constrained(
                      maxWidth: 820,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        SectionCard(
                          title: 'Customer details',
                          child: Column(children: [
                            CompanyField(value: _company, enabled: widget.id == null, onChanged: (v) => setState(() => _company = v)),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _name,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(labelText: 'Name / Business name *'),
                              validator: (v) => (v ?? '').trim().isEmpty ? 'Name is required' : null,
                            ),
                            const SizedBox(height: 12),
                            pair(
                              TextFormField(
                                controller: _phone,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(labelText: 'Mobile (WhatsApp)', prefixIcon: Icon(Icons.phone)),
                              ),
                              TextFormField(
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                              ),
                            ),
                          ]),
                        ),
                        SectionCard(
                          title: 'Party category',
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('cat-$_category'),
                            initialValue: _category.isEmpty ? null : _category,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'Category (optional)', helperText: 'Edit the list in Units, GST & Lists'),
                            items: [
                              for (final c in {...Masters.instance.partyCategories, if (_category.isNotEmpty) _category})
                                DropdownMenuItem(value: c, child: Text(c)),
                            ],
                            onChanged: (v) => setState(() => _category = v ?? ''),
                          ),
                        ),
                        SectionCard(
                          title: 'GST details',
                          child: Column(children: [
                            pair(
                              TextFormField(
                                controller: _gstin,
                                textCapitalization: TextCapitalization.characters,
                                inputFormatters: [LengthLimitingTextInputFormatter(15)],
                                decoration: const InputDecoration(labelText: 'GSTIN', helperText: 'Leave empty for unregistered (B2C)'),
                                onChanged: _onGstin,
                                validator: (v) {
                                  final g = (v ?? '').trim().toUpperCase();
                                  return g.isEmpty || gstinRegex.hasMatch(g) ? null : 'GSTIN looks wrong (15 characters)';
                                },
                              ),
                              TextFormField(
                                controller: _pan,
                                textCapitalization: TextCapitalization.characters,
                                inputFormatters: [LengthLimitingTextInputFormatter(10)],
                                decoration: const InputDecoration(labelText: 'PAN Number'),
                              ),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              key: ValueKey('st$_stateCode'),
                              initialValue: _stateCode,
                              isExpanded: true,
                              decoration: const InputDecoration(labelText: 'State (place of supply)'),
                              items: [for (final s in indianStates) DropdownMenuItem(value: s.$1, child: Text('${s.$1} - ${s.$2}'))],
                              onChanged: (v) => setState(() => _stateCode = v ?? _stateCode),
                            ),
                          ]),
                        ),
                        SectionCard(
                          title: 'Address',
                          child: Column(children: [
                            TextFormField(
                              controller: _billing,
                              maxLines: 3,
                              decoration: const InputDecoration(labelText: 'Billing address (with city, state, pincode)'),
                            ),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              value: _same,
                              onChanged: (v) => setState(() => _same = v ?? true),
                              title: const Text('Shipping address same as billing'),
                            ),
                            if (!_same) ...[
                              TextFormField(controller: _shipName, decoration: const InputDecoration(labelText: 'Ship to name')),
                              const SizedBox(height: 12),
                              TextFormField(controller: _shipAddress, maxLines: 3, decoration: const InputDecoration(labelText: 'Shipping address')),
                            ],
                          ]),
                        ),
                        SectionCard(
                          title: 'Opening balance',
                          child: TextFormField(
                            controller: _opening,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                            decoration: const InputDecoration(labelText: 'Old pending amount (₹)', helperText: 'Amount the customer already owed before using this app'),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: const Icon(Icons.save),
                          label: const Text('Save Customer'),
                        ),
                        const SizedBox(height: 40),
                      ]),
                    ),
                  ]),
                ),
    );
  }
}
