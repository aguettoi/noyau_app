import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/kpi_reporting_locale.dart';
import '../../../core/theme/app_design_system.dart';
import '../../finance/presentation/accounts_page.dart';
import '../../finance/presentation/transactions_page.dart';
import '../../monthly_close/presentation/monthly_close_page.dart';
import '../application/operational_kpi_provider.dart';
import '../domain/operational_kpis.dart';

class OperationalKpiPanel extends ConsumerStatefulWidget {
  const OperationalKpiPanel({super.key});

  @override
  ConsumerState<OperationalKpiPanel> createState() =>
      _OperationalKpiPanelState();
}

class _OperationalKpiPanelState extends ConsumerState<OperationalKpiPanel> {
  String? _memberId;

  @override
  Widget build(BuildContext context) {
    final words = KpiReportingWords.of(context);
    final async = ref.watch(operationalKpiProvider);
    return FpCard(
      key: const Key('operational-kpi-panel'),
      child: async.when(
        loading: () => FpLoadingState(label: words.text('kpi.loading')),
        error: (_, _) => FpErrorState(message: words.text('kpi.unavailable')),
        data: (bundle) {
          final quality = _memberId == null
              ? bundle.global
              : bundle.byMember[_memberId] ?? bundle.global;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                words.text('kpi.title'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              SecondaryInfoText(words.text('kpi.description')),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  ChoiceChip(
                    key: const Key('kpi-scope-household'),
                    label: Text(words.text('kpi.household')),
                    selected: _memberId == null,
                    onSelected: (_) => setState(() => _memberId = null),
                  ),
                  for (final entry in bundle.memberNames.entries)
                    ChoiceChip(
                      key: Key('kpi-scope-member-${entry.key}'),
                      label: Text(entry.value),
                      selected: _memberId == entry.key,
                      onSelected: (_) => setState(() => _memberId = entry.key),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              _QualityGrid(quality: quality, cash: bundle.cash, words: words),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  TextButton.icon(
                    key: const Key('kpi-drill-transactions'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const TransactionsPage(),
                      ),
                    ),
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: Text(words.text('kpi.open_transactions')),
                  ),
                  TextButton.icon(
                    key: const Key('kpi-drill-accounts'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AccountsPage(),
                      ),
                    ),
                    icon: const Icon(Icons.account_balance_outlined),
                    label: Text(words.text('kpi.open_reconciliations')),
                  ),
                  TextButton.icon(
                    key: const Key('kpi-drill-monthly-close'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const MonthlyClosePage(),
                      ),
                    ),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: Text(words.text('kpi.prepare_month_end')),
                  ),
                ],
              ),
              ExpansionTile(
                key: const Key('kpi-explanations'),
                tilePadding: EdgeInsets.zero,
                title: Text(words.text('kpi.explanation_title')),
                children: [
                  for (final explanation in [
                    ...quality.explanations,
                    bundle.cash.explanation,
                  ])
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(explanation.rule),
                      subtitle: Text(
                        words.format('kpi.explanation_meta', {
                          'reason': explanation.reason,
                          'source': explanation.source,
                          'period': explanation.period,
                          'completeness': explanation.completeness,
                        }),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _QualityGrid extends StatelessWidget {
  const _QualityGrid({
    required this.quality,
    required this.cash,
    required this.words,
  });
  final OperationalQualitySnapshot quality;
  final CashQualitySnapshot cash;
  final KpiReportingWords words;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth >= 900
          ? (constraints.maxWidth - AppSpacing.sm * 3) / 4
          : constraints.maxWidth >= 560
          ? (constraints.maxWidth - AppSpacing.sm) / 2
          : constraints.maxWidth;
      return Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          _metric(
            width,
            words.text('kpi.punctuality'),
            '${(quality.expectedDelayRate * 100).round()} %',
            words.format('kpi.delay_detail', {
              'median': quality.medianDelayDays.toStringAsFixed(1),
              'mean': quality.meanDelayDays.toStringAsFixed(1),
            }),
          ),
          _metric(
            width,
            words.text('kpi.receipts'),
            '${quality.receiptsPresent}/${quality.receiptsRequired}',
            words.format('kpi.missing_count', {
              'count': quality.drillDownIds['missingReceipt']?.length ?? 0,
            }),
          ),
          _metric(
            width,
            words.text('kpi.reconciliations'),
            '${quality.openReconciliations}',
            words.format('kpi.reconciliation_detail', {
              'open': quality.openReconciliations,
              'stale': quality.staleReconciliations,
              'resolved': quality.resolvedReconciliations,
            }),
          ),
          _metric(
            width,
            words.text('kpi.to_complete'),
            '${quality.unassigned + quality.missingEnvelope}',
            words.format('kpi.completion_detail', {
              'unassigned': quality.unassigned,
              'withoutEnvelope': quality.missingEnvelope,
            }),
          ),
          _metric(
            width,
            words.text('kpi.expected_operations'),
            '${quality.expectedNotMaterialized}',
            words.text('kpi.no_real_entry'),
          ),
          _metric(
            width,
            words.text('kpi.cash_inventories'),
            '${cash.inventoryCount}',
            cash.lastInventoryAt == null
                ? words.text('kpi.no_inventory')
                : words.format('kpi.last_inventory', {
                    'date': _date(cash.lastInventoryAt!),
                  }),
          ),
          _metric(
            width,
            words.text('kpi.cash_differences'),
            '${cash.unresolvedDifferences}',
            words.format('kpi.cash_difference_detail', {
              'open': cash.unresolvedDifferences,
              'regularized': cash.regularizedDifferences,
              'rate': (cash.regularizationRate * 100).round(),
            }),
          ),
          _metric(
            width,
            words.text('kpi.unassigned_cash'),
            '${cash.unassigned}',
            words.text('kpi.counter_not_responsible'),
          ),
        ],
      );
    },
  );

  Widget _metric(double width, String title, String value, String detail) =>
      SizedBox(
        width: width,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .035),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(detail, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
      );

  static String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
}
