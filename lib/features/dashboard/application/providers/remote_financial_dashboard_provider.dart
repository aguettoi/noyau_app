import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/money/money.dart';
import '../../../budget_intelligence/application/budget_reporting.dart';
import '../../../budget_intelligence/application/providers/remote_budget_provider.dart';
import '../../../envelopes/application/providers/remote_envelopes_provider.dart';
import '../../../finance/application/providers/account_balance_observation_provider.dart';
import '../../../finance/application/providers/active_household_provider.dart';
import '../../../finance/application/providers/remote_account_balances_provider.dart';
import '../../../finance/application/providers/remote_accounts_provider.dart';
import '../../../finance/application/providers/remote_debts_provider.dart';
import '../../../finance/domain/financial_account.dart';
import '../../../financial_availability/application/providers/financial_availability_provider.dart';
import '../../../financial_availability/domain/financial_availability.dart';
import '../../../priorities/application/providers/remote_priority_plans_provider.dart';
import '../../../priorities/domain/priority_plan.dart';
import '../../../savings_goals/application/providers/remote_savings_goals_provider.dart';
import '../../../savings_goals/domain/savings_goal.dart';
import '../dashboard_metrics.dart';
import 'dashboard_history_provider.dart';

class DashboardAccountBalance {
  const DashboardAccountBalance({
    required this.account,
    required this.balance,
    this.observation,
  });

  final FinancialAccount account;
  final Money balance;
  final AccountBalanceObservation? observation;

  Money? get reconciliationDifference => observation == null
      ? null
      : observation!.remainingDifference ??
            observation!.differenceSnapshot ??
            observation!.actualBalance - balance;
}

class DashboardBudgetSummary {
  const DashboardBudgetSummary({
    required this.period,
    required this.planned,
    required this.consumed,
    required this.overspentEnvelopeIds,
  });

  final RemoteBudgetPeriod? period;
  final Money planned;
  final Money consumed;
  final Set<String> overspentEnvelopeIds;

  bool get hasPreparedBudget => period != null && planned.minorUnits > 0;
  Money get remaining => planned - consumed;
  double? get consumptionRate =>
      planned.minorUnits <= 0 ? null : consumed.minorUnits / planned.minorUnits;
}

class FinancialDashboardSnapshot {
  const FinancialDashboardSnapshot({
    required this.accounts,
    required this.ordinaryEnvelopes,
    required this.toAllocate,
    required this.budget,
    required this.monthlyFlow,
    required this.debts,
    required this.incomeReceivables,
    required this.recoveryReceivables,
    required this.activeGoals,
    required this.nextPriority,
    required this.alerts,
    this.report = const [],
    this.history = const [],
    this.reconciliations = const [],
    this.activePlan,
    this.availability,
    this.period = DashboardPeriod.currentMonth,
  });

  final List<DashboardAccountBalance> accounts;
  final List<RemoteEnvelopeBalance> ordinaryEnvelopes;
  final RemoteEnvelopeBalance? toAllocate;
  final DashboardBudgetSummary budget;
  final DashboardMonthlyFlow monthlyFlow;
  final List<RemoteDebtBalance> debts;
  final List<RemoteReceivableBalance> incomeReceivables;
  final List<RemoteReceivableBalance> recoveryReceivables;
  final List<SavingsGoalProgress> activeGoals;
  final PriorityPlanItemView? nextPriority;
  final List<DashboardAlert> alerts;
  final List<RemoteBudgetReportRow> report;
  final List<DashboardFlowPoint> history;
  final List<DashboardReconciliation> reconciliations;
  final PriorityPlanView? activePlan;
  final FinancialAvailabilitySnapshot? availability;
  final DashboardPeriod period;

  bool get isEmpty =>
      accounts.isEmpty &&
      ordinaryEnvelopes.isEmpty &&
      toAllocate == null &&
      debts.isEmpty &&
      incomeReceivables.isEmpty &&
      recoveryReceivables.isEmpty &&
      history.isEmpty;
  Money get totalEnvelopes =>
      ordinaryEnvelopeTotal +
      (toAllocate?.balance ?? const Money.fromMinorUnits(0));
  Money get savingsAccounts => _total(
    accounts
        .where((a) => a.account.type == FinancialAccountType.savings)
        .map((a) => a.balance),
  );
  Money get netObligations =>
      incomeReceivableRemaining + recoveryRemaining - debtRemaining;

  Money get cashTotal => Money.fromMinorUnits(
    accounts.fold(0, (sum, item) => sum + item.balance.minorUnits),
  );

  Money get cashOnHand => Money.fromMinorUnits(
    accounts
        .where((item) => item.account.type == FinancialAccountType.cash)
        .fold(0, (sum, item) => sum + item.balance.minorUnits),
  );

