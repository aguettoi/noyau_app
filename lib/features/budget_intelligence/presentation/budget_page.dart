import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design_system.dart';
import '../../envelopes/application/providers/remote_envelopes_provider.dart';
import '../application/budget_reporting.dart';
import '../application/providers/remote_budget_provider.dart';
import 'budget_runs_page.dart';
import 'budget_monthly_preparation_page.dart';
import 'budget_scenarios_page.dart';

class BudgetPage extends ConsumerStatefulWidget {
  const BudgetPage({super.key});

  @override
  ConsumerState<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends ConsumerState<BudgetPage> {
  BudgetHorizon _horizon = BudgetHorizon.monthly;

  @override
  Widget build(BuildContext context) {
    final periods = ref.watch(remoteBudgetPeriodsProvider);
    final envelopes = ref.watch(remoteEnvelopeBalancesProvider);
    final compact = AppLayout.isCompact(MediaQuery.sizeOf(context).width);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Budget'),
        actions: compact
            ? [
                PopupMenuButton<_BudgetDestination>(
                  tooltip: 'Navigation Budget',
                  onSelected: (destination) =>
                      _openDestination(context, destination),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: _BudgetDestination.month,
                      child: Text('Préparer mon mois'),
                    ),
                    PopupMenuItem(
                      value: _BudgetDestination.scenarios,
                      child: Text('Scénarios'),
                    ),
                    PopupMenuItem(
                      value: _BudgetDestination.history,
                      child: Text('Historique'),
                    ),
                  ],
                ),
              ]
            : [
                TextButton(
                  onPressed: () =>
                      _openDestination(context, _BudgetDestination.month),
                  child: const Text('Préparer mon mois'),
                ),
                TextButton(
                  onPressed: () =>
                      _openDestination(context, _BudgetDestination.scenarios),
                  child: const Text('Scénarios'),
                ),
                TextButton(
                  onPressed: () =>
                      _openDestination(context, _BudgetDestination.history),
                  child: const Text('Historique'),
                ),
              ],
      ),
      body: periods.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Périodes budgétaires indisponibles.')),
        data: (allPeriods) {
          if (allPeriods.isEmpty) {
            return const Center(
              child: Text('Aucune période budgétaire disponible.'),
            );
          }
          final selectedId =
              ref.watch(selectedBudgetPeriodIdProvider) ?? allPeriods.first.id;
          final period =
              allPeriods.where((item) => item.id == selectedId).firstOrNull ??
              allPeriods.first;
          final report = ref.watch(
            remoteBudgetReportingProvider((horizon: _horizon, period: period)),
          );
          return LayoutBuilder(
            builder: (context, constraints) => Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppLayout.contentMaxWidth,
                ),
                child: ListView(
                  padding: AppLayout.pagePaddingFor(constraints.maxWidth),
                  children: [
                    _BudgetHero(
                      periodId: period.id,
                      periods: allPeriods,
                      horizon: _horizon,
                      onPeriodChanged: (value) {
                        ref
                                .read(selectedBudgetPeriodIdProvider.notifier)
                                .state =
                            value;
                      },
                      onHorizonChanged: (value) =>
                          setState(() => _horizon = value),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    LayoutBuilder(
                      builder: (context, bodyConstraints) {
                        final desktop = AppLayout.isDesktop(
                          bodyConstraints.maxWidth,
                        );
                        final reporting = _ReportingList(
                          report: report,
                          envelopes: envelopes,
                        );
                        final preparation = _BudgetPreparationCard(
                          onOpen: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  const BudgetMonthlyPreparationPage(),
                            ),
                          ),
                        );
                        if (!desktop) {
                          return Column(
                            children: [
                              reporting,
                              const SizedBox(height: AppSpacing.md),
                              preparation,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: reporting),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(flex: 2, child: preparation),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _openDestination(BuildContext context, _BudgetDestination destination) {
    final page = switch (destination) {
      _BudgetDestination.month => const BudgetMonthlyPreparationPage(),
      _BudgetDestination.scenarios => const BudgetScenariosPage(),
      _BudgetDestination.history => const BudgetRunsPage(),
    };
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }
}

enum _BudgetDestination { month, scenarios, history }

class _BudgetHero extends StatelessWidget {
  const _BudgetHero({
    required this.periodId,
    required this.periods,
    required this.horizon,
    required this.onPeriodChanged,
    required this.onHorizonChanged,
  });

  final String periodId;
  final List<RemoteBudgetPeriod> periods;
  final BudgetHorizon horizon;
  final ValueChanged<String?> onPeriodChanged;
  final ValueChanged<BudgetHorizon> onHorizonChanged;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: AppSpacing.card,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.lg,
        runSpacing: AppSpacing.sm,
        children: [
          const SizedBox(
            width: 310,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pilotage du budget'),
                SizedBox(height: AppSpacing.xxs),
                Text('Suivez le prévu, le réel et les écarts de la période.'),
              ],
            ),
          ),
          SizedBox(
            width: 260,
            child: DropdownButtonFormField<String>(
              key: const Key('budget-period-selector'),
              initialValue: periodId,
              decoration: const InputDecoration(labelText: 'Période'),
              items: periods
                  .map(
                    (item) => DropdownMenuItem(
                      value: item.id,
                      child: Text(item.label),
                    ),
                  )
                  .toList(),
              onChanged: onPeriodChanged,
            ),
          ),
          SegmentedButton<BudgetHorizon>(
            segments: const [
              ButtonSegment(value: BudgetHorizon.monthly, label: Text('Mois')),
              ButtonSegment(value: BudgetHorizon.ytd, label: Text('YTD')),
              ButtonSegment(value: BudgetHorizon.ltd, label: Text('LTD')),
            ],
            selected: {horizon},
            onSelectionChanged: (value) => onHorizonChanged(value.single),
          ),
        ],
      ),
    ),
  );
}

