import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/gst.dart';
import '../widgets/common.dart';

class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key, this.id});
  final String? id;
  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _hsn = TextEditingController();
  final _rate = TextEditingController();
  String _unit = 'KGS';
  double _gst = 5;
  bool _loading = false, _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.id != null) _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _desc, _hsn, _rate]) {
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
      final list = List<Map>.from(await Api.instance.get('/products'));
      final p = list.firstWhere((e) => e['_id'] == widget.id, orElse: () => throw ApiException(404, 'Product not found'));
      _name.text = '${p['name']}';
      _desc.text = '${p['description'] ?? ''}';
      _hsn.text = '${p['hsn'] ?? ''}';
      _rate.text = '${p['rate'] ?? ''}';
      _unit = '${p['unit'] ?? 'KGS'}';
      _gst = toD(p['gstRate']);
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final body = {
      'name': _name.text.trim(),
      'description': _desc.text.trim(),
      'hsn': _hsn.text.trim(),
      'unit': _unit,
      'rate': double.tryParse(_rate.text) ?? 0,
      'gstRate': _gst,
    };
    try {
      final r = widget.id == null ? await Api.instance.post('/products', body) : await Api.instance.put('/products/${widget.id}', body);
      if (!mounted) return;
      showSnack(context, 'Product saved');
      context.pop(Map<String, dynamic>.from(r));
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.id == null ? 'Add Product' : 'Edit Product')),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : Form(
                  key: _form,
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    Constrained(
                      maxWidth: 640,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        SectionCard(
                          child: Column(children: [
                            TextFormField(
                              controller: _name,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(labelText: 'Product name *'),
                              validator: (v) => (v ?? '').trim().isEmpty ? 'Name is required' : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(controller: _desc, decoration: const InputDecoration(labelText: 'Description (optional)')),
                            const SizedBox(height: 12),
                            Row(children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _rate,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                                  decoration: const InputDecoration(labelText: 'Rate (₹, without GST)'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  key: ValueKey('u$_unit'),
                                  initialValue: _unit,
                                  decoration: const InputDecoration(labelText: 'Unit'),
                                  items: [for (final u in {...units, _unit}) DropdownMenuItem(value: u, child: Text(u))],
                                  onChanged: (v) => setState(() => _unit = v ?? _unit),
                                ),
                              ),
                            ]),
                            const SizedBox(height: 12),
                            Row(children: [
                              Expanded(
                                child: DropdownButtonFormField<double>(
                                  key: ValueKey('g$_gst'),
                                  initialValue: _gst,
                                  decoration: const InputDecoration(labelText: 'GST rate'),
                                  items: [for (final g in {...gstRates, _gst}) DropdownMenuItem(value: g, child: Text(pct(g)))],
                                  onChanged: (v) => setState(() => _gst = v ?? _gst),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: TextFormField(controller: _hsn, decoration: const InputDecoration(labelText: 'HSN / SAC code'))),
                            ]),
                          ]),
                        ),
                        FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save), label: const Text('Save Product')),
                      ]),
                    ),
                  ]),
                ),
    );
  }
}
