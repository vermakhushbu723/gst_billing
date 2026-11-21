import 'package:flutter/material.dart';

import '../core/format.dart';

/// Date range with quick presets: this month, last month, this FY, last FY, custom.
class Period {
  Period(this.key, this.from, this.to);
  final String key, from, to;

  static Period preset(String key) {
    final now = DateTime.now();
    final fy = now.month >= 4 ? now.year : now.year - 1;
    return switch (key) {
      'today' => Period(key, ymdOf(now), ymdOf(now)),
      'last' => Period(key, ymdOf(DateTime(now.year, now.month - 1, 1)), ymdOf(DateTime(now.year, now.month, 0))),
      'fy' => Period(key, '$fy-04-01', '${fy + 1}-03-31'),
      'lastfy' => Period(key, '${fy - 1}-04-01', '$fy-03-31'),
      _ => Period('month', ymdOf(DateTime(now.year, now.month, 1)), ymdOf(DateTime(now.year, now.month + 1, 0))),
    };
  }
}

class PeriodFilter extends StatelessWidget {
  const PeriodFilter({super.key, required this.value, required this.onChanged});
  final Period value;
  final ValueChanged<Period> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final p in const [('today', 'Today'), ('month', 'This month'), ('last', 'Last month'), ('fy', 'This FY'), ('lastfy', 'Last FY')])
          ChoiceChip(label: Text(p.$2), selected: value.key == p.$1, onSelected: (_) => onChanged(Period.preset(p.$1))),
        ChoiceChip(
          avatar: const Icon(Icons.date_range, size: 18),
          label: Text(value.key == 'custom' ? '${dmy(value.from)} - ${dmy(value.to)}' : 'Custom'),
          selected: value.key == 'custom',
          onSelected: (_) async {
            final r = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2015),
              lastDate: DateTime(2100),
              initialDateRange: DateTimeRange(start: parseYmd(value.from)!, end: parseYmd(value.to)!),
            );
            if (r != null) onChanged(Period('custom', ymdOf(r.start), ymdOf(r.end)));
          },
        ),
      ]),
      const SizedBox(height: 6),
      Text('${dmy(value.from)} to ${dmy(value.to)}', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
    ]);
  }
}
