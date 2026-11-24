import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api.dart';
import '../core/companies.dart';
import '../core/states.dart';
import '../widgets/common.dart';
import '../core/brand.dart';

const _palette = ['#000000', '#1F4E9C', '#0B7A75', '#2E7D32', '#B71C1C', '#6A1B9A', '#E65100', '#37474F'];

class CompanyFormScreen extends StatefulWidget {
  const CompanyFormScreen({super.key, this.id});
  final String? id;
  @override
  State<CompanyFormScreen> createState() => _CompanyFormScreenState();
}

class _CompanyFormScreenState extends State<CompanyFormScreen> {
  final _form = GlobalKey<FormState>();
  final _c = {
    for (final k in [
      'name', 'tagline', 'address', 'city', 'pincode', 'mobile', 'email', 'gstin', 'pan',
      'accountName', 'ifsc', 'accountNo', 'bankName', 'branch', 'upiId', 'terms', 'invoicePrefix', 'nextInvoiceNo', 'dueDays', 'qtPrefix', 'dcPrefix', 'cnPrefix', 'billPrefix', 'estPrefix', 'srPrefix', 'ndcPrefix', 'nextBillNo',
    ])
      k: TextEditingController(),
  };
  String _stateCode = '27';
  String _color = '#000000';
  bool _gstRegistered = true;
  String _logo = '', _signature = '';
  bool _loading = false, _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.id != null) {
      _load();
    } else {
      _c['nextInvoiceNo']!.text = '1';
      _c['qtPrefix']!.text = 'QT-';
      _c['dcPrefix']!.text = 'DC-';
      _c['cnPrefix']!.text = 'CN-';
      _c['billPrefix']!.text = 'B-';
      _c['estPrefix']!.text = 'EST-';
      _c['srPrefix']!.text = 'SR-';
      _c['ndcPrefix']!.text = 'NDC-';
      _c['nextBillNo']!.text = '1';
      _c['dueDays']!.text = '15';
      _c['terms']!.text = 'Goods once sold will not be taken back or exchanged\nAll disputes are subject to Mumbai jurisdiction only';
    }
  }

  @override
  void dispose() {
    for (final c in _c.values) {
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
      final c = Map<String, dynamic>.from(await Api.instance.get('/companies/${widget.id}'));
      final bank = Map<String, dynamic>.from(c['bank'] ?? {});
      for (final k in ['name', 'tagline', 'address', 'city', 'pincode', 'mobile', 'email', 'gstin', 'pan', 'invoicePrefix', 'nextInvoiceNo', 'dueDays']) {
        _c[k]!.text = '${c[k] ?? ''}';
      }
      for (final k in ['accountName', 'ifsc', 'accountNo', 'bankName', 'branch', 'upiId']) {
        _c[k]!.text = '${bank[k] ?? ''}';
      }
      final dp = Map<String, dynamic>.from(c['docPrefixes'] ?? {});
      _c['qtPrefix']!.text = '${dp['quotation'] ?? 'QT-'}';
      _c['dcPrefix']!.text = '${dp['challan'] ?? 'DC-'}';
      _c['cnPrefix']!.text = '${dp['credit_note'] ?? 'CN-'}';
      final np = Map<String, dynamic>.from(c['nonGstPrefixes'] ?? {});
      _c['billPrefix']!.text = '${np['invoice'] ?? 'B-'}';
      _c['estPrefix']!.text = '${np['quotation'] ?? 'EST-'}';
      _c['srPrefix']!.text = '${np['credit_note'] ?? 'SR-'}';
      _c['ndcPrefix']!.text = '${np['challan'] ?? 'NDC-'}';
      _c['nextBillNo']!.text = '${c['nextBillNo'] ?? 1}';
      _gstRegistered = c['gstRegistered'] != false;
      _c['terms']!.text = List<String>.from((c['terms'] ?? []).map((e) => '$e')).join('\n');
      _stateCode = '${c['stateCode'] ?? '27'}';
      _color = '${c['color'] ?? '#000000'}';
      _logo = '${c['logo'] ?? ''}';
      _signature = '${c['signature'] ?? ''}';
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<String?> _pickImage() async {
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 700, maxHeight: 700, imageQuality: 88);
      if (f == null) return null;
      final bytes = await f.readAsBytes();
      if (bytes.length > 1000000) {
        if (mounted) showSnack(context, 'Image is too large (max 1 MB)', error: true);
        return null;
      }
      final name = f.name.toLowerCase();
      final mime = f.mimeType ?? (name.endsWith('.png') ? 'image/png' : 'image/jpeg');
      return 'data:$mime;base64,${base64Encode(bytes)}';
    } catch (e) {
      if (mounted) showSnack(context, 'Could not open image: $e', error: true);
      return null;
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    String t(String k) => _c[k]!.text.trim();
    final body = {
      'name': t('name').toUpperCase(),
      'tagline': t('tagline'),
      'address': t('address'),
      'city': t('city'),
      'stateCode': _stateCode,
      'pincode': t('pincode'),
      'mobile': t('mobile'),
      'email': t('email'),
      'gstin': t('gstin').toUpperCase(),
      'pan': t('pan').toUpperCase(),
      'bank': {
        'accountName': t('accountName'),
        'ifsc': t('ifsc').toUpperCase(),
        'accountNo': t('accountNo'),
        'bankName': t('bankName'),
        'branch': t('branch'),
        'upiId': t('upiId'),
      },
      'terms': t('terms').split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      'invoicePrefix': t('invoicePrefix'),
      'docPrefixes': {'quotation': t('qtPrefix'), 'challan': t('dcPrefix'), 'credit_note': t('cnPrefix')},
      'gstRegistered': _gstRegistered,
      'nonGstPrefixes': {'invoice': t('billPrefix'), 'quotation': t('estPrefix'), 'credit_note': t('srPrefix'), 'challan': t('ndcPrefix')},
      'nextBillNo': int.tryParse(t('nextBillNo')) ?? 1,
      'nextInvoiceNo': int.tryParse(t('nextInvoiceNo')) ?? 1,
      'dueDays': int.tryParse(t('dueDays')) ?? 0,
      'color': _color,
      'logo': _logo,
      'signature': _signature,
    };
    try {
      final r = widget.id == null ? await Api.instance.post('/companies', body) : await Api.instance.put('/companies/${widget.id}', body);
      Companies.instance.invalidate('${r['_id']}');
      await Companies.instance.load();
      if (!mounted) return;
      showSnack(context, 'Company saved');
      context.pop(true);
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    Widget f(String k, String label, {int lines = 1, TextInputType? kb, String? Function(String?)? validator, String? helper, List<TextInputFormatter>? fmt}) =>
        TextFormField(
          controller: _c[k],
          maxLines: lines,
          keyboardType: kb,
          inputFormatters: fmt,
          validator: validator,
          decoration: InputDecoration(labelText: label, helperText: helper),
        );
    Widget pair(Widget a, Widget b) => wide
        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)])
        : Column(children: [a, const SizedBox(height: 12), b]);
    const gap = SizedBox(height: 12);

    return Scaffold(
      appBar: AppBar(title: Text(widget.id == null ? 'Add Company' : 'Edit Company')),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : Form(
                  key: _form,
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    Constrained(
                      maxWidth: 860,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        SectionCard(
                          title: 'Business',
                          child: Column(children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _gstRegistered,
                              onChanged: (v) => setState(() => _gstRegistered = v),
                              title: const Text('GST registered'),
                              subtitle: Text(_gstRegistered
                                  ? 'Can make bills with GST and without GST'
                                  : 'Only bills without GST (no tax, no GSTIN on the bill)'),
                            ),
                            f('name', 'Company name *', validator: (v) => (v ?? '').trim().isEmpty ? 'Name is required' : null),
                            gap,
                            f('tagline', 'Tagline (top right of invoice)', helper: 'e.g. PURE RO TREATED ICE CUBES'),
                            gap,
                            f('address', 'Address', lines: 2),
                            gap,
                            pair(f('city', 'City'), f('pincode', 'Pincode', kb: TextInputType.number)),
                            gap,
                            DropdownButtonFormField<String>(
                              key: ValueKey('st$_stateCode'),
                              initialValue: _stateCode,
                              isExpanded: true,
                              decoration: const InputDecoration(labelText: 'State'),
                              items: [for (final s in indianStates) DropdownMenuItem(value: s.$1, child: Text('${s.$1} - ${s.$2}'))],
                              onChanged: (v) => setState(() => _stateCode = v ?? _stateCode),
                            ),
                            gap,
                            pair(f('mobile', 'Mobile', kb: TextInputType.phone), f('email', 'Email', kb: TextInputType.emailAddress)),
                            gap,
                            pair(
                              f('gstin', 'GSTIN',
                                  fmt: [LengthLimitingTextInputFormatter(15)],
                                  validator: (v) {
                                    final g = (v ?? '').trim().toUpperCase();
                                    return g.isEmpty || gstinRegex.hasMatch(g) ? null : 'GSTIN looks wrong';
                                  }),
                              f('pan', 'PAN', fmt: [LengthLimitingTextInputFormatter(10)]),
                            ),
                          ]),
                        ),
                        SectionCard(
                          title: 'Logo, signature & colour',
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Wrap(spacing: 16, runSpacing: 16, children: [
                              _imageBox('Logo', _logo, () async {
                                final v = await _pickImage();
                                if (v != null) setState(() => _logo = v);
                              }, () => setState(() => _logo = '')),
                              _imageBox('Signature', _signature, () async {
                                final v = await _pickImage();
                                if (v != null) setState(() => _signature = v);
                              }, () => setState(() => _signature = '')),
                            ]),
                            const SizedBox(height: 16),
                            const Text('Invoice line colour'),
                            const SizedBox(height: 8),
                            Wrap(spacing: 10, children: [
                              for (final p in _palette)
                                GestureDetector(
                                  onTap: () => setState(() => _color = p),
                                  child: CircleAvatar(
                                    radius: 16,
                                    backgroundColor: Color(int.parse('FF${p.substring(1)}', radix: 16)),
                                    child: _color.toUpperCase() == p.toUpperCase() ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                                  ),
                                ),
                            ]),
                          ]),
                        ),
                        SectionCard(
                          title: 'Bank details (printed on invoice)',
                          child: Column(children: [
                            pair(f('accountName', 'Account name'), f('accountNo', 'Account number', kb: TextInputType.number)),
                            gap,
                            pair(f('ifsc', 'IFSC code'), f('bankName', 'Bank name')),
                            gap,
                            pair(f('branch', 'Branch / transfer mode'), f('upiId', 'UPI ID')),
                          ]),
                        ),
                        SectionCard(
                          title: 'Numbering & invoice settings',
                          child: Column(children: [
                            pair(
                              f('invoicePrefix', 'Invoice prefix (optional)', helper: 'e.g. OM/ — leave empty for plain numbers'),
                              f('nextInvoiceNo', 'Next invoice number', kb: TextInputType.number, fmt: [FilteringTextInputFormatter.digitsOnly]),
                            ),
                            gap,
                            Row(children: [
                              Expanded(child: f('qtPrefix', 'Quotation prefix')),
                              const SizedBox(width: 12),
                              Expanded(child: f('dcPrefix', 'Challan prefix')),
                              const SizedBox(width: 12),
                              Expanded(child: f('cnPrefix', 'Credit note prefix')),
                            ]),
                            gap,
                            const Align(alignment: Alignment.centerLeft, child: Text('Without GST series', style: TextStyle(fontWeight: FontWeight.w700))),
                            gap,
                            Row(children: [
                              Expanded(child: f('billPrefix', 'Bill prefix')),
                              const SizedBox(width: 12),
                              Expanded(child: f('nextBillNo', 'Next bill number', kb: TextInputType.number, fmt: [FilteringTextInputFormatter.digitsOnly])),
                            ]),
                            gap,
                            Row(children: [
                              Expanded(child: f('estPrefix', 'Estimate prefix')),
                              const SizedBox(width: 12),
                              Expanded(child: f('ndcPrefix', 'Challan prefix')),
                              const SizedBox(width: 12),
                              Expanded(child: f('srPrefix', 'Sales return prefix')),
                            ]),
                            gap,
                            f('dueDays', 'Payment due in (days)', kb: TextInputType.number, fmt: [FilteringTextInputFormatter.digitsOnly]),
                            gap,
                            f('terms', 'Terms and conditions (one per line)', lines: 4),
                          ]),
                        ),
                        FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save), label: const Text('Save Company')),
                        const SizedBox(height: 40),
                      ]),
                    ),
                  ]),
                ),
    );
  }

  Widget _imageBox(String label, String dataUrl, VoidCallback onPick, VoidCallback onClear) {
    final i = dataUrl.indexOf(',');
    final bytes = dataUrl.startsWith('data:image/') && i > 0 ? base64Decode(dataUrl.substring(i + 1)) : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      InkWell(
        onTap: onPick,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 170,
          height: 100,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Brand.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Brand.border),
          ),
          child: bytes == null
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add_photo_alternate_outlined, color: Colors.grey.shade600),
                  Text('Upload', style: TextStyle(color: Colors.grey.shade600)),
                ])
              : Padding(padding: const EdgeInsets.all(6), child: Image.memory(bytes, fit: BoxFit.contain)),
        ),
      ),
      if (bytes != null) TextButton(onPressed: onClear, child: const Text('Remove')),
    ]);
  }
}
