import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/money/money.dart';
import '../../../budget_intelligence/application/budget_reporting.dart';
import '../../../budget_intelligence/application/providers/remote_budget_provider.dart';
import '../../../envelopes/application/providers/remote_envelopes_provider.dart';
import '../../../finance/application/providers/account_balance_observation_provider.dart';
import '../../../finance/application/providers/active_household_provider.dart';
import '../../../finance/application/providers/remote_account_balances_provider.dart';
import '../../../finance/application/providers/remote_accounts_provider.dart';
import '../../../finance/application/providers/remote_debts_provider.dart';
import '../../../finance/application/providers/supabase_client_provider.dart';
import '../../../finance/domain/financial_account.dart';
import '../../../priorities/application/providers/remote_priority_plans_provider.dart';
import '../../../priorities/domain/priority_plan.dart';
import '../../../savings_goals/application/providers/remote_savings_goals_provider.dart';
import '../../../savings_goals/domain/savings_goal.dart';
import '../dashboard_metrics.dart';

class DashboardAccountBalance {
  const DashboardAccountBalance({
    required this.account,
    required this.balance,
    this.observation,
  });

  final FinancialAccount account;
  final Money balance;
  final AccountBalanceObservation? observation;

  Money? get reconciliationDifference =>
      observation == null ? null : observation!.actualBalance - balance;
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

abstract interface class FinancialDashboardGateway {
  Future<List<Map<String, Object?>>> fetchMonthlyTransactions({
    required String householdId,
    required DateTime startsAt,
    required DateTime endsAt,
  });
}

class SupabaseFinancialDashboardGateway implements FinancialDashboardGateway {
  SupabaseFinancialDashboardGateway(this._client);
  final SupabaseClient _client;

