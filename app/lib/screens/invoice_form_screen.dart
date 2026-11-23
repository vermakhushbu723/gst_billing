import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../core/api.dart';
import '../core/companies.dart';
import '../core/docs.dart';
import '../core/format.dart';
import '../core/gst.dart';
import '../core/states.dart';
import '../widgets/common.dart';
import '../core/brand.dart';

class _Line {
  _Line({Map? from}) {
    if (from != null) {
      productId = from['product'] is String ? from['product'] : null;
      name.text = '${from['name'] ?? ''}';
      description.text = '${from['description'] ?? ''}';
      hsn.text = '${from['hsn'] ?? ''}';
      unit = '${from['unit'] ?? 'KGS'}';
      qty.text = from['qty'] == null ? '' : qtyStr(from['qty']);
      rate.text = from['rate'] == null ? '' : '${from['rate']}';
      gstRate = toD(from['gstRate'] ?? 5);
    }
  }
  String? productId;
  final name = TextEditingController();
  final description = TextEditingController();
  final hsn = TextEditingController();
  final qty = TextEditingController();
  final rate = TextEditingController();
  String unit = 'KGS';
  double gstRate = 5;

  double get qtyV => double.tryParse(qty.text.replaceAll(',', '')) ?? 0;
  double get rateV => double.tryParse(rate.text.replaceAll(',', '')) ?? 0;

  void dispose() {
    for (final c in [name, description, hsn, qty, rate]) {
      c.dispose();
    }
  }

  Map<String, dynamic> toJson() => {
        if (productId != null) 'product': productId,
        'name': name.text.trim(),
        'description': description.text.trim(),
        'hsn': hsn.text.trim(),
        'unit': unit,
        'qty': qtyV,
        'rate': rateV,
        'gstRate': gstRate,
      };
}

class InvoiceFormScreen extends StatefulWidget {
  const InvoiceFormScreen({super.key, this.invoiceId, this.customerId, this.copyFromId, this.docType = DocType.invoice});
  final DocType docType;
  final String? invoiceId;
  final String? customerId;
  final String? copyFromId;
  @override
  State<InvoiceFormScreen> createState() => _InvoiceFormScreenState();
}

class _InvoiceFormScreenState extends State<InvoiceFormScreen> {
  bool get _editing => widget.invoiceId != null;
  bool _loading = true, _saving = false;
  String? _error;