class _BudgetPreparationCard extends StatelessWidget {
  const _BudgetPreparationCard({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: AppSpacing.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.calendar_month_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Préparation budgétaire',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Choisissez un scénario, ajustez le mois puis enregistrez un snapshot immuable.',
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const Key('open-monthly-preparation'),
              onPressed: onOpen,
              icon: const Icon(Icons.arrow_forward_outlined),
              label: const Text('Préparer mon mois'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ReportingList extends StatelessWidget {
  const _ReportingList({required this.report, required this.envelopes});
  final AsyncValue<List<RemoteBudgetReportRow>> report;
  final AsyncValue<List<dynamic>> envelopes;

  @override
  Widget build(BuildContext context) => report.when(
    loading: () => const LinearProgressIndicator(),
    error: (_, _) => const Text('Reporting indisponible.'),
    data: (rows) => envelopes.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => const Text('Enveloppes indisponibles.'),
      data: (items) {
        final names = {for (final item in items) item.id: item.name};
        return Card(
          child: Padding(
            padding: AppSpacing.card,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Répartition des enveloppes',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                if (rows.isEmpty)
                  const Text('Aucun flux pour cette période.')
                else
                  ...rows.map(
                    (row) => _BudgetReportRow(
                      name: names[row.envelopeId] ?? 'Enveloppe',
                      row: row,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _BudgetReportRow extends StatelessWidget {
  const _BudgetReportRow({required this.name, required this.row});

  final String name;
  final RemoteBudgetReportRow row;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Prévu ${_mad(row.plannedCents)} • Réel ${_mad(row.actualCents)}',
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          row.balanceCents < 0
              ? '−${_mad(-row.balanceCents)}'
              : _mad(row.balanceCents),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: row.balanceCents < 0
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.secondary,
          ),
        ),
      ],
    ),
  );
}

String _mad(int cents) => '${(cents / 100).toStringAsFixed(2)} MAD';

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
