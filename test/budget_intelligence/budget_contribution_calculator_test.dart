import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/budget_intelligence/application/budget_contribution_calculator.dart';
import 'package:noyau_app/features/budget_intelligence/domain/budget_intelligence.dart';

void main() {
  const calculator = BudgetContributionCalculator();
  test('calculates automatic shares for two members after direct charges', () {
    final members = calculator.calculate(
      incomes: const [
        BudgetScenarioMemberIncome(
          memberUserId: 'a',
          netRecurringCents: 1310000,
        ),
        BudgetScenarioMemberIncome(
          memberUserId: 'b',
          netRecurringCents: 1400000,
        ),
      ],
      directChargesByMember: const {'a': 620000, 'b': 700000},
    );
    expect(members[0].rawCapacityCents, 690000);
    expect(members[1].rawCapacityCents, 700000);
    expect(members[0].autoShare + members[1].autoShare, closeTo(1, .000001));
    expect(
      calculator
          .allocateSharedAuto(amountCents: 250000, members: members)
          .values
          .fold(0, (a, b) => a + b),
      250000,
    );
  });

  test(
    'supports an arbitrary number of members and excludes exceptional income by default',
    () {
      final members = calculator.calculate(
        incomes: const [
          BudgetScenarioMemberIncome(
            memberUserId: 'one',
            netRecurringCents: 10000,
          ),
          BudgetScenarioMemberIncome(
            memberUserId: 'two',
            netRecurringCents: 20000,
            exceptionalCents: 500000,
          ),
          BudgetScenarioMemberIncome(
            memberUserId: 'three',
            netRecurringCents: 30000,
          ),
        ],
        directChargesByMember: const {},
      );
      expect(members.map((member) => member.autoShare), [
        closeTo(1 / 6, .000001),
        closeTo(2 / 6, .000001),
        closeTo(3 / 6, .000001),
      ]);
    },
  );

  test('includes an exceptional income only when explicitly configured', () {
    final members = calculator.calculate(
      incomes: const [
        BudgetScenarioMemberIncome(
          memberUserId: 'included',
          netRecurringCents: 10000,
          exceptionalCents: 5000,
          exceptionalTreatment:
              ExceptionalIncomeTreatment.includedInSharedCapacity,
        ),
        BudgetScenarioMemberIncome(
          memberUserId: 'direct',
          netRecurringCents: 10000,
          exceptionalCents: 5000,
          exceptionalTreatment: ExceptionalIncomeTreatment.directAllocation,
        ),
      ],
      directChargesByMember: const {},
    );
    expect(members[0].eligibleIncomeCents, 15000);
    expect(members[1].eligibleIncomeCents, 10000);
  });

  test(
    'clamps negative capacity to zero while preserving the visible deficit',
    () {
      final members = calculator.calculate(
        incomes: const [
          BudgetScenarioMemberIncome(
            memberUserId: 'a',
            netRecurringCents: 10000,
          ),
          BudgetScenarioMemberIncome(
            memberUserId: 'b',
            netRecurringCents: 50000,
          ),
        ],
        directChargesByMember: const {'a': 20000},
      );
      expect(members.first.rawCapacityCents, -10000);
      expect(members.first.contributionCapacityCents, 0);
      expect(members.first.autoShare, 0);
      expect(members.last.autoShare, 1);
    },
  );

  test('validates custom and fixed member contributions', () {
    BudgetContributionCalculator.validateCustomPercentages(const {
      'one': 70,
      'two': 30,
    });
    BudgetContributionCalculator.validateFixedContributions(const {
      'one': 200000,
      'two': 100000,
    }, 300000);
    expect(
      () => BudgetContributionCalculator.validateCustomPercentages(const {
        'one': 90,
      }),
      throwsStateError,
    );
    expect(
      () => BudgetContributionCalculator.validateFixedContributions(const {
        'one': 1,
      }, 2),
      throwsStateError,
    );
  });
}
