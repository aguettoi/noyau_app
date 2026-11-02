import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design_system.dart';
import '../../../core/localization/budget_locale.dart';
import '../../envelopes/application/providers/remote_envelopes_provider.dart';
import '../application/budget_reporting.dart';
import '../application/monthly_quality_analysis.dart';
import '../application/providers/monthly_quality_provider.dart';
import '../application/providers/remote_budget_provider.dart';
import 'budget_runs_page.dart';
import 'budget_monthly_preparation_page.dart';
import 'budget_scenarios_page.dart';

String _bt(BuildContext context, String key) =>
    BudgetWords.of(context).text(key);
String _bf(BuildContext context, String key, Map<String, Object> values) =>
    BudgetWords.of(context).format(key, values);

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
        title: Text(_bt(context, 'budget.title')),
        actions: compact
            ? [
                PopupMenuButton<_BudgetDestination>(
                  tooltip: _bt(context, 'budget.navigation'),
                  onSelected: (destination) =>
                      _openDestination(context, destination),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: _BudgetDestination.month,
                      child: Text(_bt(context, 'budget.prepare_month')),
                    ),
                    PopupMenuItem(
                      value: _BudgetDestination.scenarios,
                      child: Text(_bt(context, 'budget.scenarios')),
                    ),
                    PopupMenuItem(
                      value: _BudgetDestination.history,
                      child: Text(_bt(context, 'budget.history')),
                    ),
                  ],
                ),
              ]
            : [
                TextButton(
                  onPressed: () =>
                      _openDestination(context, _BudgetDestination.month),
                  child: Text(_bt(context, 'budget.prepare_month')),
                ),
                TextButton(
                  onPressed: () =>
                      _openDestination(context, _BudgetDestination.scenarios),
                  child: Text(_bt(context, 'budget.scenarios')),
                ),
                TextButton(
                  onPressed: () =>
                      _openDestination(context, _BudgetDestination.history),
                  child: Text(_bt(context, 'budget.history')),
                ),
              ],
      ),
      body: periods.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            Center(child: Text(_bt(context, 'budget.periods_error'))),
        data: (allPeriods) {
          if (allPeriods.isEmpty) {
            return Center(child: Text(_bt(context, 'budget.no_period')));
          }
          final selectedId =
              ref.watch(selectedBudgetPeriodIdProvider) ?? allPeriods.first.id;
          final period =
              allPeriods.where((item) => item.id == selectedId).firstOrNull ??
              allPeriods.first;
          final report = ref.watch(
            remoteBudgetReportingProvider((horizon: _horizon, period: period)),
          );
          final quality = ref.watch(
            monthlyQualityProvider((horizon: _horizon, period: period)),
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
                    const SizedBox(height: AppSpacing.md),
                    _MonthlyQualityPanel(quality: quality),
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
          SizedBox(
            width: 310,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_bt(context, 'budget.steering')),
                const SizedBox(height: AppSpacing.xxs),
                Text(_bt(context, 'budget.steering_hint')),
              ],
            ),
          ),
          SizedBox(
            width: 260,
            child: DropdownButtonFormField<String>(
              key: const Key('budget-period-selector'),
              initialValue: periodId,
              decoration: InputDecoration(
                labelText: _bt(context, 'budget.period'),
              ),
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
            segments: [
              ButtonSegment(
                value: BudgetHorizon.monthly,
                label: Text(_bt(context, 'budget.month')),
              ),
              ButtonSegment(
                value: BudgetHorizon.ytd,
                label: Text(_bt(context, 'budget.ytd')),
              ),
              ButtonSegment(
                value: BudgetHorizon.ltd,
                label: Text(_bt(context, 'budget.ltd')),
              ),
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
            _bt(context, 'budget.preparation'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(_bt(context, 'budget.preparation_hint')),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const Key('open-monthly-preparation'),
              onPressed: onOpen,
              icon: const Icon(Icons.arrow_forward_outlined),
              label: Text(_bt(context, 'budget.prepare_month')),
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
    error: (_, _) => Text(_bt(context, 'budget.reporting_error')),
    data: (rows) => envelopes.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => Text(_bt(context, 'budget.envelopes_error')),
      data: (items) {
        final names = {for (final item in items) item.id: item.name};
        return Card(
          child: Padding(
            padding: AppSpacing.card,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _bt(context, 'budget.envelope_distribution'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                if (rows.isEmpty)
                  Text(_bt(context, 'budget.no_flow'))
                else
                  ...rows.map(
                    (row) => _BudgetReportRow(
                      name:
                          names[row.envelopeId] ??
                          _bt(context, 'budget.envelope'),
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

class _MonthlyQualityPanel extends StatelessWidget {
  const _MonthlyQualityPanel({required this.quality});
  final AsyncValue<MonthlyQualityAnalysis> quality;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: AppSpacing.card,
      child: quality.when(
        loading: () => const LinearProgressIndicator(),
        error: (_, _) => Text(_bt(context, 'budget.quality_error')),
        data: (value) => Column(
          key: const Key('monthly-quality-panel'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _bt(context, 'budget.quality_title'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _bf(context, 'budget.quality_totals', {
                'planned': _mad(value.plannedCents),
                'actual': _mad(value.actualCents),
                'expected': _mad(value.expectedCents),
                'remaining': _mad(value.remainingCents),
              }),
              key: const Key('monthly-quality-totals'),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              children: [
                Text(
                  _bf(context, 'budget.open_reconciliations', {
                    'count': value.reconciliations.open,
                  }),
                ),
                Text(
                  _bf(context, 'budget.missing_receipts', {
                    'count': value.receipts.missing,
                  }),
                ),
                Text(
                  _bf(context, 'budget.unresolved_expected', {
                    'count': value.unresolvedOccurrences,
                  }),
                ),
                Text(
                  _bf(context, 'budget.unassigned', {
                    'count': value.responsibilities.unassigned,
                  }),
                ),
              ],
            ),
            if (value.explanations.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              for (final item in value.explanations)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.info_outline),
                  title: Text(item.rule),
                  subtitle: Text(
                    _bf(context, 'budget.explanation', {
                      'reason': item.reason,
                      'source': item.source,
                      'period': item.period,
                      'action': item.action == null
                          ? ''
                          : _bf(context, 'budget.action', {
                              'action': item.action!,
                            }),
                    }),
                  ),
                ),
            ],
            if (value.options.isNotEmpty) ...[
              const Divider(),
              Text(
                _bt(context, 'budget.options'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(_bt(context, 'budget.simulation_hint')),
              for (final option in value.options)
                ListTile(
                  key: Key('monthly-decision-${option.kind.name}'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.balance_outlined),
                  title: Text(
                    _bf(context, 'budget.option_title', {
                      'title': option.title,
                      'amount': _mad(option.amountCents),
                    }),
                  ),
                  subtitle: Text(
                    _bf(context, 'budget.option_detail', {
                      'consequence': option.consequence,
                      'reason': option.explanation.reason,
                    }),
                  ),
                  trailing: option.requiresConfirmation
                      ? Chip(label: Text(_bt(context, 'budget.to_confirm')))
                      : null,
                ),
            ],
          ],
        ),
      ),
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
                _bf(context, 'budget.row', {
                  'planned': _mad(row.plannedCents),
                  'actual': _mad(row.actualCents),
                }),
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
