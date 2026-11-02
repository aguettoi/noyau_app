import 'package:flutter/material.dart';

import '../../../core/localization/finance_residual_locale.dart';
import '../../../core/theme/app_design_system.dart';

class ImportWizardStepper extends StatelessWidget {
  const ImportWizardStepper({super.key, required this.currentStep});

  final int currentStep;

  @override
  Widget build(BuildContext context) {
    final words = FinanceResidualWords.of(context);
    final labels = <String>[
      words.text('import.step.source'),
      words.text('import.step.data'),
      words.text('import.step.plan'),
      words.text('import.step.execution'),
      words.text('import.step.reconciliation'),
    ];
    return Card(
      key: const Key('import-wizard-stepper'),
      color: AppColors.surfaceSecondary,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final selected = currentStep.clamp(0, labels.length - 1);
            if (constraints.maxWidth < 620) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    words.format('import.step_progress', {
                      'current': selected + 1,
                      'total': labels.length,
                      'label': labels[selected],
                    }),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  LinearProgressIndicator(
                    value: (selected + 1) / labels.length,
                  ),
                ],
              );
            }
            return Row(
              children: [
                for (var index = 0; index < labels.length; index++) ...[
                  Expanded(
                    child: _WizardStep(
                      index: index,
                      label: labels[index],
                      active: index <= selected,
                      current: index == selected,
                    ),
                  ),
                  if (index < labels.length - 1)
                    Expanded(
                      child: Divider(
                        color: index < selected
                            ? AppColors.primary
                            : AppColors.divider,
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WizardStep extends StatelessWidget {
  const _WizardStep({
    required this.index,
    required this.label,
    required this.active,
    required this.current,
  });

  final int index;
  final String label;
  final bool active;
  final bool current;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      CircleAvatar(
        radius: 14,
        backgroundColor: active ? AppColors.primary : AppColors.surface,
        foregroundColor: active ? Colors.white : AppColors.textSecondary,
        child: current
            ? Text((index + 1).toString())
            : Icon(active ? Icons.check : null, size: 16),
      ),
      const SizedBox(height: AppSpacing.xxs),
      Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: current ? AppColors.primary : AppColors.textSecondary,
          fontWeight: current ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    ],
  );
}

enum ImportDecisionTone { create, match, conflict, operational, technical }

class ImportDecisionBadge extends StatelessWidget {
  const ImportDecisionBadge({
    super.key,
    required this.label,
    required this.tone,
  });

  final String label;
  final ImportDecisionTone tone;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, icon) = switch (tone) {
      ImportDecisionTone.create => (
        AppColors.secondaryContainer,
        AppColors.secondary,
        Icons.add_circle_outline,
      ),
      ImportDecisionTone.match => (
        AppColors.primaryContainer,
        AppColors.primary,
        Icons.link,
      ),
      ImportDecisionTone.conflict => (
        AppColors.dangerContainer,
        AppColors.dangerContainerText,
        Icons.error_outline,
      ),
      ImportDecisionTone.operational => (
        AppColors.secondaryContainer,
        AppColors.secondary,
        Icons.home_outlined,
      ),
      ImportDecisionTone.technical => (
        AppColors.accentContainer,
        AppColors.accentContainerText,
        Icons.science_outlined,
      ),
    };
    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 5),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CutoverExecutionPanel extends StatelessWidget {
  const CutoverExecutionPanel({
    super.key,
    required this.confirmed,
    required this.executing,
    required this.result,
    required this.onExecute,
  });

  final bool confirmed;
  final bool executing;
  final Map<String, dynamic>? result;
  final VoidCallback onExecute;

  @override
  Widget build(BuildContext context) {
    final words = FinanceResidualWords.of(context);
    if (!confirmed) return const SizedBox.shrink();
    if (result != null) return CutoverReconciliationPanel(result: result!);
    return Card(
      key: const Key('cutover-execution-panel'),
      child: Padding(
        padding: AppSpacing.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              words.text('import.execution_title'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            SecondaryInfoText(words.text('import.execution_description')),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                key: const Key('cutover-execute-button'),
                onPressed: executing ? null : onExecute,
                icon: executing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: Text(
                  executing
                      ? words.text('import.executing')
                      : words.text('import.execute'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CutoverReconciliationPanel extends StatelessWidget {
  const CutoverReconciliationPanel({super.key, required this.result});

  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final words = FinanceResidualWords.of(context);
    final reconciled = result['status'] == 'RECONCILED';
    final rows = <Map<String, dynamic>>[
      ..._rows('accounts'),
      ..._rows('envelopes'),
    ];
    return Card(
      key: const Key('cutover-reconciliation-panel'),
      color: reconciled
          ? AppColors.secondaryContainer
          : AppColors.dangerContainer,
      child: Padding(
        padding: AppSpacing.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  reconciled ? Icons.verified_outlined : Icons.error_outline,
                  color: reconciled ? AppColors.success : AppColors.danger,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    reconciled
                        ? words.text('import.reconciled')
                        : words.text('import.reconcile_warning'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              words.format('import.result_summary', {
                'events': result['financial_events'] ?? 0,
                'transactions': result['gl_transactions'] ?? 0,
                'movements': result['envelope_movements'] ?? 0,
              }),
            ),
            const SizedBox(height: AppSpacing.md),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 700) {
                  return Column(
                    children: [
                      for (final row in rows)
                        _ReconciliationRowCard(value: row),
                    ],
                  );
                }
                return Table(
                  key: const Key('cutover-reconciliation-table'),
                  columnWidths: const {
                    0: FlexColumnWidth(2.2),
                    1: FlexColumnWidth(),
                    2: FlexColumnWidth(),
                    3: FlexColumnWidth(),
                  },
                  children: [
                    TableRow(
                      children: [
                        _TableCellText(
                          words.text('import.position'),
                          header: true,
                        ),
                        _TableCellText(
                          words.text('import.expected'),
                          header: true,
                        ),
                        _TableCellText(
                          words.text('import.actual'),
                          header: true,
                        ),
                        _TableCellText(
                          words.text('import.difference'),
                          header: true,
                        ),
                      ],
                    ),
                    for (final row in rows)
                      TableRow(
                        children: [
                          _TableCellText('${row['name']}'),
                          _TableCellText('${row['expected']}'),
                          _TableCellText('${row['actual']}'),
                          _TableCellText('${row['difference']}'),
                        ],
                      ),
                  ],
                );
              },
            ),
            if (reconciled) ...[
              const SizedBox(height: AppSpacing.md),
              SecondaryInfoText(words.text('import.completed')),
            ],
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _rows(String key) =>
      (result[key] as List<dynamic>? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false);
}

class _TableCellText extends StatelessWidget {
  const _TableCellText(this.value, {this.header = false});

  final String value;
  final bool header;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
    child: Text(
      value,
      style: header
          ? Theme.of(context).textTheme.labelLarge
          : Theme.of(context).textTheme.bodyMedium,
    ),
  );
}

class _ReconciliationRowCard extends StatelessWidget {
  const _ReconciliationRowCard({required this.value});

  final Map<String, dynamic> value;

  @override
  Widget build(BuildContext context) {
    final words = FinanceResidualWords.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: AppRadius.input,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(child: Text(value['name'].toString())),
          Text(
            words.format('import.row_summary', {
              'actual': value['actual'] ?? '',
              'expected': value['expected'] ?? '',
              'difference': value['difference'] ?? '',
            }),
          ),
        ],
      ),
    );
  }
}
