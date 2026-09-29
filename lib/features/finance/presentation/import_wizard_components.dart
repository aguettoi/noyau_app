import 'package:flutter/material.dart';

import '../../../core/theme/app_design_system.dart';

class ImportWizardStepper extends StatelessWidget {
  const ImportWizardStepper({super.key, required this.currentStep});

  final int currentStep;

  static const labels = <String>[
    'Source',
    'Données',
    'Plan',
    'Exécution',
    'Réconciliation',
  ];

  @override
  Widget build(BuildContext context) => Card(
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
                  'Étape ${selected + 1} sur ${labels.length} — ${labels[selected]}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                LinearProgressIndicator(value: (selected + 1) / labels.length),
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
            ? Text('${index + 1}')
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
    if (!confirmed) return const SizedBox.shrink();
    if (result != null) return CutoverReconciliationPanel(result: result!);
    return Card(
      key: const Key('cutover-execution-panel'),
      child: Padding(
        padding: AppSpacing.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('4. Exécution', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            const SecondaryInfoText(
              'Le plan confirmé sera exécuté par les primitives canoniques, puis relu pour réconciliation.',
            ),
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
                  executing ? 'Exécution...' : 'Exécuter et réconcilier',
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
                        ? '5. Réconciliation — écart zéro'
                        : '5. Réconciliation — écarts à vérifier',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${result['financial_events'] ?? 0} événements • '
              '${result['gl_transactions'] ?? 0} transactions GL • '
              '${result['envelope_movements'] ?? 0} mouvements enveloppes',
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
                    const TableRow(
                      children: [
                        _TableCellText('Position', header: true),
                        _TableCellText('Attendu', header: true),
                        _TableCellText('Réel', header: true),
                        _TableCellText('Écart', header: true),
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
              const SecondaryInfoText(
                'Exécution terminée. Un nouveau clic n’est pas nécessaire : le résultat persistant est déjà relu.',
              ),
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
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: AppSpacing.xs),
    padding: const EdgeInsets.all(AppSpacing.sm),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: AppRadius.input,
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      children: [
        Expanded(child: Text('${value['name']}')),
        Text(
          '${value['actual']} / ${value['expected']}  •  Δ ${value['difference']}',
        ),
      ],
    ),
  );
}
