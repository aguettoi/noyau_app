import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/providers/member_compensations_provider.dart';
import 'package:noyau_app/features/organization/application/organization_provider.dart';

void main() {
  MemberCompensation item({
    required String id,
    required String status,
    double remaining = 200,
    double pending = 0,
  }) => MemberCompensation(
    id: id,
    sourceFinancialEventId: 'event',
    debtorUserId: 'debtor',
    creditorUserId: 'creditor',
    debtor: 'Débiteur',
    creditor: 'Créancier',
    initial: 300,
    remaining: remaining,
    pendingReceipt: pending,
    status: status,
    reason: 'Partage',
  );

  test('compensation alerts target the correct member and derived amount', () {
    final toPay = buildCompensationAlerts(
      [item(id: 'one', status: 'to_pay')],
      'debtor',
      const {},
    );
    expect(toPay.single.detail, contains('200.00'));
    expect(
      buildCompensationAlerts(
        [item(id: 'one', status: 'to_pay')],
        'creditor',
        const {},
      ),
      isEmpty,
    );

    final receipt = buildCompensationAlerts(
      [item(id: 'two', status: 'transfer_sent', pending: 100)],
      'creditor',
      const {'compensation:receipt:two'},
    );
    expect(receipt.single.title, 'Réception à confirmer');
    expect(receipt.single.read, isTrue);
  });

  test('settled and abandoned compensations never remain active', () {
    expect(
      buildCompensationAlerts(
        [
          item(id: 'settled', status: 'settled', remaining: 0),
          item(id: 'abandoned', status: 'abandoned', remaining: 0),
        ],
        'debtor',
        const {},
      ),
      isEmpty,
    );
  });
}