  Money get ordinaryEnvelopeTotal => Money.fromMinorUnits(
    ordinaryEnvelopes.fold(0, (sum, item) => sum + item.balance.minorUnits),
  );

  Money get debtRemaining => _total(debts.map((item) => item.remainingAmount));
  Money get incomeReceivableRemaining =>
      _total(incomeReceivables.map((item) => item.remainingAmount));
  Money get recoveryRemaining =>
      _total(recoveryReceivables.map((item) => item.remainingAmount));

  static Money _total(Iterable<Money> values) => Money.fromMinorUnits(
    values.fold(0, (sum, item) => sum + item.minorUnits),
  );
}

/// Reads and composes canonical ledgers. It has no mutation path.
final financialDashboardProvider = FutureProvider<FinancialDashboardSnapshot>((
  ref,
) async {
  final household = await ref.watch(activeHouseholdProvider.future);
  final householdId = household.householdId;
  if (!household.hasActiveHousehold || householdId == null) {
    throw StateError('Aucun foyer actif sans ambiguïté.');
  }

  final now = ref.watch(dashboardClockProvider);
  final selectedPeriod = ref.watch(dashboardPeriodProvider);
  final bounds = selectedPeriod.bounds(now);
  final accounts = await ref.watch(remoteAccountsProvider.future);
  final balances = await ref.watch(remoteAccountBalancesProvider.future);
  final envelopes = await ref.watch(remoteEnvelopeHistoryProvider.future);
  final debts = await ref.watch(remoteDebtBalancesProvider.future);
  final receivables = await ref.watch(remoteReceivableBalancesProvider.future);
  final goals = await ref.watch(savingsGoalsProvider.future);
  final priorities = await ref.watch(priorityPlansProvider.future);
  final periods = await ref.watch(remoteBudgetPeriodsProvider.future);
  final transactionRows = await ref.watch(dashboardHistoryProvider.future);
  final reconciliations = await ref.watch(
    dashboardReconciliationsProvider.future,
  );
  final availability = await ref.watch(financialAvailabilityProvider.future);

  final accountBalances = <DashboardAccountBalance>[];
  for (final account in accounts.where(
    (item) => !item.isArchived && !item.isSystem,
  )) {
    accountBalances.add(
      DashboardAccountBalance(
        account: account,
        balance: balances[account.id] ?? const Money.fromMinorUnits(0),
      ),
    );
  }

  final currentPeriod = periods.where((period) {
    final starts = DateTime(
      period.startsOn.year,
      period.startsOn.month,
      period.startsOn.day,
    );
    final ends = DateTime(
      period.endsOn.year,
      period.endsOn.month,
      period.endsOn.day + 1,
    );
    return starts.isBefore(bounds.end) && ends.isAfter(bounds.start);
  }).firstOrNull;
  final report = await ref.watch(
    remoteBudgetReportingProvider((
      horizon: BudgetHorizon.monthly,
      period: RemoteBudgetPeriod(
        id: 'dashboard-range',
        householdId: householdId,
        startsOn: bounds.start,
        endsOn: DateTime(bounds.end.year, bounds.end.month, bounds.end.day - 1),
        status: 'projection',
      ),
    )).future,
  );
  final budget = DashboardBudgetSummary(
    period: currentPeriod,
    planned: _sum(report.map((item) => item.plannedCents)),
    consumed: _sum(report.map((item) => item.actualCents)),
    overspentEnvelopeIds: {
      for (final item in report)
        if (item.plannedCents > 0 && item.actualCents > item.plannedCents)
          item.envelopeId,
    },
  );
  final ordinaryEnvelopes = envelopes
      .where((item) => !item.isArchived && !item.isSystem)
      .toList(growable: false);
  final toAllocate = envelopes
      .where((item) => item.isSystem && item.systemCode == 'to_allocate')
      .firstOrNull;
  final flow = DashboardMonthlyFlow.fromTransactionRows(
    transactionRows.where((row) {
      final date = DateTime.parse(row['occurred_at'] as String).toLocal();
      return !date.isBefore(bounds.start) && date.isBefore(bounds.end);
    }),
  );
  final activeGoals = goals
      .where((item) => item.goal.status == SavingsGoalStatus.active)
      .toList(growable: false);
  final activePlans = priorities
      .where((item) => item.plan.status == PriorityPlanStatus.active)
      .toList();
  final activePlan = activePlans.length == 1 ? activePlans.single : null;
  final pendingEntries =
      availability.planEntries[activePlan?.plan.id] ??
      const <PlanProjectionEntry>[];
  final nextId = pendingEntries
      .where((e) => e.remainingNeed.minorUnits > 0)
      .firstOrNull
      ?.itemId;
  final nextPriority = activePlan?.items
      .where((e) => e.item.id == nextId)
      .firstOrNull;
  final openDebts = debts
      .where((item) => item.remainingAmount.minorUnits > 0)
      .toList(growable: false);
  final incomeReceivables = receivables
      .where(
        (item) => item.kind == 'income' && item.remainingAmount.minorUnits > 0,
      )
      .toList(growable: false);
  final recoveryReceivables = receivables
      .where(
        (item) =>
            item.kind == 'recovery' && item.remainingAmount.minorUnits > 0,
      )
      .toList(growable: false);

  return FinancialDashboardSnapshot(
    accounts: List.unmodifiable(accountBalances),
    ordinaryEnvelopes: List.unmodifiable(ordinaryEnvelopes),
    toAllocate: toAllocate,
    budget: budget,
    monthlyFlow: flow,
    debts: List.unmodifiable(openDebts),
    incomeReceivables: List.unmodifiable(incomeReceivables),
    recoveryReceivables: List.unmodifiable(recoveryReceivables),
    activeGoals: List.unmodifiable(activeGoals),
    nextPriority: nextPriority,
    alerts: buildDashboardAlerts(
      accounts: accountBalances,
      envelopes: ordinaryEnvelopes,
      toAllocate: toAllocate,
      budget: budget,
      debts: openDebts,
      incomeReceivables: incomeReceivables,
      recoveryReceivables: recoveryReceivables,
      now: now,
      report: report,
      reconciliations: reconciliations,
      goals: activeGoals,
      availability: availability,
      activePlan: activePlan,
      thresholds: ref.watch(dashboardThresholdsProvider),
    ),
    report: report,
    history: dashboardFlowSeries(
      transactionRows.where(
        (row) => !DateTime.parse(
          row['occurred_at'] as String,
        ).toLocal().isBefore(DateTime(now.year, now.month - 5)),
      ),
    ),
    reconciliations: reconciliations,
    activePlan: activePlan,
    availability: availability,
    period: selectedPeriod,
  );
});

