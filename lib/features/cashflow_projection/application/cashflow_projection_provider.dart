import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../budget_intelligence/application/providers/remote_budget_provider.dart';
import '../../budget_intelligence/domain/budget_intelligence.dart';
import '../../envelopes/application/providers/remote_envelopes_provider.dart';
import '../../finance/application/providers/remote_account_balances_provider.dart';
import '../../finance/application/providers/remote_accounts_provider.dart';
import '../../finance/domain/financial_account.dart';
import '../../recurring_finance/application/recurring_finance_provider.dart';
import '../../recurring_finance/domain/recurring_finance.dart';
import '../../wealth/application/providers/wealth_provider.dart';
import '../domain/cashflow_projection.dart';

final projectionHorizonProvider = StateProvider<ProjectionHorizon>(
  (_) => ProjectionHorizon.nextMonth,
);
final projectionScenarioIdProvider = StateProvider<String?>((_) => null);

final cashflowProjectionProvider = FutureProvider<CashflowProjection>((
  ref,
) async {
  final horizon = ref.watch(projectionHorizonProvider);
  final selectedScenarioId = ref.watch(projectionScenarioIdProvider);
  final results = await Future.wait([
    ref.watch(remoteAccountsProvider.future),
    ref.watch(remoteAccountBalancesProvider.future),
    ref.watch(remoteEnvelopeBalancesProvider.future),
    ref.watch(recurringIntentionsProvider.future),
    ref.watch(expectedOccurrencesProvider.future),
    ref.watch(wealthDataProvider.future),
    ref.watch(remoteBudgetScenariosProvider.future),
  ]);
  final accounts = results[0] as List<FinancialAccount>;
  final allBalances = results[1] as Map<String, Money>;
  final envelopes = results[2] as List<RemoteEnvelopeBalance>;
  final intentions = results[3] as List<RecurringFinancialIntention>;
  final persisted = results[4] as List<ExpectedFinancialOccurrence>;
  final wealth = results[5] as WealthData;
  final scenarios = results[6] as List<BudgetScenario>;
  final selectedScenario = scenarios
      .where((scenario) => scenario.id == selectedScenarioId)
      .firstOrNull;
  final applicableScenario =
      selectedScenario ??
      scenarios
          .where((scenario) => scenario.active && scenario.isDefault)
          .firstOrNull ??
      scenarios.where((scenario) => scenario.active).firstOrNull;
  final now = DateTime.now();
  final through = projectionThrough(now, horizon);
  final liquidAccountIds = accounts
      .where(
        (a) =>
            !a.isArchived &&
            (a.type == FinancialAccountType.bank ||
                a.type == FinancialAccountType.cash ||
                a.type == FinancialAccountType.savings),
      )
      .map((a) => a.id)
      .toSet();
  final balances = <String, Money>{
    for (final id in liquidAccountIds)
      if (allBalances[id] != null) id: allBalances[id]!,
  };
  final occurrences = expandExpectedOccurrences(
    asOf: now,
    through: through,
    intentions: intentions,
    persisted: persisted,
  );
  return buildCashflowProjection(
    asOf: now,
    through: through,
    accountBalances: balances,
    envelopeBalances: {for (final e in envelopes) e.id: e.balance},
    occurrences: occurrences,
    financings: wealth.financings,
    certaintyByIntention: {
      for (final intention in intentions)
        intention.id: intention.certainty == RecurringCertainty.certain
            ? ProjectionCertainty.certain
            : ProjectionCertainty.estimated,
    },
    scenarioName: applicableScenario?.name,
  );
});
