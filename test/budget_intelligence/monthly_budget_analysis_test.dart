import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/budget_intelligence/application/monthly_budget_analysis.dart';
import 'package:noyau_app/features/budget_intelligence/domain/budget_intelligence.dart';

void main() {
  const analyzer = MonthlyBudgetAnalyzer();

  test('builds household and member summaries without a financial write', () {
    final analysis = analyzer.analyze(
      run: const BudgetAllocationRun(
        id: 'run',
        householdId: 'household',
        periodId: 'period',
        scenarioId: 'scenario',
        availableResourcesCents: 300000,
        memberContributions: [
          BudgetMemberContribution(
            memberUserId: 'a',
            eligibleIncomeCents: 150000,
            directChargesCents: 0,
            rawCapacityCents: 150000,
            contributionCapacityCents: 60000,
            autoShare: .5,
          ),
          BudgetMemberContribution(
            memberUserId: 'b',
            eligibleIncomeCents: 150000,
            directChargesCents: 0,
            rawCapacityCents: 150000,
            contributionCapacityCents: 60000,
            autoShare: .5,
          ),
        ],
        lines: [
          BudgetAllocationRunLine(
            envelopeId: 'personal',
            previousBalanceCents: 0,
            rolloverCents: 0,
            plannedAllocationCents: 50000,
            resultingAvailableCents: 50000,
            priority: 1,
            state: BudgetEnvelopeState.available,
          ),
          BudgetAllocationRunLine(
            envelopeId: 'common',
            previousBalanceCents: 0,
            rolloverCents: 0,
            plannedAllocationCents: 120000,
            resultingAvailableCents: 120000,
            priority: 2,
            state: BudgetEnvelopeState.available,
          ),
        ],
      ),
      incomes: const [
        BudgetScenarioMemberIncome(
          memberUserId: 'a',
          netRecurringCents: 150000,
        ),
        BudgetScenarioMemberIncome(
          memberUserId: 'b',
          netRecurringCents: 150000,
        ),
      ],
      rules: const [
        BudgetScenarioRule(
          id: 'personal-rule',
          scenarioId: 'scenario',
          envelopeId: 'personal',
          method: BudgetAllocationMethod.fixed,
          priority: 1,
          rolloverPolicy: RolloverPolicy.reset,
          amountCents: 50000,
          fundingMode: BudgetFundingMode.personalMember,
          fundingMemberUserId: 'a',
        ),
        BudgetScenarioRule(
          id: 'common-rule',
          scenarioId: 'scenario',
          envelopeId: 'common',
          method: BudgetAllocationMethod.fixed,
          priority: 2,
          rolloverPolicy: RolloverPolicy.reset,
          amountCents: 120000,
        ),
      ],
    );

    expect(analysis.personalChargesCents, 50000);
    expect(analysis.commonChargesCents, 120000);
    expect(analysis.memberSummaries, hasLength(2));
    expect(analysis.transferSuggestion, isNotNull);
    expect(analysis.blockers, isEmpty);
  });

  test('blocks a custom contribution key that is not 100 percent', () {
    final analysis = analyzer.analyze(
      run: const BudgetAllocationRun(
        id: 'run',
        householdId: 'household',
        periodId: 'period',
        scenarioId: 'scenario',
        availableResourcesCents: 10000,
        lines: [
          BudgetAllocationRunLine(
            envelopeId: 'food',
            previousBalanceCents: 0,
            rolloverCents: 0,
            plannedAllocationCents: 5000,
            resultingAvailableCents: 5000,
            priority: 1,
            state: BudgetEnvelopeState.available,
          ),
        ],
      ),
      incomes: const [],
      rules: const [
        BudgetScenarioRule(
          id: 'rule',
          scenarioId: 'scenario',
          envelopeId: 'food',
          method: BudgetAllocationMethod.fixed,
          priority: 1,
          rolloverPolicy: RolloverPolicy.reset,
          amountCents: 5000,
          fundingMode: BudgetFundingMode.sharedCustom,
          fundingDefinition: {'a': 40, 'b': 40},
        ),
      ],
    );

    expect(
      analysis.blockers,
      contains('Une clé personnalisée doit totaliser 100 %.'),
    );
  });
}
