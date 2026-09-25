import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/financial_availability/domain/financial_availability.dart';

Money mad(int value) => Money.fromDirhams(value);

FinancialAvailabilityInput input({
  Money? debt,
  Money? capacity,
  List<AvailabilityGoal>? goals,
  List<AvailabilityPlanItem>? items,
  List<AvailabilityEnvelope>? envelopes,
}) => FinancialAvailabilityInput(
  liquidity: mad(10000),
  envelopes:
      envelopes ??
      const [
        AvailabilityEnvelope(
          id: 'travel',
          balance: Money.fromMinorUnits(500000),
        ),
      ],
  debtCommitments: debt ?? const Money.fromMinorUnits(0),
  potentialReceivables: mad(3000),
  goals:
      goals ??
      [
        AvailabilityGoal(
          id: 'a',
          envelopeId: 'travel',
          target: mad(15000),
          accumulated: mad(5000),
          isActive: true,
        ),
      ],
  plans: [
    AvailabilityPlan(
      id: 'plan',
      isActive: true,
      monthlyCapacity: capacity ?? mad(5000),
      items: items ?? const [],
    ),
  ],
);

void main() {
  test('ne double jamais comptes et enveloppes', () {
    final value = projectFinancialAvailability(input(), DateTime(2026, 9, 1));
    expect(value.realLiquidity, mad(10000));
    expect(value.envelopeTotal, mad(5000));
    expect(value.realLiquidity, isNot(mad(15000)));
    expect(value.potentialReceivables, mad(3000));
  });

  test('cascade une capacité unique sur plusieurs projets', () {
    final value = projectFinancialAvailability(
      input(
        items: const [
          AvailabilityPlanItem(
            id: 'a',
            rank: 1,
            type: AvailabilitySourceType.goal,
            sourceId: 'a',
            status: 'Actif',
          ),
          AvailabilityPlanItem(
            id: 'b',
            rank: 2,
            type: AvailabilitySourceType.shopping,
            sourceId: 'b',
            status: 'Prévu',
            estimatedAmount: Money.fromMinorUnits(1200000),
          ),
          AvailabilityPlanItem(
            id: 'c',
            rank: 3,
            type: AvailabilitySourceType.shopping,
            sourceId: 'c',
            status: 'Prévu',
            estimatedAmount: Money.fromMinorUnits(600000),
          ),
        ],
      ),
      DateTime(2026, 1, 1),
    );
    final entries = value.planEntries['plan']!;
    expect(entries.map((e) => e.months), [2, 3, 2]);
    expect(entries.last.completionDate, DateTime(2026, 8, 1));
  });

  test(
    'exclut une créance du cash et bloque honnêtement une dette non qualifiée',
    () {
      final value = projectFinancialAvailability(
        input(
          debt: mad(1000),
          items: const [
            AvailabilityPlanItem(
              id: 'a',
              rank: 1,
              type: AvailabilitySourceType.goal,
              sourceId: 'a',
              status: 'Actif',
            ),
          ],
        ),
        DateTime(2026, 1, 1),
      );
      expect(value.realLiquidity, mad(10000));
      expect(value.potentialReceivables, mad(3000));
      expect(value.planEntries['plan']!.single.completionDate, isNull);
      expect(value.planEntries['plan']!.single.reason, isNotNull);
    },
  );

  test('protège une enveloppe partagée et un achat déjà acheté', () {
    final value = projectFinancialAvailability(
      input(
        goals: [
          AvailabilityGoal(
            id: 'a',
            envelopeId: 'travel',
            target: mad(15000),
            accumulated: mad(5000),
            isActive: true,
          ),
          AvailabilityGoal(
            id: 'b',
            envelopeId: 'travel',
            target: mad(8000),
            accumulated: mad(5000),
            isActive: true,
          ),
        ],
        items: const [
          AvailabilityPlanItem(
            id: 'shopping',
            rank: 1,
            type: AvailabilitySourceType.shopping,
            sourceId: 'shopping',
            status: 'Acheté',
            estimatedAmount: Money.fromMinorUnits(600000),
          ),
        ],
      ),
      DateTime(2026, 1, 1),
    );
    expect(value.goals['a']!.securedFunding, const Money.fromMinorUnits(0));
    expect(
      value.planEntries['plan']!.single.remainingNeed,
      const Money.fromMinorUnits(0),
    );
  });
}
