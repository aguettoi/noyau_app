import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/budget_intelligence/domain/budget_intelligence.dart';
import 'package:noyau_app/features/cashflow_projection/domain/cashflow_projection.dart';
import 'package:noyau_app/features/finance/application/providers/remote_debts_provider.dart';
import 'package:noyau_app/features/recurring_finance/domain/recurring_finance.dart';
import 'package:noyau_app/features/wealth/domain/home_auto_models.dart';

void main() {
  group('L2.1 temporal contracts', () {
    test('HID-01 date trigger is deterministic at month/year boundaries', () {
      const scenario = BudgetScenario(
        id: 's',
        householdId: 'h',
        name: 'Après changement',
        active: true,
        triggerType: 'date_reached',
        triggerDefinition: {'effective_on': '2027-01-01'},
      );
      expect(
        evaluateScenarioApplicability(scenario, DateTime(2026, 12, 31)).applies,
        isFalse,
      );
      final result = evaluateScenarioApplicability(
        scenario,
        DateTime(2027, 1, 1, 23, 59),
      );
      expect(result.applies, isTrue);
      expect(result.reason, contains('Date'));
    });

    test(
      'REC-X3 adapts obligation and vehicle plan exactly once with provenance',
      () {
        final flows = adaptCanonicalExpectedSources(
          asOf: DateTime(2026, 10, 22),
          through: DateTime(2026, 11, 30),
          obligations: [
            RemoteDebtBalance(
              id: 'o1',
              description: 'Dette',
              initialAmount: const Money.fromMinorUnits(10000),
              settledAmount: const Money.fromMinorUnits(2000),
              remainingAmount: const Money.fromMinorUnits(8000),
              status: 'open',
              dueAt: DateTime(2026, 11, 2),
            ),
          ],
          vehicleCosts: [
            VehicleCostPlan(
              id: 'v1',
              assetId: 'a1',
              category: VehicleCostCategory.insurance,
              label: 'Assurance',
              amount: const Money.fromMinorUnits(30000),
              dueDate: DateTime(2026, 11, 3),
            ),
          ],
        );
        expect(flows.map((e) => e.id).toSet(), {
          'obligation:o1',
          'vehicle-cost:v1',
        });
        expect(
          flows.every((e) => e.explanation?.reason.isNotEmpty == true),
          isTrue,
        );
      },
    );

    test(
      'CAS-X1 hypothesis changes projection without creating a real source',
      () {
        final hypothesis = ProjectionFlow(
          id: 'hypothesis:1',
          date: DateTime(2026, 10, 25),
          label: 'Test',
          amount: const Money.fromMinorUnits(1000),
          kind: ProjectionFlowKind.expense,
          certainty: ProjectionCertainty.hypothetical,
          source: 'simulation',
        );
        final projection = buildCashflowProjection(
          asOf: DateTime(2026, 10, 22),
          through: DateTime(2026, 10, 31),
          accountBalances: {'a': const Money.fromMinorUnits(5000)},
          envelopeBalances: const {},
          occurrences: const [],
          hypotheticalFlows: [hypothesis],
        );
        expect(projection.projectedHouseholdBalance.minorUnits, 4000);
        expect(
          projection.flows.single.certainty,
          ProjectionCertainty.hypothetical,
        );
      },
    );

    test(
      'R3-02 suggests stable monthly pattern but rejects unstable amounts',
      () {
        ActualFinancialCandidate item(int month, int amount) =>
            ActualFinancialCandidate(
              id: '$month-$amount',
              type: RecurringEconomicType.expense,
              occurredAt: DateTime(2026, month, 5),
              amount: Money.fromMinorUnits(amount),
              description: 'Internet maison',
              accountId: 'a',
            );
        final stable = detectRecurringPatterns([
          item(7, 5000),
          item(8, 5050),
          item(9, 5000),
        ]);
        expect(stable, hasLength(1));
        expect(stable.single.frequency, RecurringFrequency.monthly);
        expect(stable.single.reasons, hasLength(3));
        expect(
          detectRecurringPatterns([
            item(7, 1000),
            item(8, 5000),
            item(9, 9000),
          ]),
          isEmpty,
        );
      },
    );

    test('canonical and hypothetical flows are idempotent by source id', () {
      final flow = ProjectionFlow(
        id: 'obligation:o',
        date: DateTime(2026, 10, 25),
        label: 'Dette',
        amount: const Money.fromMinorUnits(1000),
        kind: ProjectionFlowKind.expense,
        certainty: ProjectionCertainty.certain,
        source: 'obligation',
      );
      final projection = buildCashflowProjection(
        asOf: DateTime(2026, 10, 22),
        through: DateTime(2026, 10, 31),
        accountBalances: const {},
        envelopeBalances: const {},
        occurrences: const [],
        canonicalExpectedFlows: [flow, flow],
      );
      expect(projection.flows, hasLength(1));
    });
  });
}
