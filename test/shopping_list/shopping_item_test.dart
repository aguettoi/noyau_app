import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/shopping_list/domain/shopping_item.dart';

void main() {
  test('un article prévu valide reste une intention sans solde local', () {
    const draft = ShoppingItemDraft(
      label: 'Siège auto',
      estimatedAmount: Money.fromMinorUnits(120000),
      finalPriority: 0,
    );

    expect(draft.validate(), isNull);
    expect(draft.estimatedAmount, Money.fromDirhams(1200));
  });

  test(
    'les validations gardent le montant et la priorité dans le périmètre MVP',
    () {
      expect(
        const ShoppingItemDraft(
          label: 'A',
          estimatedAmount: Money.fromMinorUnits(0),
        ).validate(),
        contains('strictement positif'),
      );
      expect(
        const ShoppingItemDraft(label: 'A', finalPriority: 4).validate(),
        contains('entre 0 et 3'),
      );
    },
  );

  test('les statuts conservent des libellés utilisateur', () {
    expect(ShoppingItemStatusLabel.fromDatabase('planned').label, 'Prévu');
    expect(ShoppingItemStatusLabel.fromDatabase('archived').label, 'Archivé');
  });

  test('l estimation et la preuve financière réelle restent distinctes', () {
    final item = ShoppingItem(
      id: 'shopping-1',
      householdId: 'household-1',
      label: 'TEST TV',
      estimatedAmount: Money.fromDirhams(6000),
      status: ShoppingItemStatus.purchased,
      purchasedFinancialEventId: 'event-1',
      createdBy: 'actor-1',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    final purchase = ShoppingPurchase(
      financialEventId: 'event-1',
      financialTransactionId: 'transaction-1',
      amount: Money.fromDirhams(5650),
      occurredAt: DateTime.utc(2026, 9, 25),
      description: 'TEST TV',
      actorId: 'actor-1',
      actorName: 'Ibrahim',
    );

    expect(item.estimatedAmount, Money.fromDirhams(6000));
    expect(purchase.amount, Money.fromDirhams(5650));
    expect(item.purchasedFinancialEventId, purchase.financialEventId);
  });
}
