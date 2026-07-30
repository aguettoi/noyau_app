import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/finance/domain/financial_account.dart';
import 'package:noyau_app/features/finance/domain/multi_account_operation.dart';

FinancialAccount account(String id, {bool archived = false}) =>
    FinancialAccount(
      id: id,
      name: id,
      type: FinancialAccountType.bank,
      openingBalance: const Money.fromMinorUnits(0),
      archivedAt: archived ? DateTime(2026) : null,
    );

void main() {
  test('accepte une dépense répartie exactement sur deux comptes', () {
    final operation = MultiAccountOperation(
      total: Money.fromDirhams(1000),
      recordedByMemberId: 'nora',
      paidByMemberId: 'ibrahim',
      splits: [
        AccountSplit(account: account('cih'), amount: Money.fromDirhams(600)),
        AccountSplit(account: account('cash'), amount: Money.fromDirhams(400)),
      ],
    );
    expect(operation.splits, hasLength(2));
  });

  test('refuse une ventilation qui ne couvre pas exactement le total', () {
    expect(
      () => MultiAccountOperation(
        total: Money.fromDirhams(1000),
        recordedByMemberId: 'ibrahim',
        splits: [
          AccountSplit(
            account: account('awb'),
            amount: Money.fromDirhams(999.99),
          ),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('refuse un compte archivé ou une ventilation nulle', () {
    expect(
      () => MultiAccountOperation(
        total: Money.fromDirhams(10),
        recordedByMemberId: 'ibrahim',
        splits: [
          AccountSplit(
            account: account('old', archived: true),
            amount: Money.fromDirhams(10),
          ),
        ],
      ),
      throwsArgumentError,
    );
  });
}