Money _sum(Iterable<int> values) =>
    Money.fromMinorUnits(values.fold(0, (sum, item) => sum + item));

List<DashboardAlert> buildDashboardAlerts({
  required List<DashboardAccountBalance> accounts,
  required List<RemoteEnvelopeBalance> envelopes,
  required RemoteEnvelopeBalance? toAllocate,
  required DashboardBudgetSummary budget,
  required List<RemoteDebtBalance> debts,
  required List<RemoteReceivableBalance> incomeReceivables,
  required List<RemoteReceivableBalance> recoveryReceivables,
  required DateTime now,
  required List<RemoteBudgetReportRow> report,
  required List<DashboardReconciliation> reconciliations,
  required List<SavingsGoalProgress> goals,
  required FinancialAvailabilitySnapshot availability,
  required PriorityPlanView? activePlan,
  required DashboardThresholds thresholds,
}) {
  final alerts = <DashboardAlert>[];
  for (final account in accounts) {
    if (account.balance.minorUnits < 0) {
      alerts.add(
        DashboardAlert(
          title: 'Compte négatif',
          detail: '${account.account.name} est négatif.',
          severity: DashboardAlertSeverity.warning,
          destination: DashboardDestination.accounts,
        ),
      );
    }
    final cases = reconciliations
        .where((c) => c.accountId == account.account.id)
        .toList();
    final open = cases.where((c) => c.isOpen).length;
    if (open > 0) {
      alerts.add(
        DashboardAlert(
          title: 'Écart de rapprochement',
          detail: '${account.account.name} : $open dossier(s) ouvert(s).',
          severity: DashboardAlertSeverity.warning,
        ),
      );
    }
    final dates = cases.map((c) => c.observedAt).toList()..sort();
    if (dates.isEmpty ||
        now.difference(dates.last).inDays > thresholds.reconciliationDays ||
        cases.every((c) => c.status == 'legacy_unfrozen')) {
      alerts.add(
        DashboardAlert(
          title: account.account.type == FinancialAccountType.cash
              ? 'Espèces à contrôler'
              : 'Compte à rapprocher',
          detail:
              '${account.account.name} : ${dates.isEmpty ? "aucun constat" : "constat ancien ou historique non figé"}.',
          severity: DashboardAlertSeverity.attention,
        ),
      );
    }
  }
  for (final envelope in envelopes) {
    if (envelope.balance.minorUnits < 0) {
      alerts.add(
        DashboardAlert(
          title: 'Enveloppe négative',
          detail: '${envelope.name} est à découvert.',
          severity: DashboardAlertSeverity.warning,
          destination: DashboardDestination.envelopes,
        ),
      );
    }
  }
  for (final row in report) {
    if (row.plannedCents <= 0 ||
        row.actualCents < row.plannedCents * thresholds.budgetWarning) {
      continue;
    }
    final name =
        envelopes.where((e) => e.id == row.envelopeId).firstOrNull?.name ??
        'Enveloppe';
    alerts.add(
      DashboardAlert(
        title: row.actualCents > row.plannedCents
            ? 'Budget dépassé'
            : 'Budget proche de sa limite',
        detail:
            '$name : ${(row.actualCents / 100).toStringAsFixed(2)} / ${(row.plannedCents / 100).toStringAsFixed(2)} MAD ; reste ${((row.plannedCents - row.actualCents) / 100).toStringAsFixed(2)} MAD.',
        severity: row.actualCents > row.plannedCents
            ? DashboardAlertSeverity.critical
            : DashboardAlertSeverity.warning,
        destination: DashboardDestination.budget,
      ),
    );
  }
  if ((toAllocate?.balance.minorUnits ?? 0) > 0) {
    alerts.add(
      const DashboardAlert(
        title: 'Fonds à répartir',
        detail: 'Une partie des fonds attend encore une affectation.',
        severity: DashboardAlertSeverity.attention,
        destination: DashboardDestination.envelopes,
      ),
    );
  }
  final dueSoon = DateTime(now.year, now.month, now.day + thresholds.dueDays);
  for (final obligation in debts) {
    if (obligation.dueAt != null && !obligation.dueAt!.isAfter(dueSoon)) {
      alerts.add(
        DashboardAlert(
          title:
              obligation.dueAt!.isBefore(DateTime(now.year, now.month, now.day))
              ? 'Dette en retard'
              : 'Dette à échéance proche',
          detail:
              '${obligation.description} : ${obligation.remainingAmount.dirhams.toStringAsFixed(2)} MAD restant.',
          severity: DashboardAlertSeverity.warning,
          destination: DashboardDestination.debts,
        ),
      );
    }
  }
  for (final obligation in [...incomeReceivables, ...recoveryReceivables]) {
    if (obligation.dueAt != null && !obligation.dueAt!.isAfter(dueSoon)) {
      alerts.add(
        DashboardAlert(
          title: 'Créance à suivre',
          detail:
              '${obligation.description} : ${obligation.remainingAmount.dirhams.toStringAsFixed(2)} MAD à recevoir.',
          severity: DashboardAlertSeverity.attention,
          destination: DashboardDestination.receivables,
        ),
      );
    }
  }
  if (recoveryReceivables.isNotEmpty) {
    alerts.add(
      DashboardAlert(
        title: 'Recovery restant',
        detail: '${recoveryReceivables.length} remboursement(s) à suivre.',
        severity: DashboardAlertSeverity.attention,
        destination: DashboardDestination.receivables,
      ),
    );
  }
  for (final goal in goals) {
    final projection = availability.goals[goal.goal.id];
    if (goal.remaining.minorUnits > 0 &&
        goal.goal.targetDate != null &&
        goal.goal.targetDate!.isBefore(
          DateTime(now.year, now.month, now.day),
        )) {
      alerts.add(
        DashboardAlert(
          title: 'Objectif en retard',
          detail: goal.goal.name,
          severity: DashboardAlertSeverity.warning,
          destination: DashboardDestination.goals,
        ),
      );
    }
    if (projection == null || projection.securedFunding.minorUnits <= 0) {
      alerts.add(
        DashboardAlert(
          title: 'Objectif sans financement sécurisé',
          detail: goal.goal.name,
          severity: DashboardAlertSeverity.attention,
          destination: DashboardDestination.goals,
        ),
      );
    }
  }
  if (activePlan != null) {
    final entries =
        availability.planEntries[activePlan.plan.id] ??
        const <PlanProjectionEntry>[];
    if ((activePlan.plan.monthlyCapacity?.minorUnits ?? 0) <= 0 ||
        entries.any(
          (e) => e.remainingNeed.minorUnits > 0 && e.completionDate == null,
        )) {
      alerts.add(
        DashboardAlert(
          title: 'Projection PRIOS à vérifier',
          detail:
              'Capacité ou données insuffisantes pour ${activePlan.plan.name}.',
          severity: DashboardAlertSeverity.warning,
          destination: DashboardDestination.priorities,
        ),
      );
    }
    for (final item in activePlan.items) {
      final date = entries
          .where((e) => e.itemId == item.item.id)
          .firstOrNull
          ?.completionDate;
      if (date != null &&
          item.source.date != null &&
          date.isAfter(item.source.date!)) {
        alerts.add(
          DashboardAlert(
            title: 'Priorité au-delà de la date cible',
            detail: item.source.label,
            severity: DashboardAlertSeverity.warning,
            destination: DashboardDestination.priorities,
          ),
        );
      }
    }
  }
  alerts.sort((a, b) {
    final level = b.severity.index.compareTo(a.severity.index);
    return level != 0
        ? level
        : '${a.title} ${a.detail}'.compareTo('${b.title} ${b.detail}');
  });
  return List.unmodifiable(alerts);
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
