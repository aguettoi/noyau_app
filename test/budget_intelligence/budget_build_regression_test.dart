import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/budget_intelligence/application/budget_simulator.dart';
import 'package:noyau_app/features/budget_intelligence/domain/budget_intelligence.dart';

void main() {
  test(
    'BudgetPeriod validates dates at runtime and remains usable on native builds',
    () {
      expect(
        () => BudgetPeriod(
          id: 'period',
          householdId: 'home',
          startDate: DateTime.utc(2026, 10, 1),
          endDate: DateTime.utc(2026, 9, 30),
          status: BudgetPeriodStatus.draft,
        ),
        throwsAssertionError,
      );
    },
  );

  test(
    'simulation sorts a copy of active rules without mutating input order',
    () {
      const later = BudgetScenarioRule(
        id: 'later',
        scenarioId: 'scenario',
        envelopeId: 'later-envelope',
        method: BudgetAllocationMethod.fixed,
        amountCents: 10000,
        priority: 2,
        rolloverPolicy: RolloverPolicy.reportTotal,
      );
      const first = BudgetScenarioRule(
        id: 'first',
        scenarioId: 'scenario',
        envelopeId: 'first-envelope',
        method: BudgetAllocationMethod.fixed,
        amountCents: 20000,
        priority: 1,
        rolloverPolicy: RolloverPolicy.reportTotal,
      );
      final rules = [later, first];
      final run = const BudgetSimulator().simulate(
        runId: 'run',
        householdId: 'home',
        periodId: 'period',
        scenarioId: 'scenario',
        availableResourcesCents: 50000,
        previousBalancesCents: const {},
        rules: rules,
      );
      expect(run.lines.map((line) => line.envelopeId), [
        'first-envelope',
        'later-envelope',
      ]);
      expect(rules.map((rule) => rule.envelopeId), [
        'later-envelope',
        'first-envelope',
      ]);
    },
  );
}
