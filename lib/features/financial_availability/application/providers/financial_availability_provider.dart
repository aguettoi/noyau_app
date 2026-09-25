import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/money/money.dart';
import '../../../envelopes/application/providers/remote_envelopes_provider.dart';
import '../../../finance/application/providers/remote_account_balances_provider.dart';
import '../../../finance/application/providers/remote_accounts_provider.dart';
import '../../../finance/application/providers/remote_debts_provider.dart';
import '../../../finance/domain/financial_account.dart';
import '../../../savings_goals/domain/savings_goal.dart';
import '../../../priorities/application/providers/remote_priority_plans_provider.dart';
import '../../../priorities/domain/priority_plan.dart';
import '../../../savings_goals/application/providers/remote_savings_goals_provider.dart';
import '../../domain/financial_availability.dart';

/// One read-only composition of canonical account, envelope, obligation,
/// objective and PRIOS data. It deliberately has no gateway or mutation path.
final financialAvailabilityProvider =
    FutureProvider<FinancialAvailabilitySnapshot>((ref) async {
      final results = await Future.wait([
        ref.watch(remoteAccountsProvider.future),
        ref.watch(remoteAccountBalancesProvider.future),
        ref.watch(remoteEnvelopeHistoryProvider.future),
        ref.watch(remoteDebtBalancesProvider.future),
        ref.watch(remoteReceivableBalancesProvider.future),
        ref.watch(savingsGoalsProvider.future),
        ref.watch(priorityPlansProvider.future),
      ]);
      final accounts = results[0] as List<FinancialAccount>;
      final balances = results[1] as Map<String, Money>;
      final envelopes = results[2] as List<RemoteEnvelopeBalance>;
      final debts = results[3] as List<RemoteDebtBalance>;
      final receivables = results[4] as List<RemoteReceivableBalance>;
      final goals = results[5] as List<SavingsGoalProgress>;
      final plans = results[6] as List<PriorityPlanView>;
      final liquidity = Money.fromMinorUnits(
        accounts
            .where((account) => !account.isArchived)
            .fold<int>(
              0,
              (sum, account) => sum + (balances[account.id]?.minorUnits ?? 0),
            ),
      );
      final debtTotal = Money.fromMinorUnits(
        debts.fold<int>(
          0,
          (sum, debt) => sum + debt.remainingAmount.minorUnits,
        ),
      );
      final potential = Money.fromMinorUnits(
        receivables.fold<int>(
          0,
          (sum, item) => sum + item.remainingAmount.minorUnits,
        ),
      );
      return projectFinancialAvailability(
        FinancialAvailabilityInput(
          liquidity: liquidity,
          envelopes: envelopes
              .map(
                (item) => AvailabilityEnvelope(
                  id: item.id,
                  balance: item.balance,
                  isToAllocate:
                      item.isSystem && item.systemCode == 'to_allocate',
                ),
              )
              .toList(growable: false),
          debtCommitments: debtTotal,
          potentialReceivables: potential,
          goals: goals
              .map(
                (item) => AvailabilityGoal(
                  id: item.goal.id,
                  envelopeId: item.goal.fundingEnvelopeId,
                  target: item.goal.targetAmount,
                  accumulated: item.accumulated,
                  isActive: item.goal.status.name == 'active',
                ),
              )
              .toList(growable: false),
          plans: plans
              .map(
                (plan) => AvailabilityPlan(
                  id: plan.plan.id,
                  isActive: plan.plan.status.name == 'active',
                  monthlyCapacity: plan.plan.monthlyCapacity,
                  items: plan.items
                      .map(
                        (item) => AvailabilityPlanItem(
                          id: item.item.id,
                          rank: item.item.rank,
                          type:
                              item.item.sourceType ==
                                  PrioritySourceType.budgetGoal
                              ? AvailabilitySourceType.goal
                              : AvailabilitySourceType.shopping,
                          sourceId: item.item.sourceId,
                          status: item.source.status,
                          goalId: item.source.goalId,
                          estimatedAmount: item.source.estimatedNeed,
                        ),
                      )
                      .toList(growable: false),
                ),
              )
              .toList(growable: false),
        ),
        DateTime.now(),
      );
    });
