import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/budget_intelligence/application/providers/remote_budget_provider.dart';
import '../features/dashboard/application/providers/dashboard_history_provider.dart';
import '../features/dashboard/application/providers/remote_financial_dashboard_provider.dart';
import '../features/envelopes/application/providers/remote_envelopes_provider.dart';
import '../features/finance/application/providers/account_balance_observation_provider.dart';
import '../features/finance/application/providers/payment_methods_provider.dart';
import '../features/finance/application/providers/remote_account_balances_provider.dart';
import '../features/finance/application/providers/remote_accounts_provider.dart';
import '../features/finance/application/providers/remote_debts_provider.dart';
import '../features/finance/application/providers/remote_household_members_provider.dart';
import '../features/finance/application/providers/remote_transactions_provider.dart';
import '../features/financial_availability/application/providers/financial_availability_provider.dart';
import '../features/priorities/application/providers/remote_priority_plans_provider.dart';
import '../features/savings_goals/application/providers/remote_savings_goals_provider.dart';
import '../features/shopping_list/application/providers/remote_shopping_list_provider.dart';
import '../features/wealth/application/providers/wealth_provider.dart';
import '../features/wealth/application/providers/home_auto_provider.dart';

typedef GlobalRefreshAction = Future<void> Function();

/// Recharges the read models used by the current household without creating
/// any financial operation. Derived providers are invalidated after their
/// canonical sources so every screen observes one coherent refresh cycle.
final globalRefreshActionProvider = Provider<GlobalRefreshAction>((ref) {
  return () async {
    ref.invalidate(remoteAccountsProvider);
    ref.invalidate(remoteAccountBalancesProvider);
    ref.invalidate(remoteEnvelopeHistoryProvider);
    ref.invalidate(remoteEnvelopeBalancesProvider);
    ref.invalidate(remoteEnvelopeMovementsProvider);
    ref.invalidate(remoteTransactionsProvider);
    ref.invalidate(accountTransactionHistoryProvider);
    ref.invalidate(remoteDebtBalancesProvider);
    ref.invalidate(remoteReceivableBalancesProvider);
    ref.invalidate(eligibleRecoverySourcesProvider);
    ref.invalidate(obligationSettlementHistoryProvider);
    ref.invalidate(remoteBudgetPeriodsProvider);
    ref.invalidate(remoteBudgetScenariosProvider);
    ref.invalidate(remoteBudgetRunsProvider);
    ref.invalidate(remoteBudgetRunProvider);
    ref.invalidate(remoteBudgetRunLinesProvider);
    ref.invalidate(remoteBudgetReportingProvider);
    ref.invalidate(remoteHouseholdMembersProvider);
    ref.invalidate(paymentMethodsProvider);
    ref.invalidate(latestAccountBalanceObservationProvider);
    ref.invalidate(accountReconciliationHistoryProvider);
    ref.invalidate(savingsGoalsProvider);
    ref.invalidate(shoppingItemsProvider);
    ref.invalidate(priorityPlansProvider);
    ref.invalidate(dashboardHistoryProvider);
    ref.invalidate(dashboardReconciliationsProvider);
    ref.invalidate(financialAvailabilityProvider);
    ref.invalidate(financialDashboardProvider);
    ref.invalidate(wealthDataProvider);
    ref.invalidate(homeAutoDataProvider);

    await Future.wait<Object?>([
      ref.read(remoteAccountsProvider.future),
      ref.read(remoteAccountBalancesProvider.future),
      ref.read(remoteEnvelopeHistoryProvider.future),
      ref.read(remoteTransactionsProvider.future),
      ref.read(remoteDebtBalancesProvider.future),
      ref.read(remoteReceivableBalancesProvider.future),
      ref.read(remoteBudgetPeriodsProvider.future),
      ref.read(remoteBudgetScenariosProvider.future),
      ref.read(financialDashboardProvider.future),
    ]);
  };
});
