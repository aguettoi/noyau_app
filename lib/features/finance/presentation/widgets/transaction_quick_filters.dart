import 'package:flutter/material.dart';

import '../../../../core/theme/app_design_system.dart';

class TransactionQuickFilter {
  const TransactionQuickFilter({required this.value, required this.label});
  final String? value;
  final String label;
}

class TransactionQuickFilters extends StatelessWidget {
  const TransactionQuickFilters({
    super.key,
    required this.selected,
    required this.options,
    required this.onChanged,
  });

  final String? selected;
  final List<TransactionQuickFilter> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final option in options) ...[
            FilterChip(
              key: Key('transaction-quick-filter-${option.value ?? 'all'}'),
              label: Text(option.label),
              selected: selected == option.value,
              onSelected: (_) => onChanged(option.value),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
        ],
      ),
    ),
  );
}
