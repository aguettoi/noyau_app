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
  List<AvailabilityPlan>? plans,
  List<AvailabilityCommitment>? commitments,
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
  commitments: commitments ?? const [],
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
  plans:
      plans ??
      [
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
    expect(entries.last.completionDate, DateTime(2026, 7, 1));
  });

  test(
    'exclut une créance du cash et signale honnêtement une dette non datée',
    () {
      final value = projectFinancialAvailability(
        input(
          debt: mad(1000),
          commitments: [AvailabilityCommitment(amount: mad(1000))],
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
      expect(value.planEntries['plan']!.single.completionDate, isNotNull);
      expect(value.warnings.single, contains('sans échéancier précis'));
    },
  );

  test('consomme une capacité variable mois par mois sans extrapoler', () {
    final value = projectFinancialAvailability(
      input(
        goals: [
          AvailabilityGoal(
            id: 'a',
            envelopeId: 'travel',
            target: mad(7000),
            accumulated: mad(0),
            isActive: true,
          ),
        ],
        items: const [
          AvailabilityPlanItem(
            id: 'goal',
            rank: 1,
            type: AvailabilitySourceType.goal,
            sourceId: 'a',
            status: 'Actif',
          ),
        ],
        plans: const [
          AvailabilityPlan(
            id: 'plan',
            isActive: true,
            monthlyCapacity: null,
            monthlyCapacities: [
              Money.fromMinorUnits(100000),
              Money.fromMinorUnits(200000),
              Money.fromMinorUnits(400000),
            ],
            items: [
              AvailabilityPlanItem(
                id: 'goal',
                rank: 1,
                type: AvailabilitySourceType.goal,
                sourceId: 'a',
                status: 'Actif',
              ),
            ],
          ),
        ],
      ),
      DateTime(2026, 1, 1),
    );
    expect(
      value.planEntries['plan']!.single.completionDate,
      DateTime(2026, 4, 1),
    );
    expect(value.planEntries['plan']!.single.months, 3);
  });

  test(
    'impute une dette datée sur son mois, sans toucher les mois voisins',
    () {
      final value = projectFinancialAvailability(
        input(
          capacity: mad(5000),
          commitments: [
            AvailabilityCommitment(
              amount: mad(5000),
              dueAt: DateTime(2026, 2, 15),
            ),
          ],
          goals: [
            AvailabilityGoal(
              id: 'a',
              envelopeId: 'travel',
              target: mad(10000),
              accumulated: mad(0),
              isActive: true,
            ),
          ],
          items: const [
            AvailabilityPlanItem(
              id: 'goal',
              rank: 1,
              type: AvailabilitySourceType.goal,
              sourceId: 'a',
              status: 'Actif',
            ),
          ],
        ),
        DateTime(2026, 1, 1),
      );
      expect(
        value.planEntries['plan']!.single.completionDate,
        DateTime(2026, 4, 1),
      );
    },
  );

  test('ne choisit jamais arbitrairement entre plusieurs plans actifs', () {
    final goal = AvailabilityGoal(
      id: 'a',
      envelopeId: 'travel',
      target: mad(1000),
      accumulated: mad(0),
      isActive: true,
    );
    final item = const AvailabilityPlanItem(
      id: 'goal',
      rank: 1,
      type: AvailabilitySourceType.goal,
      sourceId: 'a',
      status: 'Actif',
    );
    final value = projectFinancialAvailability(
      input(
        goals: [goal],
        plans: [
          AvailabilityPlan(
            id: 'one',
            isActive: true,
            monthlyCapacity: mad(1000),
            items: [item],
          ),
          AvailabilityPlan(
            id: 'two',
            isActive: true,
            monthlyCapacity: mad(1000),
            items: [item],
          ),
        ],
      ),
      DateTime(2026, 1, 1),
    );
    expect(value.planEntries['one']!.single.completionDate, isNull);
    expect(
      value.planEntries['two']!.single.reason,
      contains('plusieurs plans actifs'),
    );
    expect(
      value.warnings.single,
      contains('Plusieurs plans PRIOS sont actifs'),
    );
  });

  test('n utilise jamais un plan prévu comme référence de projection', () {
    final value = projectFinancialAvailability(
      input(
        plans: const [
          AvailabilityPlan(
            id: 'planned',
            isActive: false,
            monthlyCapacity: Money.fromMinorUnits(500000),
            items: [
              AvailabilityPlanItem(
                id: 'goal',
                rank: 1,
                type: AvailabilitySourceType.goal,
                sourceId: 'a',
                status: 'Actif',
              ),
            ],
          ),
        ],
      ),
      DateTime(2026, 1, 1),
    );
    expect(value.goals['a']!.completionDate, isNull);
    expect(value.goals['a']!.reason, contains('aucun plan PRIOS actif'));
  });

  test('le reorder recalcule la même capacité unique dans le nouvel ordre', () {
    const first = AvailabilityPlanItem(
      id: 'first',
      rank: 1,
      type: AvailabilitySourceType.shopping,
      sourceId: 'first',
      status: 'Prévu',
      estimatedAmount: Money.fromMinorUnits(600000),
    );
    const second = AvailabilityPlanItem(
      id: 'second',
      rank: 2,
      type: AvailabilitySourceType.shopping,
      sourceId: 'second',
      status: 'Prévu',
      estimatedAmount: Money.fromMinorUnits(200000),
    );
    final ordered = projectFinancialAvailability(
      input(items: const [first, second]),
      DateTime(2026, 1, 1),
    );
    final reordered = projectFinancialAvailability(
      input(
        items: const [
          AvailabilityPlanItem(
            id: 'first',
            rank: 2,
            type: AvailabilitySourceType.shopping,
            sourceId: 'first',
            status: 'Prévu',
            estimatedAmount: Money.fromMinorUnits(600000),
          ),
          AvailabilityPlanItem(
            id: 'second',
            rank: 1,
            type: AvailabilitySourceType.shopping,
            sourceId: 'second',
            status: 'Prévu',
            estimatedAmount: Money.fromMinorUnits(200000),
          ),
        ],
      ),
      DateTime(2026, 1, 1),
    );
    expect(ordered.planEntries['plan']!.first.itemId, 'first');
    expect(reordered.planEntries['plan']!.first.itemId, 'second');
    expect(
      reordered.planEntries['plan']!.first.completionDate,
      DateTime(2026, 2, 1),
    );
  });

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

  test(
    'un achat acheté lié à un objectif ne consomme plus sa capacité future',
    () {
      final value = projectFinancialAvailability(
        input(
          items: const [
            AvailabilityPlanItem(
              id: 'shopping-done',
              rank: 1,
              type: AvailabilitySourceType.shopping,
              sourceId: 'shopping',
              goalId: 'a',
              status: 'Acheté',
              estimatedAmount: Money.fromMinorUnits(600000),
            ),
            AvailabilityPlanItem(
              id: 'goal',
              rank: 2,
              type: AvailabilitySourceType.goal,
              sourceId: 'a',
              status: 'Actif',
            ),
          ],
        ),
        DateTime(2026, 1, 1),
      );
      final entries = value.planEntries['plan']!;
      expect(entries.first.remainingNeed, const Money.fromMinorUnits(0));
      expect(entries.first.months, 0);
      expect(entries.last.completionDate, DateTime(2026, 3, 1));
    },
  );

  test(
    'respecte le plafond mensuel de l objectif et le reliquat intra-mois',
    () {
      final value = projectFinancialAvailability(
        input(
          goals: [
            AvailabilityGoal(
              id: 'a',
              envelopeId: 'travel',
              target: mad(15000),
              accumulated: mad(0),
              isActive: true,
              monthlyTarget: mad(3000),
            ),
          ],
          items: const [
            AvailabilityPlanItem(
              id: 'tv',
              rank: 1,
              type: AvailabilitySourceType.shopping,
              sourceId: 'tv',
              status: 'Prévu',
              estimatedAmount: Money.fromMinorUnits(600000),
            ),
            AvailabilityPlanItem(
              id: 'goal',
              rank: 2,
              type: AvailabilitySourceType.goal,
              sourceId: 'a',
              status: 'Actif',
            ),
          ],
        ),
        DateTime(2026, 1, 1),
      );
      final entries = value.planEntries['plan']!;
      expect(entries[0].completionDate, DateTime(2026, 3, 1));
      expect(entries[1].completionDate, DateTime(2026, 7, 1));
    },
  );

  test(
    'réalloue le reliquat mensuel après le plafond à la priorité suivante',
    () {
      final value = projectFinancialAvailability(
        input(
          goals: [
            AvailabilityGoal(
              id: 'a',
              envelopeId: 'travel',
              target: mad(3000),
              accumulated: mad(0),
              isActive: true,
              monthlyTarget: mad(3000),
            ),
          ],
          items: const [
            AvailabilityPlanItem(
              id: 'goal',
              rank: 1,
              type: AvailabilitySourceType.goal,
              sourceId: 'a',
              status: 'Actif',
            ),
            AvailabilityPlanItem(
              id: 'shopping',
              rank: 2,
              type: AvailabilitySourceType.shopping,
              sourceId: 'shopping',
              status: 'Prévu',
              estimatedAmount: Money.fromMinorUnits(200000),
            ),
          ],
        ),
        DateTime(2026, 1, 1),
      );
      final entries = value.planEntries['plan']!;
      expect(entries[0].completionDate, DateTime(2026, 2, 1));
      expect(entries[1].completionDate, DateTime(2026, 2, 1));
      expect(entries[1].months, 1);
    },
  );
}
