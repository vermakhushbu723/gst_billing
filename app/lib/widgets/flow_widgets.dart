import 'package:flutter/material.dart';

import '../core/brand.dart';
import '../core/tax_mode.dart';

/// Top-bar switch between the two flows: With GST / Without GST.
class ModeSwitch extends StatelessWidget {
  const ModeSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    final m = TaxMode.instance;
    final compact = MediaQuery.sizeOf(context).width < 600;
    return ListenableBuilder(
      listenable: m,
      builder: (context, _) {
        Widget seg(bool gst, String label) {
          final on = m.gst == gst;
          final enabled = gst ? m.gstAllowed : true;
          return InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: enabled && !on ? () => m.set(gst) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 12, vertical: 6),
              decoration: BoxDecoration(color: on ? (gst ? Brand.teal : Brand.gold) : Colors.transparent, borderRadius: BorderRadius.circular(18)),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: on ? (gst ? Colors.white : Brand.navy) : (enabled ? Brand.slate : Colors.grey.shade400),
                ),
              ),
            ),
          );
        }

        return Tooltip(
          message: m.gstAllowed ? 'Switch between GST bills and bills without GST' : 'This company is not GST registered',
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Brand.border)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              seg(true, compact ? 'GST' : 'With GST'),
              seg(false, compact ? 'No GST' : 'Without GST'),
            ]),
          ),
        );
      },
    );
  }
}

/// Filter chips for reports and export: both flows, with GST, without GST.
/// Value: null = both, true = with GST, false = without GST.
class FlowChips extends StatelessWidget {
  const FlowChips({super.key, required this.value, required this.onChanged});
  final bool? value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final o in const [(null, 'Both'), (true, 'With GST'), (false, 'Without GST')])
          ChoiceChip(
            avatar: Icon(o.$1 == null ? Icons.layers_outlined : (o.$1! ? Icons.percent : Icons.money_off), size: 16),
            label: Text(o.$2),
            selected: value == o.$1,
            onSelected: (_) => onChanged(o.$1),
          ),
      ]);
}

/// "gst" / "nongst" / null for the API from a FlowChips value.
String? flowParam(bool? v) => v == null ? null : (v ? 'gst' : 'nongst');
