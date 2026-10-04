import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/app/global_refresh_provider.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/budget_intelligence/application/providers/remote_budget_provider.dart';
import 'package:noyau_app/features/budget_intelligence/domain/budget_intelligence.dart';
import 'package:noyau_app/features/dashboard/application/dashboard_metrics.dart';
import 'package:noyau_app/features/dashboard/application/providers/remote_financial_dashboard_provider.dart';
import 'package:noyau_app/features/envelopes/application/providers/remote_envelopes_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_account_balances_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_accounts_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_debts_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_transactions_provider.dart';
import 'package:noyau_app/features/finance/domain/financial_account.dart';
import 'package:noyau_app/features/finance/domain/transaction_history_item.dart';

void main() {
  test(
    'le refresh recharge toutes les sources canoniques obligatoires',
    () async {
      final calls = <String, int>{};
      int hit(String name) =>
          calls.update(name, (value) => value + 1, ifAbsent: () => 1);

      final container = ProviderContainer(
        overrides: [
          remoteAccountsProvider.overrideWith((ref) async {
            hit('accounts');
            return const <FinancialAccount>[];
          }),
          remoteAccountBalancesProvider.overrideWith((ref) async {
            hit('accountBalances');
            return const <String, Money>{};
          }),
          remoteEnvelopeHistoryProvider.overrideWith((ref) async {
            hit('envelopes');
            return const <RemoteEnvelopeBalance>[];
          }),
          remoteTransactionsProvider.overrideWith((ref) async {
            hit('transactions');
            return const <TransactionHistoryItem>[];
          }),
          remoteDebtBalancesProvider.overrideWith((ref) async {
            hit('debts');
            return const <RemoteDebtBalance>[];
          }),
          remoteReceivableBalancesProvider.overrideWith((ref) async {
            hit('receivables');
            return const <RemoteReceivableBalance>[];
          }),
          remoteBudgetPeriodsProvider.overrideWith((ref) async {
            hit('budgetPeriods');
            return const <RemoteBudgetPeriod>[];
          }),
          remoteBudgetScenariosProvider.overrideWith((ref) async {
            hit('budgetScenarios');
            return const <BudgetScenario>[];
          }),
          financialDashboardProvider.overrideWith((ref) async {
            hit('dashboard');
            return _emptyDashboard;
          }),
        ],
      );
      addTearDown(container.dispose);

      await container.read(globalRefreshActionProvider)();
      const requiredSources = {
        'accounts',
        'accountBalances',
        'envelopes',
        'transactions',
        'debts',
        'receivables',
        'budgetPeriods',
        'budgetScenarios',
        'dashboard',
      };
      expect(calls.keys, containsAll(requiredSources));
      expect(calls.values, everyElement(greaterThan(0)));

      final firstCycle = Map<String, int>.from(calls);
      await container.read(globalRefreshActionProvider)();
      for (final source in requiredSources) {
        expect(calls[source], greaterThan(firstCycle[source]!));
      }
    },
  );
}

const _emptyDashboard = FinancialDashboardSnapshot(
  accounts: [],
  ordinaryEnvelopes: [],
  toAllocate: null,
  budget: DashboardBudgetSummary(
    period: null,
    planned: Money.fromMinorUnits(0),
    consumed: Money.fromMinorUnits(0),
    overspentEnvelopeIds: {},
  ),
  monthlyFlow: DashboardMonthlyFlow(
    income: Money.fromMinorUnits(0),
    expense: Money.fromMinorUnits(0),
  ),
  debts: [],
  incomeReceivables: [],
  recoveryReceivables: [],
  activeGoals: [],
  nextPriority: null,
  alerts: [],
);
