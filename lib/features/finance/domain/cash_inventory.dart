import '../../../core/money/money.dart';

enum CashCountInputMode { direct, denominations }

enum CashDenominationKind { banknote, coin }

class CashDenomination {
  const CashDenomination({
    required this.currencyCode,
    required this.valueMinor,
    required this.kind,
    required this.label,
  });
  final String currencyCode;
  final int valueMinor;
  final CashDenominationKind kind;
  final String label;
}

class CashDenominationCount {
  const CashDenominationCount({
    required this.denomination,
    required this.quantity,
  }) : assert(quantity >= 0);
  final CashDenomination denomination;
  final int quantity;
  Money get subtotal =>
      Money.fromMinorUnits(denomination.valueMinor * quantity);
}

const cashDenominationsByCurrency = <String, List<CashDenomination>>{
  'MAD': [
    CashDenomination(
      currencyCode: 'MAD',
      valueMinor: 20000,
      kind: CashDenominationKind.banknote,
      label: '200 MAD',
    ),
    CashDenomination(
      currencyCode: 'MAD',
      valueMinor: 10000,
      kind: CashDenominationKind.banknote,
      label: '100 MAD',
    ),
    CashDenomination(
      currencyCode: 'MAD',
      valueMinor: 5000,
      kind: CashDenominationKind.banknote,
      label: '50 MAD',
    ),
    CashDenomination(
      currencyCode: 'MAD',
      valueMinor: 2000,
      kind: CashDenominationKind.banknote,
      label: '20 MAD',
    ),
    CashDenomination(
      currencyCode: 'MAD',
      valueMinor: 1000,
      kind: CashDenominationKind.coin,
      label: '10 MAD',
    ),
    CashDenomination(
      currencyCode: 'MAD',
      valueMinor: 500,
      kind: CashDenominationKind.coin,
      label: '5 MAD',
    ),
    CashDenomination(
      currencyCode: 'MAD',
      valueMinor: 200,
      kind: CashDenominationKind.coin,
      label: '2 MAD',
    ),
    CashDenomination(
      currencyCode: 'MAD',
      valueMinor: 100,
      kind: CashDenominationKind.coin,
      label: '1 MAD',
    ),
    CashDenomination(
      currencyCode: 'MAD',
      valueMinor: 50,
      kind: CashDenominationKind.coin,
      label: '0,50 MAD',
    ),
    CashDenomination(
      currencyCode: 'MAD',
      valueMinor: 20,
      kind: CashDenominationKind.coin,
      label: '0,20 MAD',
    ),
    CashDenomination(
      currencyCode: 'MAD',
      valueMinor: 10,
      kind: CashDenominationKind.coin,
      label: '0,10 MAD',
    ),
  ],
};

Money totalCashCount(Iterable<CashDenominationCount> counts) =>
    Money.fromMinorUnits(
      counts.fold(0, (sum, item) => sum + item.subtotal.minorUnits),
    );

List<Map<String, Object?>> cashCountPayload(
  Iterable<CashDenominationCount> counts,
) => [
  for (final item in counts.where((item) => item.quantity > 0))
    {
      'currency_code': item.denomination.currencyCode,
      'value_minor': item.denomination.valueMinor,
      'kind': item.denomination.kind.name,
      'quantity': item.quantity,
    },
];
