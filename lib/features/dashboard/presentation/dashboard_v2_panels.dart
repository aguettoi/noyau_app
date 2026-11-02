import 'package:flutter/material.dart';
import '../../../core/theme/app_design_system.dart';
import '../../../core/localization/dashboard_v2_locale.dart';
import '../application/dashboard_metrics.dart';
import '../application/providers/remote_financial_dashboard_provider.dart';
import 'dashboard_charts.dart';

/// Presentation only: positions, allocations and forecasts are never added together.
class DashboardV2Panels extends StatelessWidget {
  const DashboardV2Panels({
    super.key,
    required this.snapshot,
    required this.open,
  });
  final FinancialDashboardSnapshot snapshot;
  final ValueChanged<DashboardDestination> open;

  Widget action(String key, String label, DashboardDestination destination) =>
      TextButton(
        key: Key(key),
        onPressed: () => open(destination),
        child: Text(label),
      );

  @override
  Widget build(BuildContext context) {
    final w = DashboardV2Words.of(context);
    final s = snapshot;
    final report = [...s.report]
      ..sort((a, b) {
        final amount = b.actualCents.compareTo(a.actualCents);
        return amount != 0 ? amount : a.envelopeId.compareTo(b.envelopeId);
      });
    String name(String id) =>
        s.ordinaryEnvelopes.where((e) => e.id == id).firstOrNull?.name ??
        (s.toAllocate?.id == id
            ? w.text('to_allocate')
            : w.text('archived_envelope'));
    final spending = report.where((e) => e.actualCents != 0).toList();
    final positive = spending.where((e) => e.actualCents > 0).toList();
    final total = positive.fold<int>(0, (sum, e) => sum + e.actualCents);
    final maxSpend = spending.fold<int>(
      1,
      (max, e) => e.actualCents.abs() > max ? e.actualCents.abs() : max,
    );
    final budgets = report.where((e) => e.plannedCents > 0).toList();
    final segments = [
      for (final e in positive.take(5))
        (name: name(e.envelopeId), cents: e.actualCents),
      if (positive.length > 5)
        (
          name: w.text('other'),
          cents: positive.skip(5).fold<int>(0, (sum, e) => sum + e.actualCents),
        ),
    ];
    final alerts = [...s.alerts]
      ..sort((a, b) => b.severity.index.compareTo(a.severity.index));
    final plan = s.activePlan;
    final entries = s.availability?.planEntries[plan?.plan.id];
    final pending = entries
        ?.where((e) => e.remainingNeed.minorUnits > 0)
        .toList();
    final accounts = [...s.accounts]
      ..sort((a, b) {
        final balance = b.balance.minorUnits.compareTo(a.balance.minorUnits);
        return balance != 0 ? balance : a.account.id.compareTo(b.account.id);
      });
    final maxAccount = accounts.fold<int>(
      1,
      (max, e) =>
          e.balance.minorUnits.abs() > max ? e.balance.minorUnits.abs() : max,
    );
    final openCases = s.reconciliations.where((e) => e.isOpen).toList();
    final observed = s.reconciliations.map((e) => e.accountId).toSet();
    final dates =
        s.reconciliations
            .where((e) => e.status == 'resolved' || e.status == 'reconciled')
            .map((e) => e.observedAt)
            .toList()
          ..sort();
    final maxObligation = [
      s.debtRemaining.minorUnits,
      s.incomeReceivableRemaining.minorUnits,
      s.recoveryRemaining.minorUnits,
      1,
    ].reduce((a, b) => a > b ? a : b);
    final kpis = <({String title, String value, String detail})>[
      (
        title: s.hasHiddenAccountBalances
            ? w.text('visible_liquidity')
            : w.text('liquidity'),
        value: chartMoney(s.cashTotal.minorUnits),
        detail: s.hasHiddenAccountBalances
            ? w.text('partial_total')
            : w.format('cash_detail', {
                'amount': chartMoney(s.cashOnHand.minorUnits),
              }),
      ),
      (
        title: w.text('envelopes'),
        value: chartMoney(s.totalEnvelopes.minorUnits),
        detail: w.text('envelopes_detail'),
      ),
      (
        title: w.text('income'),
        value: chartMoney(s.monthlyFlow.income.minorUnits),
        detail: s.period.label,
      ),
      (
        title: w.text('expenses'),
        value: chartMoney(s.monthlyFlow.expense.minorUnits),
        detail: s.period.label,
      ),
      (
        title: w.text('budget_remaining'),
        value: s.budget.hasPreparedBudget
            ? chartMoney(s.budget.remaining.minorUnits)
            : w.text('unavailable'),
        detail: w.text('official_budget'),
      ),
      (
        title: s.hasHiddenAccountBalances
            ? w.text('visible_savings')
            : w.text('savings'),
        value: accounts.any((a) => a.account.type.name == 'savings')
            ? chartMoney(s.savingsAccounts.minorUnits)
            : w.text('unavailable'),
        detail: w.text('savings_detail'),
      ),
      (
        title: w.text('net_obligations'),
        value: chartMoney(s.netObligations.minorUnits),
        detail: w.text('net_obligations_detail'),
      ),
      (
        title: w.text('to_allocate'),
        value: s.toAllocate == null
            ? w.text('unavailable')
            : chartMoney(s.toAllocate!.balance.minorUnits),
        detail: w.text('to_allocate_detail'),
      ),
    ];
    final flow = _Panel(
      title: w.text('flow_title'),
      subtitle: w.text('flow_subtitle'),
      height: 310,
      child: IncomeExpenseChart(
        key: const Key('dashboard-chart-income'),
        points: s.history,
      ),
    );
    final alertPanel = _Panel(
      title: w.text('todo'),
      subtitle: w.text('priority_points'),
      height: 310,
      child: alerts.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    color: AppColors.secondary,
                    size: 32,
                  ),
                  const SizedBox(height: 12),
                  Text(w.text('no_critical'), textAlign: TextAlign.center),
                ],
              ),
            )
          : ListView(
              children: [
                for (final a in alerts.take(4))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      a.severity == DashboardAlertSeverity.critical
                          ? Icons.error_outline
                          : Icons.info_outline,
                      color: a.severity == DashboardAlertSeverity.critical
                          ? Colors.red.shade700
                          : a.severity == DashboardAlertSeverity.warning
                          ? AppColors.accent
                          : AppColors.primary,
                    ),
                    title: Text(
                      a.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      a.detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => open(a.destination),
                  ),
                if (alerts.length > 4)
                  Text(
                    w.format('more_alerts', {'count': alerts.length - 4}),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
    );
    final envelope = _Panel(
      title: w.text('envelope_expenses'),
      subtitle: w.format('envelope_subtitle', {'period': s.period.label}),
      height: 350,
      action: action(
        'dashboard-open-envelopes',
        w.text('view_envelopes'),
        DashboardDestination.envelopes,
      ),
      child: KeyedSubtree(
        key: const Key('dashboard-chart-envelopes'),
        child: spending.isEmpty
            ? EmptyPlot(message: w.text('no_consumption'))
            : ListView(
                children: [
                  for (final e in spending.take(5))
                    ValueBar(
                      label: name(e.envelopeId),
                      cents: e.actualCents,
                      maximum: maxSpend,
                      suffix: e.actualCents > 0 && total > 0
                          ? '${(e.actualCents / total * 100).toStringAsFixed(1)} %'
                          : null,
                    ),
                ],
              ),
      ),
    );
    final donut = _Panel(
      title: w.text('expense_breakdown'),
      subtitle: w.format('breakdown_subtitle', {'period': s.period.label}),
      height: 350,
      child: ExpenseDonut(
        key: const Key('dashboard-chart-donut'),
        segments: segments,
      ),
    );
    final budget = _Panel(
      title: w.text('budget_actual'),
      subtitle: s.period.label,
      height: 370,
      action: action(
        'dashboard-open-month-preparation',
        w.text('prepare_month'),
        DashboardDestination.budget,
      ),
      child: KeyedSubtree(
        key: const Key('dashboard-chart-budget'),
        child: budgets.isEmpty
            ? EmptyPlot(
                key: const Key('dashboard-budget-empty'),
                message: w.text('prepare_first_budget'),
              )
            : ListView(
                children: [
                  for (final e in budgets.take(5))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ValueBar(
                            label: name(e.envelopeId),
                            cents: e.actualCents,
                            maximum: e.plannedCents,
                            suffix:
                                '${(e.actualCents / e.plannedCents * 100).toStringAsFixed(1)} %',
                            color: e.actualCents > e.plannedCents
                                ? Colors.red.shade700
                                : e.actualCents >= e.plannedCents * .8
                                ? AppColors.accent
                                : AppColors.secondary,
                          ),
                          Text(
                            w.format('budget_line', {
                              'budget': chartMoney(e.plannedCents),
                              'actual': chartMoney(e.actualCents),
                              'remaining': chartMoney(
                                e.plannedCents - e.actualCents,
                              ),
                            }),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
    final goals = _Panel(
      title: w.text('active_goals'),
      subtitle: w.text('goals_subtitle'),
      height: 370,
      action: action(
        'dashboard-open-goals',
        w.text('view_goals'),
        DashboardDestination.goals,
      ),
      child: s.activeGoals.isEmpty
          ? _EmptyProgress(message: w.text('no_goal'))
          : ListView(
              children: [
                for (final g in s.activeGoals.take(3))
                  Builder(
                    builder: (context) {
                      final p = s.availability?.goals[g.goal.id];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              g.goal.name,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            if (p == null)
                              _EmptyProgress(
                                message: w.text('secured_unavailable'),
                              )
                            else
                              ValueBar(
                                label: w.text('secured'),
                                cents: p.securedFunding.minorUnits,
                                maximum: g.goal.targetAmount.minorUnits,
                                color: AppColors.secondary,
                                suffix: g.goal.targetAmount.minorUnits > 0
                                    ? '${(p.securedFunding.minorUnits / g.goal.targetAmount.minorUnits * 100).clamp(0, 100).toStringAsFixed(1)} %'
                                    : null,
                              ),
                            Text(
                              w.format('goal_detail', {
                                'remaining': chartMoney(
                                  (p?.remaining ?? g.remaining).minorUnits,
                                ),
                                'due': _date(w, g.goal.targetDate),
                                'projection': _date(w, p?.completionDate),
                              }),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
    );
    final priorities = _Panel(
      title: w.text('priority_path'),
      subtitle: plan == null
          ? w.text('no_plan')
          : w.format('plan_summary', {
              'plan': plan.plan.name,
              'capacity': plan.plan.monthlyCapacity == null
                  ? w.text('unavailable')
                  : chartMoney(plan.plan.monthlyCapacity!.minorUnits),
            }),
      height: 300,
      action: action(
        'dashboard-open-priorities',
        w.text('view_priorities'),
        DashboardDestination.priorities,
      ),
      child: pending == null || pending.isEmpty
          ? _EmptyTimeline(words: w)
          : ListView(
              children: [
                for (final e in pending.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.radio_button_checked,
                          size: 16,
                          color: AppColors.accent,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                plan!.items
                                        .where((i) => i.item.id == e.itemId)
                                        .firstOrNull
                                        ?.source
                                        .label ??
                                    w.text('project_unavailable'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Row(
                                children: [
                                  const Expanded(
                                    child: Divider(color: AppColors.accent),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _date(w, e.completionDate),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (s.availability!.warnings.isNotEmpty)
                  Text(
                    s.availability!.warnings.join('\n'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
    );
    final obligations = _Panel(
      title: w.text('commitments'),
      subtitle: w.text('commitments_subtitle'),
      height: 300,
      action: action(
        'dashboard-open-obligations',
        w.text('view_debts'),
        DashboardDestination.debts,
      ),
      child: ListView(
        children: [
          ValueBar(
            label: w.text('debts'),
            cents: s.debtRemaining.minorUnits,
            maximum: maxObligation,
          ),
          ValueBar(
            label: w.text('receivables'),
            cents: s.incomeReceivableRemaining.minorUnits,
            maximum: maxObligation,
            color: AppColors.secondary,
          ),
          ValueBar(
            label: w.text('recovery'),
            cents: s.recoveryRemaining.minorUnits,
            maximum: maxObligation,
            color: AppColors.accent,
          ),
          Text(
            w.format('net_position', {
              'amount': chartMoney(s.netObligations.minorUnits),
            }),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          TextButton(
            onPressed: () => open(DashboardDestination.receivables),
            child: Text(w.text('view_receivables')),
          ),
        ],
      ),
    );
    final distribution = _Panel(
      title: w.text('account_distribution'),
      subtitle: w.text('account_subtitle'),
      height: 300,
      action: action(
        'dashboard-open-accounts',
        w.text('accounts'),
        DashboardDestination.accounts,
      ),
      child: accounts.isEmpty
          ? EmptyPlot(message: w.text('no_account'))
          : ListView(
              children: [
                for (final a in accounts)
                  ValueBar(
                    label: a.account.name,
                    cents: a.balance.minorUnits,
                    maximum: maxAccount,
                  ),
              ],
            ),
    );
    final health = _Panel(
      title: w.text('reconciliations'),
      subtitle: w.text('reconciliation_subtitle'),
      height: 300,
      child: ListView(
        children: [
          Text(
            w.format('accounts_to_check', {
              'count': s.accounts
                  .where(
                    (a) =>
                        !observed.contains(a.account.id) ||
                        s.reconciliations.any(
                          (c) =>
                              c.accountId == a.account.id &&
                              (c.isOpen || c.status == 'legacy_unfrozen'),
                        ),
                  )
                  .length,
            }),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Text(w.format('open_cases', {'count': openCases.length})),
          Text(
            w.format('residuals', {
              'amount': chartMoney(
                openCases.fold<int>(
                  0,
                  (sum, c) => sum + (c.remaining?.minorUnits.abs() ?? 0),
                ),
              ),
            }),
          ),
          Text(
            w.format('last_observation', {'date': _date(w, dates.lastOrNull)}),
          ),
          const SizedBox(height: 12),
          Text(w.text('residual_notice'), style: const TextStyle(fontSize: 12)),
          TextButton(
            onPressed: () => open(DashboardDestination.accounts),
            child: Text(w.text('check_accounts')),
          ),
        ],
      ),
    );
    final liquidity = _Panel(
      title: w.text('liquidity_trend'),
      subtitle: w.text('liquidity_history'),
      height: 250,
      child: EmptyPlot(
        key: const Key('dashboard-chart-liquidity'),
        message: w.text('liquidity_empty'),
      ),
    );
    return LayoutBuilder(
      builder: (context, box) {
        final desktop = box.maxWidth >= 1000;
        final columns = box.maxWidth < 600 ? 2 : 4;
        Widget pair(Widget a, Widget b) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: a),
              const SizedBox(width: 16),
              Expanded(child: b),
            ],
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              key: const Key('dashboard-kpi-grid'),
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final k in kpis)
                  SizedBox(
                    width: (box.maxWidth - (columns - 1) * 12) / columns,
                    child: FpKpiCard(
                      title: k.title,
                      value: k.value,
                      detail: k.detail,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (desktop) ...[
              pair(flow, alertPanel),
              pair(envelope, donut),
              pair(budget, goals),
              pair(priorities, obligations),
              pair(distribution, health),
              liquidity,
            ] else
              for (final panel in [
                alertPanel,
                flow,
                budget,
                envelope,
                donut,
                goals,
                priorities,
                obligations,
                distribution,
                health,
                liquidity,
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: panel,
                ),
          ],
        );
      },
    );
  }
}

String _date(DashboardV2Words words, DateTime? d) => d == null
    ? words.text('date_unavailable')
    : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.subtitle,
    required this.height,
    required this.child,
    this.action,
  });
  final String title, subtitle;
  final double height;
  final Widget child;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Expanded(child: child),
            if (action != null)
              Align(alignment: Alignment.centerLeft, child: action!),
          ],
        ),
      ),
    ),
  );
}

class _EmptyProgress extends StatelessWidget {
  const _EmptyProgress({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const LinearProgressIndicator(value: 0, minHeight: 8),
      const SizedBox(height: 12),
      Text(message, textAlign: TextAlign.center),
    ],
  );
}

class _EmptyTimeline extends StatelessWidget {
  const _EmptyTimeline({required this.words});
  final DashboardV2Words words;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Row(
        children: [
          Icon(Icons.circle_outlined, color: AppColors.border),
          Expanded(child: Divider()),
          Icon(Icons.circle_outlined, color: AppColors.border),
          Expanded(child: Divider()),
          Icon(Icons.circle_outlined, color: AppColors.border),
        ],
      ),
      const SizedBox(height: 16),
      Text(
        words.text('timeline_empty'),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}