  late DocType _type = widget.docType;
  String _prefix = '';
  final _refInvoice = TextEditingController();
  String? _companyId;
  Map<String, dynamic>? _customer;
  final _invoiceNo = TextEditingController();
  String _invoiceDate = today();
  String _dueDate = '';
  int _dueDays = 15;
  String _posCode = '27';
  final List<_Line> _lines = [];
  bool _customShip = false;
  final _shipName = TextEditingController();
  final _shipAddress = TextEditingController();
  final _vehicle = TextEditingController();
  final _po = TextEditingController();
  final _notes = TextEditingController();
  final _received = TextEditingController();
  String _mode = 'Cash';

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    for (final c in [_refInvoice, _invoiceNo, _shipName, _shipAddress, _vehicle, _po, _notes, _received]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Companies.instance.ensure();
      if (_editing || widget.copyFromId != null) {
        final inv = Map<String, dynamic>.from(await Api.instance.get('/invoices/${widget.invoiceId ?? widget.copyFromId}'));
        _companyId = inv['company'];
        _type = DocType.of(inv['docType']);
        _refInvoice.text = '${inv['refInvoiceNo'] ?? ''}';
        _customer = Map<String, dynamic>.from(await Api.instance.get('/customers/${inv['customer']}'));
        _posCode = '${inv['placeOfSupplyCode'] ?? _customer!['stateCode']}';
        for (final it in List<Map>.from(inv['items'])) {
          _lines.add(_Line(from: it));
        }
        final ship = Map<String, dynamic>.from(inv['shipTo'] ?? {});
        _vehicle.text = '${inv['vehicleNo'] ?? ''}';
        _po.text = '${inv['poNumber'] ?? ''}';
        _notes.text = '${inv['notes'] ?? ''}';
        if (_editing) {
          _invoiceNo.text = '${inv['invoiceNo']}';
          _prefix = '${inv['invoicePrefix'] ?? ''}';
          _invoiceDate = '${inv['invoiceDate']}';
          _dueDate = '${inv['dueDate'] ?? ''}';
          final cust = _customer!;
          final defName = cust['sameAsBilling'] == false && '${cust['shippingName']}'.isNotEmpty ? cust['shippingName'] : cust['name'];
          final defAddr = cust['sameAsBilling'] == false && '${cust['shippingAddress']}'.isNotEmpty ? cust['shippingAddress'] : cust['billingAddress'];
          if (ship['name'] != defName || ship['address'] != defAddr) {
            _customShip = true;
            _shipName.text = '${ship['name'] ?? ''}';
            _shipAddress.text = '${ship['address'] ?? ''}';
          }
        } else {
          await _loadNextNumber();
        }
      } else {
        _companyId = Companies.instance.defaultId;
        if (widget.customerId != null) {
          _customer = Map<String, dynamic>.from(await Api.instance.get('/customers/${widget.customerId}'));
          _posCode = '${_customer!['stateCode']}';
        }
        _lines.add(_Line());
        await _loadNextNumber();
      }
      if (_companyId == null) throw ApiException(0, 'Add a company first (Companies screen)');
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _loadNextNumber() async {
    if (_companyId == null) return;
    final r = await Api.instance.get('/invoices/next-number', {'company': _companyId, 'type': _type.key});
    _invoiceNo.text = '${r['invoiceNo']}';
    _prefix = '${r['prefix'] ?? ''}';
    _dueDays = (r['dueDays'] as num?)?.toInt() ?? 15;
    _setDueFromDays();
  }

  void _setDueFromDays() {
    final d = parseYmd(_invoiceDate);
    _dueDate = d == null || _dueDays <= 0 || _type.secondDateLabel == null ? '' : ymdOf(d.add(Duration(days: _dueDays)));
  }

  Map<String, dynamic>? get _company => Companies.instance.byId(_companyId);
  bool get _intra => (_company?['stateCode'] ?? '27') == _posCode;

  InvoiceCalc get _calc => calcInvoice(
        [for (final l in _lines) (qty: l.qtyV, rate: l.rateV, gstRate: l.gstRate)],
        intraState: _intra,
      );

  Future<void> _pickCustomer() async {
    final c = await pickFromList(
      context,
      title: 'Select customer',
      load: (q) async => List<Map<String, dynamic>>.from(
          (await Api.instance.get('/customers', {'q': q, 'company': _companyId}) as List).map((e) => Map<String, dynamic>.from(e))),
      label: (c) => '${c['name']}',
      subtitle: (c) => [c['gstin'], c['phone']].where((e) => '${e ?? ''}'.isNotEmpty).join(' • '),
      addLabel: 'Add new customer',
      onAdd: () async {
        final r = await context.push<Map<String, dynamic>>('/customers/new');
        return r;
      },
    );
    if (c != null) {
      setState(() {
        _customer = c;
        _posCode = '${c['stateCode'] ?? _posCode}';
      });
    }
  }

  Future<void> _pickProduct(_Line line) async {
    final p = await pickFromList(
      context,
      title: 'Select product',
      load: (q) async => List<Map<String, dynamic>>.from(
          (await Api.instance.get('/products', {'q': q, 'company': _companyId}) as List).map((e) => Map<String, dynamic>.from(e))),
      label: (p) => '${p['name']}',
      subtitle: (p) => '${rupee(p['rate'])} / ${p['unit']} • GST ${pct(p['gstRate'])}${'${p['hsn']}'.isNotEmpty ? ' • HSN ${p['hsn']}' : ''}',
      addLabel: 'Add new product',
      onAdd: () => context.push<Map<String, dynamic>>('/products/new'),
    );
    if (p != null) {
      setState(() {
        line.productId = p['_id'];
        line.name.text = '${p['name']}';
        line.description.text = '${p['description'] ?? ''}';
        line.hsn.text = '${p['hsn'] ?? ''}';
        line.unit = '${p['unit'] ?? 'KGS'}';
        line.rate.text = '${p['rate'] ?? ''}';
        line.gstRate = toD(p['gstRate']);
      });
    }
  }

  Future<void> _save() async {
    if (_customer == null) return showSnack(context, 'Select a customer', error: true);
    final lines = _lines.where((l) => l.name.text.trim().isNotEmpty || l.qtyV > 0).toList();
    if (lines.isEmpty) return showSnack(context, 'Add at least one item', error: true);
    for (final l in lines) {
      if (l.name.text.trim().isEmpty) return showSnack(context, 'Item name is missing', error: true);
      if (l.qtyV <= 0) return showSnack(context, 'Enter quantity for ${l.name.text}', error: true);
    }
    final body = <String, dynamic>{
      'docType': _type.key,
      'refInvoiceNo': _refInvoice.text.trim(),
      'company': _companyId,
      'customer': _customer!['_id'],
      'invoiceNo': int.tryParse(_invoiceNo.text.trim()),
      'invoiceDate': _invoiceDate,
      'dueDate': _dueDate,
      'placeOfSupplyCode': _posCode,
      'items': [for (final l in lines) l.toJson()],
      'shipTo': _customShip ? {'name': _shipName.text.trim(), 'address': _shipAddress.text.trim()} : null,
      'vehicleNo': _vehicle.text.trim(),
      'poNumber': _po.text.trim(),
      'notes': _notes.text.trim(),
      if (!_editing && _type.isInvoice) 'receivedAmount': double.tryParse(_received.text.replaceAll(',', '')) ?? 0,
      if (!_editing && _type.isInvoice) 'paymentMode': _mode,
    };
    setState(() => _saving = true);
    try {
      final r = _editing
          ? await Api.instance.put('/invoices/${widget.invoiceId}', body)
          : await Api.instance.post('/invoices', body);
      Companies.instance.load();
      if (!mounted) return;
      showSnack(context, _editing ? '${_type.label} updated' : '${_type.label} ${invNo(r)} saved');
      if (_editing) {
        context.pop(true);
      } else {
        context.pushReplacement('/invoices/${r['_id']}');
      }
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${_editing ? 'Edit' : 'New'} ${_type.label}'),
        actions: [
          if (!_loading && _error == null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save),
                label: const Text('Save'),
              ),
            ),
        ],
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _init)
              : _form(),
    );
  }

  Widget _form() {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Constrained(
          maxWidth: 980,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionCard(
              title: '${_type.label} details',
              child: Column(children: [
                DropdownButtonFormField<String>(
                  initialValue: _companyId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Company (billing from)', prefixIcon: Icon(Icons.business)),
                  items: [
                    for (final c in Companies.instance.list)
                      DropdownMenuItem(value: c['_id'] as String, child: Text('${c['name']}', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: _editing
                      ? null
                      : (v) async {
                          setState(() {
                            _companyId = v;
                            // customers belong to one company
                            if (_customer != null && _customer!['company'] != null && _customer!['company'] != v) _customer = null;
                          });
                          try {
                            await _loadNextNumber();
                          } catch (_) {}
                          if (mounted) setState(() {});
                        },
                ),
                const SizedBox(height: 12),
                _responsiveRow(wide, [
                  TextFormField(
                    controller: _invoiceNo,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: '${_type.label} No.',
                      prefixText: _prefix,
                    ),
                  ),
                  DateField(
                    label: _type.isInvoice ? 'Invoice date' : 'Date',
                    value: _invoiceDate,
                    onChanged: (v) => setState(() {
                      _invoiceDate = v;
                      if (!_editing) _setDueFromDays();
                    }),
                  ),
                  if (_type.secondDateLabel != null)
                    DateField(
                      label: _type.secondDateLabel!.replaceAll(':', ''),
                      value: _dueDate,
                      clearable: true,
                      onChanged: (v) => setState(() => _dueDate = v),
                    ),
                  if (_type == DocType.creditNote)
                    TextFormField(controller: _refInvoice, decoration: const InputDecoration(labelText: 'Against Invoice No.')),
                ]),
              ]),
            ),
            SectionCard(
              title: 'Bill to',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                InkWell(
                  onTap: _editing ? null : _pickCustomer,
                  borderRadius: BorderRadius.circular(10),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Customer',
                      prefixIcon: const Icon(Icons.person_outline),
                      suffixIcon: _editing ? null : const Icon(Icons.arrow_drop_down),
                    ),
                    child: _customer == null
                        ? Text('Tap to select customer', style: TextStyle(color: Colors.grey.shade600))
                        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${_customer!['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                            if ('${_customer!['billingAddress'] ?? ''}'.isNotEmpty)
                              Text('${_customer!['billingAddress']}', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                            if ('${_customer!['gstin'] ?? ''}'.isNotEmpty)
                              Text('GSTIN: ${_customer!['gstin']}', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                          ]),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey('pos$_posCode'),
                  initialValue: indianStates.any((s) => s.$1 == _posCode) ? _posCode : null,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Place of supply',
                    helperText: _intra ? 'Same state: CGST + SGST' : 'Other state: IGST',
                  ),
                  items: [for (final s in indianStates) DropdownMenuItem(value: s.$1, child: Text('${s.$1} - ${s.$2}'))],
                  onChanged: (v) => setState(() => _posCode = v ?? _posCode),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _customShip,
                  onChanged: (v) => setState(() => _customShip = v),
                  title: const Text('Different ship-to address for this invoice'),
                ),
                if (_customShip) ...[
                  TextField(controller: _shipName, decoration: const InputDecoration(labelText: 'Ship to name')),
                  const SizedBox(height: 10),
                  TextField(controller: _shipAddress, maxLines: 3, decoration: const InputDecoration(labelText: 'Ship to address')),
                ],
              ]),
            ),
            SectionCard(
              title: 'Items',
              trailing: TextButton.icon(
                onPressed: () => setState(() => _lines.add(_Line())),
                icon: const Icon(Icons.add),
                label: const Text('Add item'),
              ),
              child: Column(children: [
                for (var i = 0; i < _lines.length; i++) _lineCard(i, wide),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _lines.add(_Line())),
                  icon: const Icon(Icons.add),
                  label: const Text('Add another item'),
                ),
              ]),
            ),
            _summaryCard(),
            SectionCard(
              title: 'Other details (optional)',
              child: Column(children: [
                _responsiveRow(wide, [
                  TextField(controller: _po, decoration: const InputDecoration(labelText: 'PO / Order No.')),
                  TextField(controller: _vehicle, decoration: const InputDecoration(labelText: 'Vehicle No.')),
                ]),
                const SizedBox(height: 12),
                TextField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes (printed on invoice)')),
              ]),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save),
              label: Text(_editing ? 'Update ${_type.label}' : 'Save ${_type.label}'),
            ),
            const SizedBox(height: 40),
          ]),
        ),
      ],
    );
  }

  Widget _responsiveRow(bool wide, List<Widget> children) {
    if (!wide) {
      return Column(children: [
        for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 12), children[i]],
      ]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: 12), Expanded(child: children[i])],
    ]);
  }

  Widget _lineCard(int i, bool wide) {
    final l = _lines[i];
    final calc = calcLine(l.qtyV, l.rateV, l.gstRate);
    const numKb = TextInputType.numberWithOptions(decimal: true);
    final decimals = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
    final nameField = TextField(
      controller: l.name,
      decoration: InputDecoration(
        labelText: 'Item name',
        suffixIcon: IconButton(tooltip: 'Pick product', icon: const Icon(Icons.inventory_2_outlined), onPressed: () => _pickProduct(l)),
      ),
      onChanged: (_) => setState(() {}),
    );
    final qty = TextField(
      controller: l.qty,
      keyboardType: numKb,
      inputFormatters: decimals,
      decoration: const InputDecoration(labelText: 'Qty'),
      onChanged: (_) => setState(() {}),
    );
    final unit = DropdownButtonFormField<String>(
      key: ValueKey('u${identityHashCode(l)}${l.unit}'),
      initialValue: units.contains(l.unit) ? l.unit : null,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Unit'),
      items: [
        for (final u in {...units, if (!units.contains(l.unit)) l.unit}) DropdownMenuItem(value: u, child: Text(u)),
      ],
      onChanged: (v) => setState(() => l.unit = v ?? l.unit),
    );
    final rate = TextField(
      controller: l.rate,
      keyboardType: numKb,
      inputFormatters: decimals,
      decoration: const InputDecoration(labelText: 'Rate (₹)'),
      onChanged: (_) => setState(() {}),
    );
    final gst = DropdownButtonFormField<double>(
      key: ValueKey('g${identityHashCode(l)}${l.gstRate}'),
      initialValue: gstRates.contains(l.gstRate) ? l.gstRate : null,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'GST'),
      items: [for (final g in {...gstRates, l.gstRate}) DropdownMenuItem(value: g, child: Text(pct(g)))],
      onChanged: (v) => setState(() => l.gstRate = v ?? l.gstRate),
    );
    final hsn = TextField(controller: l.hsn, decoration: const InputDecoration(labelText: 'HSN/SAC'));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Brand.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Brand.border),
      ),
      child: Column(children: [
        Row(children: [
          CircleAvatar(radius: 12, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
          const SizedBox(width: 10),
          Expanded(child: nameField),
          if (_lines.length > 1)
            IconButton(
              tooltip: 'Remove',
              icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
              onPressed: () => setState(() => _lines.removeAt(i).dispose()),
            ),
        ]),
        const SizedBox(height: 10),
        if (wide)
          Row(children: [
            Expanded(flex: 2, child: qty),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: unit),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: rate),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: gst),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: hsn),
          ])
        else ...[
          Row(children: [Expanded(child: qty), const SizedBox(width: 8), Expanded(child: unit)]),
          const SizedBox(height: 10),
          Row(children: [Expanded(child: rate), const SizedBox(width: 8), Expanded(child: gst)]),
          const SizedBox(height: 10),
          hsn,
        ],
        const SizedBox(height: 8),
        Row(children: [
          Text('Taxable ${money(calc.taxable)}  •  Tax ${money(calc.tax)}', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
          const Spacer(),
          Text(rupee(calc.amount), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ]),
      ]),
    );
  }

  Widget _summaryCard() {
    final c = _calc;
    Widget row(String l, String v, {bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(l, style: TextStyle(fontWeight: strong ? FontWeight.w700 : null, fontSize: strong ? 17 : 14))),
            Text(v, style: TextStyle(fontWeight: strong ? FontWeight.w800 : FontWeight.w500, fontSize: strong ? 17 : 14)),
          ]),
        );
    return SectionCard(
      title: 'Summary',
      child: Column(children: [
        row('Total quantity', qtyStr(c.totalQty)),
        row('Taxable amount', rupee(c.taxable)),
        for (final t in c.rows)
          if (_intra) ...[
            row('CGST @${pct(t.rate / 2)}', rupee(t.cgst)),
            row('SGST @${pct(t.rate / 2)}', rupee(t.sgst)),
          ] else
            row('IGST @${pct(t.rate)}', rupee(t.igst)),
        const Divider(),
        row('Total amount', rupee(c.total), strong: true),
        Align(
          alignment: Alignment.centerRight,
          child: Text(amountInWords(c.total), textAlign: TextAlign.right, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
        ),
        if (!_editing && _type.isInvoice) ...[
          const Divider(height: 24),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _received,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: InputDecoration(
                  labelText: 'Amount received now (₹)',
                  suffixIcon: TextButton(
                    onPressed: () => setState(() => _received.text = c.total.toStringAsFixed(2)),
                    child: const Text('Full'),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 130,
              child: DropdownButtonFormField<String>(
                initialValue: _mode,
                decoration: const InputDecoration(labelText: 'Mode'),
                items: [for (final m in paymentModes) DropdownMenuItem(value: m, child: Text(m))],
                onChanged: (v) => setState(() => _mode = v ?? _mode),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}

