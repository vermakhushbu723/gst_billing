import 'package:flutter/material.dart';

import '../core/companies.dart';
import '../core/brand.dart';

/// Dropdown to switch between "All companies" and one company.
class CompanySelector extends StatelessWidget {
  const CompanySelector({super.key, required this.onChanged, this.allowAll = true});
  final VoidCallback onChanged;
  final bool allowAll;

  @override
  Widget build(BuildContext context) {
    final c = Companies.instance;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        if (c.locked) return _LockedCompany(name: c.nameOf(c.selected));
        final value = c.selected == 'all' && !allowAll ? c.defaultId : c.selected;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Brand.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon: const Icon(Icons.expand_more),
              items: [
                if (allowAll) const DropdownMenuItem(value: 'all', child: Text('All companies')),
                for (final co in c.list)
                  DropdownMenuItem(
                    value: co['_id'] as String,
                    child: Text('${co['name']}', overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) async {
                if (v == null) return;
                await c.select(v);
                onChanged();
              },
            ),
          ),
        );
      },
    );
  }
}

/// Company logins cannot switch company; show which one they are in.
class _LockedCompany extends StatelessWidget {
  const _LockedCompany({required this.name});
  final String name;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(color: Brand.tealLight, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          const Icon(Icons.business, size: 18, color: Brand.teal),
          const SizedBox(width: 8),
          Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.navy), overflow: TextOverflow.ellipsis)),
        ]),
      );
}

/// Company picker inside forms (customer, product...). Hidden choice for company logins.
class CompanyField extends StatelessWidget {
  const CompanyField({super.key, required this.value, required this.onChanged, this.enabled = true});
  final String? value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = Companies.instance;
    if (c.locked) return _LockedCompany(name: c.nameOf(c.selected));
    return DropdownButtonFormField<String>(
      key: ValueKey('company-$value'),
      initialValue: c.byId(value) != null ? value : null,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Company', prefixIcon: Icon(Icons.business_outlined)),
      validator: (v) => v == null ? 'Select a company' : null,
      items: [for (final co in c.list) DropdownMenuItem(value: co['_id'] as String, child: Text('${co['name']}', overflow: TextOverflow.ellipsis))],
      onChanged: enabled ? (v) => v == null ? null : onChanged(v) : null,
    );
  }
}