  @override
  Future<List<Map<String, Object?>>> fetchMonthlyTransactions({
    required String householdId,
    required DateTime startsAt,
    required DateTime endsAt,
  }) async {
    final rows = await _client
        .from('financial_transactions')
        .select('type, amount')
        .eq('household_id', householdId)
        .isFilter('archived_at', null)
        .gte('occurred_at', startsAt.toUtc().toIso8601String())
        .lt('occurred_at', endsAt.toUtc().toIso8601String());
    return List.unmodifiable(
      (rows as List<dynamic>)
          .map((row) => Map<String, Object?>.from(row as Map))
          .toList(growable: false),
    );
  }
}

final financialDashboardGatewayProvider = Provider<FinancialDashboardGateway>(
  (ref) => SupabaseFinancialDashboardGateway(ref.watch(supabaseClientProvider)),
);

/// Reads and composes canonical ledgers. It has no mutation path.
final financialDashboardProvider = FutureProvider<FinancialDashboardSnapshot>((
  ref,
) async {
  final household = await ref.watch(activeHouseholdProvider.future);
  final householdId = household.householdId;
  if (!household.hasActiveHousehold || householdId == null) {
    throw StateError('Aucun foyer actif sans ambiguïté.');
  }

  final now = DateTime.now();
  final monthStart = DateTime(now.year, now.month);
  final monthEnd = DateTime(now.year, now.month + 1);
  final accounts = await ref.watch(remoteAccountsProvider.future);
  final balances = await ref.watch(remoteAccountBalancesProvider.future);
  final envelopes = await ref.watch(remoteEnvelopeHistoryProvider.future);
  final debts = await ref.watch(remoteDebtBalancesProvider.future);
  final receivables = await ref.watch(remoteReceivableBalancesProvider.future);
  final goals = await ref.watch(savingsGoalsProvider.future);
  final priorities = await ref.watch(priorityPlansProvider.future);
  final periods = await ref.watch(remoteBudgetPeriodsProvider.future);
  final transactionRows = await ref
      .watch(financialDashboardGatewayProvider)
      .fetchMonthlyTransactions(
        householdId: householdId,
        startsAt: monthStart,
        endsAt: monthEnd,
      );

  final accountBalances = <DashboardAccountBalance>[];
  for (final account in accounts.where((item) => !item.isArchived)) {
    final observation = await ref.watch(
      latestAccountBalanceObservationProvider(account.id).future,
    );
    accountBalances.add(
      DashboardAccountBalance(
        account: account,
        balance: balances[account.id] ?? const Money.fromMinorUnits(0),
        observation: observation,
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
    return !now.isBefore(starts) && now.isBefore(ends);
  }).firstOrNull;
  final report = currentPeriod == null
      ? const <RemoteBudgetReportRow>[]
      : await ref.watch(
          remoteBudgetReportingProvider((
            horizon: BudgetHorizon.monthly,
            period: currentPeriod,
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
  final flow = DashboardMonthlyFlow.fromTransactionRows(transactionRows);
  final activeGoals = goals
      .where((item) => item.goal.status == SavingsGoalStatus.active)
      .toList(growable: false);
  final activePlan = priorities
      .where((item) => item.plan.status == PriorityPlanStatus.active)
      .firstOrNull;
  final nextPriority = activePlan?.items.firstOrNull;
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
    alerts: _buildAlerts(
      accounts: accountBalances,
      envelopes: ordinaryEnvelopes,
      toAllocate: toAllocate,
      budget: budget,
      debts: openDebts,
      incomeReceivables: incomeReceivables,
      recoveryReceivables: recoveryReceivables,
      now: now,
    ),
  );
});

Money _sum(Iterable<int> values) =>
    Money.fromMinorUnits(values.fold(0, (sum, item) => sum + item));

List<DashboardAlert> _buildAlerts({
  required List<DashboardAccountBalance> accounts,
  required List<RemoteEnvelopeBalance> envelopes,
  required RemoteEnvelopeBalance? toAllocate,
  required DashboardBudgetSummary budget,
  required List<RemoteDebtBalance> debts,
  required List<RemoteReceivableBalance> incomeReceivables,
  required List<RemoteReceivableBalance> recoveryReceivables,
  required DateTime now,
}) {
  final alerts = <DashboardAlert>[];
  for (final account in accounts) {
    if (account.balance.minorUnits < 0) {
      alerts.add(
        DashboardAlert(
          title: 'Compte négatif',
          detail: '${account.account.name} est négatif.',
          severity: DashboardAlertSeverity.warning,
        ),
      );
    }
    final difference = account.reconciliationDifference;
    if (difference != null && difference.minorUnits != 0) {
      alerts.add(
        DashboardAlert(
          title: 'Écart de rapprochement',
          detail: '${account.account.name} présente un écart constaté.',
          severity: DashboardAlertSeverity.warning,
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
        ),
      );
    }
  }
  if (budget.overspentEnvelopeIds.isNotEmpty) {
    alerts.add(
      const DashboardAlert(
        title: 'Budget dépassé',
        detail: 'Au moins une enveloppe dépasse le budget mensuel prévu.',
        severity: DashboardAlertSeverity.warning,
      ),
    );
  }
  if ((toAllocate?.balance.minorUnits ?? 0) > 0) {
    alerts.add(
      const DashboardAlert(
        title: 'Fonds à répartir',
        detail: 'Une partie des fonds attend encore une affectation.',
        severity: DashboardAlertSeverity.attention,
      ),
    );
  }
  final dueSoon = DateTime(now.year, now.month, now.day + 7);
  for (final obligation in debts) {
    if (obligation.dueAt != null && !obligation.dueAt!.isAfter(dueSoon)) {
      alerts.add(
        const DashboardAlert(
          title: 'Dette à échéance proche',
          detail: 'Une dette ouverte arrive à échéance.',
          severity: DashboardAlertSeverity.attention,
        ),
      );
      break;
    }
  }
  for (final obligation in [...incomeReceivables, ...recoveryReceivables]) {
    if (obligation.dueAt != null && !obligation.dueAt!.isAfter(dueSoon)) {
      alerts.add(
        const DashboardAlert(
          title: 'Créance à suivre',
          detail: 'Une créance ouverte arrive à échéance.',
          severity: DashboardAlertSeverity.attention,
        ),
      );
      break;
    }
  }
  return List.unmodifiable(alerts);
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
