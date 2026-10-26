import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final async = ref.watch(operationalKpiProvider);
    return FpCard(
      key: const Key('operational-kpi-panel'),
      child: async.when(
        loading: () =>
            const FpLoadingState(label: 'Calcul des indicateurs de qualité…'),
        error: (_, _) => const FpErrorState(
          message:
              'Les indicateurs de qualité sont momentanément indisponibles.',
        ),
        data: (bundle) {
          final quality = _memberId == null
              ? bundle.global
              : bundle.byMember[_memberId] ?? bundle.global;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Qualité et fiabilité',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              const SecondaryInfoText(
                'Indicateurs descriptifs : ils ne classent pas les membres. L’auteur d’une saisie n’est pas considéré comme son responsable économique.',
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  ChoiceChip(
                    key: const Key('kpi-scope-household'),
                    label: const Text('Foyer'),
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
              _QualityGrid(quality: quality, cash: bundle.cash),
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
                    label: const Text('Voir les opérations'),
                  ),
                  TextButton.icon(
                    key: const Key('kpi-drill-accounts'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AccountsPage(),
                      ),
                    ),
                    icon: const Icon(Icons.account_balance_outlined),
                    label: const Text('Voir les rapprochements'),
                  ),
                  TextButton.icon(
                    key: const Key('kpi-drill-monthly-close'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const MonthlyClosePage(),
                      ),
                    ),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Préparer la fin de mois'),
                  ),
                ],
              ),
              ExpansionTile(
                key: const Key('kpi-explanations'),
                tilePadding: EdgeInsets.zero,
                title: const Text('Comment ces indicateurs sont calculés'),
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
                        '${explanation.reason}\nSource : ${explanation.source}\nPériode : ${explanation.period} • Données : ${explanation.completeness}',
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
  const _QualityGrid({required this.quality, required this.cash});
  final OperationalQualitySnapshot quality;
  final CashQualitySnapshot cash;

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
            'Ponctualité',
            '${(quality.expectedDelayRate * 100).round()} %',
            'médiane ${quality.medianDelayDays.toStringAsFixed(1)} j • moyenne ${quality.meanDelayDays.toStringAsFixed(1)} j',
          ),
          _metric(
            width,
            'Justificatifs',
            '${quality.receiptsPresent}/${quality.receiptsRequired}',
            '${quality.drillDownIds['missingReceipt']?.length ?? 0} manquant(s)',
          ),
          _metric(
            width,
            'Rapprochements',
            '${quality.openReconciliations} ouvert(s)',
            '${quality.staleReconciliations} ancien(s) • ${quality.resolvedReconciliations} résolu(s)',
          ),
          _metric(
            width,
            'À compléter',
            '${quality.unassigned + quality.missingEnvelope}',
            '${quality.unassigned} non attribué(s) • ${quality.missingEnvelope} sans enveloppe',
          ),
          _metric(
            width,
            'Opérations attendues',
            '${quality.expectedNotMaterialized}',
            'Aucune écriture réelle créée',
          ),
          _metric(
            width,
            'Inventaires espèces',
            '${cash.inventoryCount}',
            cash.lastInventoryAt == null
                ? 'Aucun inventaire sur la période'
                : 'Dernier : ${_date(cash.lastInventoryAt!)}',
          ),
          _metric(
            width,
            'Écarts espèces',
            '${cash.unresolvedDifferences} ouvert(s)',
            '${cash.regularizedDifferences} régularisé(s) • ${(cash.regularizationRate * 100).round()} %',
          ),
          _metric(
            width,
            'Espèces non attribuées',
            '${cash.unassigned}',
            'Auteur du comptage ≠ responsable',
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
