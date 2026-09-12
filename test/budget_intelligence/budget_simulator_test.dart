import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/budget_intelligence/application/budget_simulator.dart';
import 'package:noyau_app/features/budget_intelligence/domain/budget_intelligence.dart';

void main() {
  const simulator = BudgetSimulator();
  BudgetScenarioRule rule({
    String id = 'rule',
    String envelope = 'food',
    BudgetAllocationMethod method = BudgetAllocationMethod.fixed,
    int? amount = 250000,
    double? percentage,
    RolloverPolicy rollover = RolloverPolicy.reportTotal,
    int? cap,
    int priority = 1,
  }) => BudgetScenarioRule(
    id: id,
    scenarioId: 'scenario',
    envelopeId: envelope,
    method: method,
    amountCents: amount,
    percentage: percentage,
    priority: priority,
    rolloverPolicy: rollover,
    rolloverCapCents: cap,
  );

  test('crée une période budgétaire mensuelle valide', () {
    final period = BudgetPeriod(
      id: 'period',
      householdId: 'home',
      startDate: DateTime.utc(2026, 9),
      endDate: DateTime.utc(2026, 9, 30),
      status: BudgetPeriodStatus.draft,
    );
    expect(period.startDate, DateTime.utc(2026, 9));
    expect(period.endDate, DateTime.utc(2026, 9, 30));
  });

  test('simule une règle fixed sans mouvement de ledger', () {
    final run = simulator.simulate(
      runId: 'run',
      householdId: 'home',
      periodId: 'period',
      scenarioId: 'scenario',
      availableResourcesCents: 500000,
      previousBalancesCents: const {},
      rules: [rule()],
    );
    expect(run.status, BudgetAllocationRunStatus.simulated);
    expect(run.lines.single.plannedAllocationCents, 250000);
    expect(run.remainingUnallocatedCents, 250000);
  });

  test('calcule une règle percentage et la contribution reste déclarative', () {
    final run = simulator.simulate(
      runId: 'run',
      householdId: 'home',
      periodId: 'period',
      scenarioId: 'scenario',
      availableResourcesCents: 100000,
      previousBalancesCents: const {},
      rules: [
        rule(
          method: BudgetAllocationMethod.percentage,
          amount: null,
          percentage: 15,
        ),
      ],
    );
    expect(run.lines.single.plannedAllocationCents, 15000);
  });

  test(
    'conserve la méthode de calcul indépendante des contributions communes',
    () {
      final run = simulator.simulate(
        runId: 'run',
        householdId: 'home',
        periodId: 'period',
        scenarioId: 'scenario',
        availableResourcesCents: 100000,
        previousBalancesCents: const {},
        memberIncomes: const [
          BudgetScenarioMemberIncome(
            memberUserId: 'member-a',
            netRecurringCents: 60000,
          ),
          BudgetScenarioMemberIncome(
            memberUserId: 'member-b',
            netRecurringCents: 40000,
          ),
        ],
        rules: [
          rule(
            method: BudgetAllocationMethod.percentage,
            amount: null,
            percentage: 50,
          ).copyWithFunding(BudgetFundingMode.sharedCustom, const {
            'member-a': 60,
            'member-b': 40,
          }),
        ],
      );
      expect(run.lines.single.plannedAllocationCents, 50000);
      expect(run.lines.single.contributions, const {
        'member-a': 30000,
        'member-b': 20000,
      });
    },
  );

  test('refuses des montants fixes par membre incohérents', () {
    expect(
      () => simulator.simulate(
        runId: 'run',
        householdId: 'home',
        periodId: 'period',
        scenarioId: 'scenario',
        availableResourcesCents: 100000,
        previousBalancesCents: const {},
        rules: [
          rule(amount: 50000).copyWithFunding(
            BudgetFundingMode.fixedByMember,
            const {'member-a': 20000},
          ),
        ],
      ),
      throwsStateError,
    );
  });

  test(
    'requires a configured exceptional income for a direct envelope allocation',
    () {
      expect(
        () => simulator.simulate(
          runId: 'run',
          householdId: 'home',
          periodId: 'period',
          scenarioId: 'scenario',
          availableResourcesCents: 100000,
          previousBalancesCents: const {},
          memberIncomes: const [
            BudgetScenarioMemberIncome(
              memberUserId: 'member-a',
              netRecurringCents: 100000,
            ),
          ],
          rules: [
            rule(amount: 50000).copyWithFunding(
              BudgetFundingMode.exceptionalIncome,
              const {},
              memberId: 'member-a',
            ),
          ],
        ),
        throwsStateError,
      );
    },
  );

  test('alloue le résiduel après les règles prioritaires', () {
    final run = simulator.simulate(
      runId: 'run',
      householdId: 'home',
      periodId: 'period',
      scenarioId: 'scenario',
      availableResourcesCents: 100000,
      previousBalancesCents: const {},
      rules: [
        rule(),
        rule(
          id: 'residual',
          envelope: 'saving',
          method: BudgetAllocationMethod.residual,
          amount: null,
          priority: 2,
        ),
      ],
    );
    expect(run.lines.last.plannedAllocationCents, 0);
  });

  test('applique les quatre politiques de rollover', () {
    expect(
      BudgetSimulator.rolloverFor(50000, RolloverPolicy.reportTotal, null),
      50000,
    );
    expect(
      BudgetSimulator.rolloverFor(
        50000,
        RolloverPolicy.reportDeficitOnly,
        null,
      ),
      0,
    );
    expect(
      BudgetSimulator.rolloverFor(
        -50000,
        RolloverPolicy.reportDeficitOnly,
        null,
      ),
      -50000,
    );
    expect(BudgetSimulator.rolloverFor(50000, RolloverPolicy.reset, null), 0);
    expect(
      BudgetSimulator.rolloverFor(90000, RolloverPolicy.capRollover, 50000),
      50000,
    );
  });

  test('un solde négatif reste visible sans remise à zéro', () {
    final run = simulator.simulate(
      runId: 'run',
      householdId: 'home',
      periodId: 'period',
      scenarioId: 'scenario',
      availableResourcesCents: 0,
      previousBalancesCents: const {'food': -12000},
      rules: [rule(amount: 0)],
    );
    expect(run.lines.single.resultingAvailableCents, -12000);
    expect(run.lines.single.state, BudgetEnvelopeState.exceeded);
  });

  test('projette la fin de mois sans valeur comptable', () {
    final projection = BudgetSimulator.projectEndOfMonth(
      spentToDateCents: 150000,
      elapsedDays: 10,
      daysInMonth: 30,
      plannedCents: 250000,
    );
    expect(projection.projectedCents, 450000);
    expect(projection.varianceCents, -200000);
  });

  test('estime la date d’un objectif sans modifier son état', () {
    expect(
      BudgetSimulator.goalCompletionDate(
        from: DateTime(2026, 9, 1),
        remainingCents: 60000,
        monthlyAllocationCents: 20000,
      ),
      DateTime(2026, 12, 1),
    );
    expect(
      BudgetSimulator.goalCompletionDate(
        from: DateTime(2026, 9, 1),
        remainingCents: 60000,
        monthlyAllocationCents: 0,
      ),
      isNull,
    );
  });
}

extension on BudgetScenarioRule {
  BudgetScenarioRule copyWithFunding(
    BudgetFundingMode fundingMode,
    Map<String, Object?> fundingDefinition, {
    String? memberId,
  }) => BudgetScenarioRule(
    id: id,
    scenarioId: scenarioId,
    envelopeId: envelopeId,
    method: method,
    priority: priority,
    rolloverPolicy: rolloverPolicy,
    amountCents: amountCents,
    percentage: percentage,
    rolloverCapCents: rolloverCapCents,
    fundingMode: fundingMode,
    fundingMemberUserId: memberId,
    fundingDefinition: fundingDefinition,
  );
}
