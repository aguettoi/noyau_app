import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/domain/cash_inventory.dart';

void main() {
  test('calcule exactement billets, pièces, zéro et quantité raisonnable', () {
    final mad = cashDenominationsByCurrency['MAD']!;
    CashDenomination d(int minor) =>
        mad.singleWhere((e) => e.valueMinor == minor);
    expect(
      totalCashCount([
        CashDenominationCount(denomination: d(20000), quantity: 1),
      ]).minorUnits,
      20000,
    );
    final counts = [
      CashDenominationCount(denomination: d(20000), quantity: 4),
      CashDenominationCount(denomination: d(10000), quantity: 3),
      CashDenominationCount(denomination: d(5000), quantity: 2),
      CashDenominationCount(denomination: d(2000), quantity: 1),
      CashDenominationCount(denomination: d(1000), quantity: 2),
      CashDenominationCount(denomination: d(500), quantity: 3),
      CashDenominationCount(denomination: d(100), quantity: 7),
      CashDenominationCount(denomination: d(50), quantity: 0),
    ];
    expect(totalCashCount(counts).minorUnits, 126200);
    expect(cashCountPayload(counts), hasLength(7));
    expect(
      totalCashCount([
        CashDenominationCount(denomination: d(100), quantity: 100000),
      ]).minorUnits,
      10000000,
    );
  });

  test(
    'le référentiel MAD distingue billets et pièces et reste indexé par devise',
    () {
      final mad = cashDenominationsByCurrency['MAD']!;
      expect(mad.any((e) => e.kind == CashDenominationKind.banknote), isTrue);
      expect(mad.any((e) => e.kind == CashDenominationKind.coin), isTrue);
      expect(mad.every((e) => e.currencyCode == 'MAD'), isTrue);
    },
  );
}
