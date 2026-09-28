import 'package:flutter/material.dart';
import '../../../core/theme/app_design_system.dart';
import '../application/dashboard_metrics.dart';
import '../application/providers/remote_financial_dashboard_provider.dart';

/// Charts are accessible labelled bars: never a second accounting engine.
class DashboardV2Panels extends StatelessWidget {
  const DashboardV2Panels({
    super.key,
    required this.snapshot,
    required this.open,
  });
  final FinancialDashboardSnapshot snapshot;
  final ValueChanged<DashboardDestination> open;

  @override
  Widget build(BuildContext context) {
    final report = [...snapshot.report]
      ..sort((a, b) {
        final amount = b.actualCents.compareTo(a.actualCents);
        return amount != 0 ? amount : a.envelopeId.compareTo(b.envelopeId);
      });
    String envelopeName(String id) =>
        snapshot.ordinaryEnvelopes.where((e) => e.id == id).firstOrNull?.name ??
        (snapshot.toAllocate?.id == id ? 'À répartir' : 'Enveloppe archivée');
    final spending = report.where((e) => e.actualCents != 0).toList();
    final budgets = report.where((e) => e.plannedCents > 0).toList();
    final goals = snapshot.activeGoals;
    final projections = snapshot.availability?.goals;
    final projectedGoals =
        goals
            .where((g) => projections?[g.goal.id]?.completionDate != null)
            .toList()
          ..sort(
            (a, b) => projections![a.goal.id]!.completionDate!.compareTo(
              projections[b.goal.id]!.completionDate!,
            ),
          );
    final secured = goals.fold<int>(
      0,
      (s, g) => s + (projections?[g.goal.id]?.securedFunding.minorUnits ?? 0),
    );
    final remaining = goals.fold<int>(0, (s, g) => s + g.remaining.minorUnits);
    final target = goals.fold<int>(
      0,
      (s, g) => s + g.goal.targetAmount.minorUnits,
    );
    final plan = snapshot.activePlan;
    final entries = snapshot.availability?.planEntries[plan?.plan.id];
    final pending = entries
        ?.where((e) => e.remainingNeed.minorUnits > 0)
        .toList();
    final openCases = snapshot.reconciliations.where((e) => e.isOpen).toList();
    final validIds = snapshot.accounts.map((a) => a.account.id).toSet();
    final observed = snapshot.reconciliations
        .where((e) => validIds.contains(e.accountId))
        .map((e) => e.accountId)
        .toSet();
    final dates =
        snapshot.reconciliations
            .where((e) => e.status == 'resolved' || e.status == 'reconciled')
            .map((e) => e.observedAt)
            .toList()
          ..sort();
    final debtDates =
        snapshot.debts.map((e) => e.dueAt).whereType<DateTime>().toList()
          ..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.md),
        DesktopSection(
          title: 'Suivi et santé financière',
          subtitle:
              'Positions actuelles du foyer — indépendantes du filtre des flux.',
          child: Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              _kpi(
                'Épargne en comptes dédiés',
                snapshot.accounts.any((a) => a.account.type.name == 'savings')
                    ? _amount(snapshot.savingsAccounts.minorUnits)
                    : 'Non disponible : aucun compte typé épargne',
                () => open(DashboardDestination.accounts),
              ),
              _kpi(
                'Objectifs : financement sécurisé',
                projections == null ? 'Non disponible' : _amount(secured),
                () => open(DashboardDestination.goals),
              ),
              _kpi(
                'Objectifs actifs : besoin restant',
                _amount(remaining),
                () => open(DashboardDestination.goals),
              ),
              _kpi(
                'Progression globale sécurisée',
                target <= 0 || projections == null
                    ? 'Non disponible'
                    : '${(secured / target * 100).clamp(0, 100).toStringAsFixed(1)} %',
                () => open(DashboardDestination.goals),
              ),
              _kpi(
                'Prochain objectif estimé',
                projectedGoals.isEmpty
                    ? 'Non disponible'
                    : '${projectedGoals.first.goal.name} • ${_date(projections![projectedGoals.first.goal.id]!.completionDate)}',
                () => open(DashboardDestination.goals),
              ),
              _kpi(
                'Dettes ouvertes',
                '${snapshot.debts.length} • prochaine échéance : ${_date(debtDates.firstOrNull)}',
                () => open(DashboardDestination.debts),
              ),
              _kpi(
                'Créances ouvertes',
                '${snapshot.incomeReceivables.length} Income • ${snapshot.recoveryReceivables.length} Recovery',
                () => open(DashboardDestination.receivables),
              ),
              _kpi(
                'Position nette des obligations',
                '${_amount(snapshot.netObligations.minorUnits)}\nCréances + Recovery − dettes',
                () => open(DashboardDestination.debts),
              ),
              _kpi(
                'Enveloppes proches / dépassées',
                '${snapshot.alerts.where((a) => a.title == 'Budget proche de sa limite').length} / ${snapshot.budget.overspentEnvelopeIds.length}',
                () => open(DashboardDestination.budget),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        DesktopSection(
          title: 'Plan PRIOS actif',
          action: TextButton(
            onPressed: () => open(DashboardDestination.priorities),
            child: const Text('Priorités'),
          ),
          child: Text(
            plan == null
                ? 'Aucun plan actif unique.'
                : '${plan.plan.name}\nCapacité mensuelle simulée : ${plan.plan.monthlyCapacity == null ? "Non disponible" : _amount(plan.plan.monthlyCapacity!.minorUnits)}\n${pending?.length ?? 0} priorité(s) restante(s) • ${pending == null ? "Non disponible" : _amount(pending.fold<int>(0, (s, e) => s + e.remainingNeed.minorUnits))}\nProchaine : ${snapshot.nextPriority?.source.label ?? "Aucune"} • ${_date(pending?.firstOrNull?.completionDate)}\n${snapshot.availability?.warnings.join("\n") ?? ""}',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        DesktopSection(
          title: 'Rapprochements',
          action: Flexible(
            child: TextButton(
              onPressed: () => open(DashboardDestination.accounts),
              child: const Text('Contrôler les comptes'),
            ),
          ),
          child: Text(
            '${snapshot.accounts.where((a) => !observed.contains(a.account.id) || snapshot.reconciliations.any((c) => c.accountId == a.account.id && (c.isOpen || c.status == "legacy_unfrozen"))).length} compte(s) à contrôler\n${openCases.length} dossier(s) ouvert(s) • cumul absolu des reliquats : ${_amount(openCases.fold<int>(0, (s, c) => s + (c.remaining?.minorUnits.abs() ?? 0)))}\nDernier constat rapproché : ${_date(dates.lastOrNull)}\nLes reliquats de plusieurs constats ne sont pas une correction de trésorerie. Les constats legacy ne sont pas chiffrés rétroactivement.',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        DesktopSection(
          title: 'Revenus vs dépenses — 6 derniers mois',
          subtitle:
              'Revenus et dépenses reconnus ; les mois sans flux sont omis, pas reconstruits.',
          child: snapshot.history.isEmpty
              ? const Text('Aucun historique de flux disponible.')
              : Column(
                  children: [
                    for (final p in snapshot.history)
                      _BarPair(
                        label:
                            '${p.month.month.toString().padLeft(2, "0")}/${p.month.year}',
                        firstLabel: 'Revenus',
                        first: p.flow.income.minorUnits,
                        secondLabel: 'Dépenses',
                        second: p.flow.expense.minorUnits,
                        scale: snapshot.history.fold<int>(
                          1,
                          (s, p) => [
                            s,
                            p.flow.income.minorUnits,
                            p.flow.expense.minorUnits,
                          ].reduce((a, b) => a > b ? a : b),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: AppSpacing.md),
        DesktopSection(
          title: 'Dépenses par enveloppe',
          subtitle:
              '${snapshot.period.label} • consommation du ledger des enveloppes, pas leur solde.',
          child: spending.isEmpty
              ? const Text('Aucune consommation sur cette période.')
              : Column(
                  children: [
                    for (final row in spending)
                      _BarPair(
                        label: envelopeName(row.envelopeId),
                        firstLabel: 'Consommation nette',
                        first: row.actualCents,
                        scale: spending.fold<int>(
                          1,
                          (s, e) =>
                              e.actualCents.abs() > s ? e.actualCents.abs() : s,
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: AppSpacing.md),
        DesktopSection(
          title: 'Budget vs réel',
          subtitle: snapshot.period.label,
          child: budgets.isEmpty
              ? const Text('Aucun budget officiel sur cette période.')
              : Column(
                  children: [
                    for (final row in budgets)
                      _BarPair(
                        label: envelopeName(row.envelopeId),
                        firstLabel: 'Budget',
                        first: row.plannedCents,
                        secondLabel: 'Consommé',
                        second: row.actualCents,
                        scale: budgets.fold<int>(
                          1,
                          (s, e) => [
                            s,
                            e.plannedCents,
                            e.actualCents.abs(),
                          ].reduce((a, b) => a > b ? a : b),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: AppSpacing.md),
        const DesktopSection(
          title: 'Évolution des liquidités',
          child: Text(
            'Non disponible : aucun historique de positions mensuelles vérifié n’est fourni à ce tableau de bord. Aucun snapshot historique n’est inventé. Ce suivi pourra être établi après le cutover à partir d’un historique fiable.',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        DesktopSection(
          title: 'Objectifs actifs — sécurisé / restant',
          subtitle:
              'Les montants sécurisés sont déjà compris dans les enveloppes et les comptes : ne pas les additionner.',
          child: goals.isEmpty
              ? const Text('Aucun objectif actif.')
              : Column(
                  children: [
                    for (final g in goals)
                      _BarPair(
                        label:
                            '${g.goal.name} • cible ${_amount(g.goal.targetAmount.minorUnits)}',
                        firstLabel: 'Sécurisé',
                        first:
                            projections?[g.goal.id]
                                ?.securedFunding
                                .minorUnits ??
                            0,
                        secondLabel: 'Reste à financer',
                        second:
                            projections?[g.goal.id]?.remaining.minorUnits ??
                            g.remaining.minorUnits,
                        scale: goals.fold<int>(
                          1,
                          (s, e) => e.goal.targetAmount.minorUnits > s
                              ? e.goal.targetAmount.minorUnits
                              : s,
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

Widget _kpi(String title, String value, VoidCallback tap) => SizedBox(
  width: 260,
  child: Card(
    child: InkWell(
      onTap: tap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    ),
  ),
);
String _amount(int cents) =>
    '${(cents / 100).toStringAsFixed(2).replaceAll(".", ",")} MAD';
String _date(DateTime? value) => value == null
    ? 'Non disponible'
    : '${value.day.toString().padLeft(2, "0")}/${value.month.toString().padLeft(2, "0")}/${value.year}';

class _BarPair extends StatelessWidget {
  const _BarPair({
    required this.label,
    required this.firstLabel,
    required this.first,
    required this.scale,
    this.secondLabel,
    this.second,
  });
  final String label, firstLabel;
  final String? secondLabel;
  final int first, scale;
  final int? second;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        _bar(context, firstLabel, first, Theme.of(context).colorScheme.primary),
        if (second != null)
          _bar(
            context,
            secondLabel!,
            second!,
            Theme.of(context).colorScheme.tertiary,
          ),
      ],
    ),
  );
  Widget _bar(BuildContext context, String name, int cents, Color color) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Semantics(
          label: '$label $name ${_amount(cents)}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$name : ${_amount(cents)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 3),
              LinearProgressIndicator(
                value: (cents.abs() / scale).clamp(0, 1),
                minHeight: 10,
                color: color,
              ),
            ],
          ),
        ),
      );
}
