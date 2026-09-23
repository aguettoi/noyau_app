import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/priorities/application/priority_projection.dart';
import 'package:noyau_app/features/priorities/domain/priority_plan.dart';

PriorityPlanItemView _item({
  required String id,
  required String label,
  required int need,
  PrioritySourceType type = PrioritySourceType.budgetGoal,
}) => PriorityPlanItemView(
  item: PriorityPlanItem(
    id: id,
    planId: 'plan-1',
    householdId: 'household-1',
    rank: int.parse(id.split('-').last),
    sourceType: type,
    sourceId: 'source-$id',
    createdBy: 'actor-1',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  ),
  source: PrioritySourceSnapshot(
    type: type,
    id: 'source-$id',
    label: label,
    status: 'Prévu',
    estimatedNeed: Money.fromDirhams(need),
  ),
);

void main() {
  test('la cascade A vers B vers C suit strictement l’ordre persistant', () {
    final entries = projectPriorityPlan(
      items: [
        _item(id: 'item-1', label: 'Voiture', need: 10000),
        _item(id: 'item-2', label: 'Canapé', need: 5000),
        _item(id: 'item-3', label: 'Voyage', need: 10000),
      ],
      monthlyCapacity: Money.fromDirhams(5000),
      from: DateTime(2026, 10, 1),
    );

    expect(entries.map((entry) => entry.item.source.label), [
      'Voiture',
      'Canapé',
      'Voyage',
    ]);
    expect(entries.map((entry) => entry.estimatedMonths), [2, 1, 2]);
    expect(entries[0].estimatedCompletionDate, DateTime(2026, 12, 1));
    expect(entries[1].estimatedCompletionDate, DateTime(2027, 1, 1));
    expect(entries[2].estimatedCompletionDate, DateTime(2027, 3, 1));
  });

  test(
    'un changement d’ordre ou de capacité recalcule sans état financier',
    () {
      final reordered = projectPriorityPlan(
        items: [
          _item(id: 'item-2', label: 'Canapé', need: 5000),
          _item(id: 'item-1', label: 'Voiture', need: 10000),
        ],
        monthlyCapacity: Money.fromDirhams(10000),
        from: DateTime(2026, 10, 1),
      );

      expect(reordered.map((entry) => entry.estimatedMonths), [1, 1]);
      expect(reordered[0].estimatedCompletionDate, DateTime(2026, 11, 1));
      expect(reordered[1].estimatedCompletionDate, DateTime(2026, 12, 1));
    },
  );

  test('un objectif déjà financé utilise seulement son besoin restant', () {
    final entry = projectPriorityPlan(
      items: [_item(id: 'item-1', label: 'Voiture', need: 4000)],
      monthlyCapacity: Money.fromDirhams(5000),
      from: DateTime(2026, 10, 1),
    ).single;

    expect(entry.estimatedNeed, Money.fromDirhams(4000));
    expect(entry.estimatedMonths, 1);
  });

  test(
    'un achat sans objectif utilise son estimation seulement pour la simulation',
    () {
      final entry = projectPriorityPlan(
        items: [
          _item(
            id: 'item-1',
            label: 'TV',
            need: 8000,
            type: PrioritySourceType.shoppingItem,
          ),
        ],
        monthlyCapacity: Money.fromDirhams(5000),
        from: DateTime(2026, 10, 1),
      ).single;

      expect(entry.estimatedNeed, Money.fromDirhams(8000));
      expect(entry.estimatedMonths, 2);
    },
  );

  test('sans capacité la projection reste non déterminée', () {
    final entry = projectPriorityPlan(
      items: [_item(id: 'item-1', label: 'TV', need: 8000)],
      monthlyCapacity: null,
      from: DateTime(2026, 10, 1),
    ).single;

    expect(entry.estimatedMonths, isNull);
    expect(entry.estimatedCompletionDate, isNull);
  });
}
