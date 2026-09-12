import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/finance/domain/transaction_draft.dart';

void main() {
  FinancialTransactionDraft draft({
    required LedgerTransactionType type,
    required int amountCents,
    String? sourceAccountId,
    String? destinationAccountId,
  }) => FinancialTransactionDraft(
    type: type,
    occurredAt: DateTime.utc(2026, 8, 5),
    description: 'Test validation',
    amount: Money.fromMinorUnits(amountCents),
    sourceAccountId: sourceAccountId,
    destinationAccountId: destinationAccountId,
  );

  for (final amountCents in [0, -1]) {
    test('le montant $amountCents est refusé', () {
      expect(
        draft(
          type: LedgerTransactionType.expense,
          amountCents: amountCents,
          sourceAccountId: 'cash',
        ).validate(),
        isNotNull,
      );
    });
  }

  test('une transaction sans compte requis est refusée', () {
    expect(
      draft(type: LedgerTransactionType.expense, amountCents: 100).validate(),
      isNotNull,
    );
    expect(
      draft(type: LedgerTransactionType.income, amountCents: 100).validate(),
      isNotNull,
    );
  });

  test('un virement entre le même compte est refusé', () {
    expect(
      draft(
        type: LedgerTransactionType.transfer,
        amountCents: 100,
        sourceAccountId: 'cash',
        destinationAccountId: 'cash',
      ).validate(),
      isNotNull,
    );
  });

  test(
    'une dépense simple et une dépense ventilée exigent une somme exacte',
    () {
      const first = EnvelopeAllocationDraft(
        envelopeId: 'courses',
        amount: Money.fromMinorUnits(40000),
      );
      const second = EnvelopeAllocationDraft(
        envelopeId: 'maison',
        amount: Money.fromMinorUnits(10000),
      );
      expect(
        TransactionEnvelopeSplit([
          first,
          second,
        ]).validateFor(Money.fromMinorUnits(50000)),
        isNull,
      );
      expect(
        TransactionEnvelopeSplit([
          first,
        ]).validateFor(Money.fromMinorUnits(50000)),
        isNotNull,
      );
    },
  );

  test('un split refuse les doublons et les montants non positifs', () {
    const duplicate = EnvelopeAllocationDraft(
      envelopeId: 'courses',
      amount: Money.fromMinorUnits(5000),
    );
    expect(
      TransactionEnvelopeSplit([
        duplicate,
        duplicate,
      ]).validateFor(Money.fromMinorUnits(10000)),
      contains('une fois'),
    );
    expect(
      const EnvelopeAllocationDraft(
        envelopeId: 'courses',
        amount: Money.fromMinorUnits(0),
      ).validate(),
      isNotNull,
    );
  });

  for (final allocations in [
    const <EnvelopeAllocationDraft>[
      EnvelopeAllocationDraft(
        envelopeId: 'courses',
        amount: Money.fromMinorUnits(6000),
      ),
      EnvelopeAllocationDraft(
        envelopeId: 'maison',
        amount: Money.fromMinorUnits(3000),
      ),
    ],
    const <EnvelopeAllocationDraft>[
      EnvelopeAllocationDraft(
        envelopeId: 'courses',
        amount: Money.fromMinorUnits(6000),
      ),
      EnvelopeAllocationDraft(
        envelopeId: 'maison',
        amount: Money.fromMinorUnits(5000),
      ),
    ],
  ]) {
    test('un total ventilé différent du montant est refusé', () {
      expect(
        TransactionEnvelopeSplit(
          allocations,
        ).validateFor(Money.fromMinorUnits(10000)),
        isNotNull,
      );
    });
  }

  test('un split refuse une ligne sans enveloppe et un montant négatif', () {
    expect(
      const TransactionEnvelopeSplit([
        EnvelopeAllocationDraft(
          envelopeId: '',
          amount: Money.fromMinorUnits(10000),
        ),
      ]).validateFor(Money.fromMinorUnits(10000)),
      isNotNull,
    );
    expect(
      const TransactionEnvelopeSplit([
        EnvelopeAllocationDraft(
          envelopeId: 'courses',
          amount: Money.fromMinorUnits(-1),
        ),
      ]).validateFor(Money.fromMinorUnits(10000)),
      isNotNull,
    );
  });
}
