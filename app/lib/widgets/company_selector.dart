import 'package:flutter/material.dart';

import '../core/companies.dart';

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
        final value = c.selected == 'all' && !allowAll ? c.defaultId : c.selected;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFD5DAE3)),
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
