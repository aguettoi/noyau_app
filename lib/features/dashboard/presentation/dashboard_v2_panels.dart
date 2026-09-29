import 'package:flutter/material.dart';
import '../../../core/theme/app_design_system.dart';
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
    final s = snapshot;
    final report = [...s.report]
      ..sort((a, b) {
        final amount = b.actualCents.compareTo(a.actualCents);
        return amount != 0 ? amount : a.envelopeId.compareTo(b.envelopeId);
      });
    String name(String id) =>
        s.ordinaryEnvelopes.where((e) => e.id == id).firstOrNull?.name ??
        (s.toAllocate?.id == id ? 'À répartir' : 'Enveloppe archivée');
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
          name: 'Autres',
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
        title: 'Liquidités',
        value: chartMoney(s.cashTotal.minorUnits),
        detail: 'Dont espèces : ${chartMoney(s.cashOnHand.minorUnits)}',
      ),
      (
        title: 'Enveloppes',
        value: chartMoney(s.totalEnvelopes.minorUnits),
        detail: 'Affectations, pas un patrimoine supplémentaire',
      ),
      (
        title: 'Revenus',
        value: chartMoney(s.monthlyFlow.income.minorUnits),
        detail: s.period.label,
      ),
      (
        title: 'Dépenses',
        value: chartMoney(s.monthlyFlow.expense.minorUnits),
        detail: s.period.label,
      ),
      (
        title: 'Budget restant',
        value: s.budget.hasPreparedBudget
            ? chartMoney(s.budget.remaining.minorUnits)
            : 'Non disponible',
        detail: 'Budget officiel de la période',
      ),
      (
        title: 'Épargne en comptes',
        value: accounts.any((a) => a.account.type.name == 'savings')
            ? chartMoney(s.savingsAccounts.minorUnits)
            : 'Non disponible',
        detail: 'Déjà comprise dans les liquidités',
      ),
      (
        title: 'Position nette obligations',
        value: chartMoney(s.netObligations.minorUnits),
        detail: 'Créances + Recovery − dettes',
      ),
      (
        title: 'À répartir',
        value: s.toAllocate == null
            ? 'Non disponible'
            : chartMoney(s.toAllocate!.balance.minorUnits),
        detail: 'Enveloppe indépendante des comptes',
      ),
    ];
    final flow = _Panel(
      title: 'Revenus vs dépenses',
      subtitle: '6 derniers mois • mois sans flux non reconstruits',
      height: 310,
      child: IncomeExpenseChart(
        key: const Key('dashboard-chart-income'),
        points: s.history,
      ),
    );
    final alertPanel = _Panel(
      title: 'À faire',
      subtitle: 'Points prioritaires',
      height: 310,
      child: alerts.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: AppColors.secondary,
                    size: 32,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Aucun point critique actuellement.',
                    textAlign: TextAlign.center,
                  ),
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
                    '${alerts.length - 4} autres points à consulter dans les modules.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
    );
    final envelope = _Panel(
      title: 'Dépenses par enveloppe',
      subtitle: 'Top 5 • ${s.period.label} • consommation nette',
      height: 350,
      action: action(
        'dashboard-open-envelopes',
        'Voir toutes les enveloppes',
        DashboardDestination.envelopes,
      ),
      child: KeyedSubtree(
        key: const Key('dashboard-chart-envelopes'),
        child: spending.isEmpty
            ? const EmptyPlot(message: 'Aucune consommation sur cette période.')
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
      title: 'Répartition des dépenses',
      subtitle: '${s.period.label} • consommations positives',
      height: 350,
      child: ExpenseDonut(
        key: const Key('dashboard-chart-donut'),
        segments: segments,
      ),
    );
    final budget = _Panel(
      title: 'Budget vs réel',
      subtitle: s.period.label,
      height: 370,
      action: action(
        'dashboard-open-month-preparation',
        'Préparer le mois',
        DashboardDestination.budget,
      ),
      child: KeyedSubtree(
        key: const Key('dashboard-chart-budget'),
        child: budgets.isEmpty
            ? const EmptyPlot(
                key: Key('dashboard-budget-empty'),
                message: 'Préparez votre premier budget pour activer ce suivi.',
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
                            'Budget ${chartMoney(e.plannedCents)} • Réel ${chartMoney(e.actualCents)} • Reste ${chartMoney(e.plannedCents - e.actualCents)}',
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
      title: 'Objectifs actifs',
      subtitle: 'Sécurisé / restant • déjà inclus dans les enveloppes',
      height: 370,
      action: action(
        'dashboard-open-goals',
        'Voir tous les objectifs',
        DashboardDestination.goals,
      ),
      child: s.activeGoals.isEmpty
          ? const _EmptyProgress(message: 'Aucun objectif actif.')
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
                              const _EmptyProgress(
                                message: 'Financement sécurisé non disponible.',
                              )
                            else
                              ValueBar(
                                label: 'Sécurisé',
                                cents: p.securedFunding.minorUnits,
                                maximum: g.goal.targetAmount.minorUnits,
                                color: AppColors.secondary,
                                suffix: g.goal.targetAmount.minorUnits > 0
                                    ? '${(p.securedFunding.minorUnits / g.goal.targetAmount.minorUnits * 100).clamp(0, 100).toStringAsFixed(1)} %'
                                    : null,
                              ),
                            Text(
                              'Reste : ${chartMoney((p?.remaining ?? g.remaining).minorUnits)}\nÉchéance : ${_date(g.goal.targetDate)} • Projection : ${_date(p?.completionDate)}',
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
      title: 'Priorités — trajectoire',
      subtitle: plan == null
          ? 'Aucun plan actif unique.'
          : '${plan.plan.name} • capacité simulée : ${plan.plan.monthlyCapacity == null ? 'Non disponible' : chartMoney(plan.plan.monthlyCapacity!.minorUnits)} / mois',
      height: 300,
      action: action(
        'dashboard-open-priorities',
        'Voir les priorités',
        DashboardDestination.priorities,
      ),
      child: pending == null || pending.isEmpty
          ? const _EmptyTimeline()
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
                                    'Projet indisponible',
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
                                    _date(e.completionDate),
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
      title: 'Engagements',
      subtitle: 'Restants dus / à recevoir — pas de nouveaux flux',
      height: 300,
      action: action(
        'dashboard-open-obligations',
        'Voir les dettes',
        DashboardDestination.debts,
      ),
      child: ListView(
        children: [
          ValueBar(
            label: 'Dettes',
            cents: s.debtRemaining.minorUnits,
            maximum: maxObligation,
          ),
          ValueBar(
            label: 'Créances',
            cents: s.incomeReceivableRemaining.minorUnits,
            maximum: maxObligation,
            color: AppColors.secondary,
          ),
          ValueBar(
            label: 'Recovery',
            cents: s.recoveryRemaining.minorUnits,
            maximum: maxObligation,
            color: AppColors.accent,
          ),
          Text(
            'Position nette : ${chartMoney(s.netObligations.minorUnits)}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          TextButton(
            onPressed: () => open(DashboardDestination.receivables),
            child: const Text('Voir les créances / Recovery'),
          ),
        ],
      ),
    );
    final distribution = _Panel(
      title: 'Répartition par compte',
      subtitle: 'Positions actuelles • indépendante des enveloppes',
      height: 300,
      action: action(
        'dashboard-open-accounts',
        'Comptes & rapprochements',
        DashboardDestination.accounts,
      ),
      child: accounts.isEmpty
          ? const EmptyPlot(message: 'Aucun compte disponible.')
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
      title: 'Rapprochements',
      subtitle: 'Santé financière • dossiers ouverts',
      height: 300,
      child: ListView(
        children: [
          Text(
            '${s.accounts.where((a) => !observed.contains(a.account.id) || s.reconciliations.any((c) => c.accountId == a.account.id && (c.isOpen || c.status == 'legacy_unfrozen'))).length} compte(s) à contrôler',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Text('${openCases.length} dossier(s) ouvert(s)'),
          Text(
            'Reliquats absolus : ${chartMoney(openCases.fold<int>(0, (sum, c) => sum + (c.remaining?.minorUnits.abs() ?? 0)))}',
          ),
          Text('Dernier constat rapproché : ${_date(dates.lastOrNull)}'),
          const SizedBox(height: 12),
          const Text(
            'Ces reliquats ne corrigent pas la trésorerie. Aucun écart legacy n’est reconstruit.',
            style: TextStyle(fontSize: 12),
          ),
          TextButton(
            onPressed: () => open(DashboardDestination.accounts),
            child: const Text('Contrôler les comptes'),
          ),
        ],
      ),
    );
    const liquidity = _Panel(
      title: 'Évolution des liquidités',
      subtitle:
          'Historique de positions non disponible • aucun snapshot inventé',
      height: 250,
      child: EmptyPlot(
        key: Key('dashboard-chart-liquidity'),
        message:
            'Ce suivi apparaîtra à partir d’un historique fiable après le cutover.',
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
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              k.title,
                              maxLines: 2,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            const SizedBox(height: 8),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                k.value,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              k.detail,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
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

String _date(DateTime? d) => d == null
    ? 'Non disponible'
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
  const _EmptyTimeline();
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
        'Les projections du plan actif apparaîtront ici.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}
