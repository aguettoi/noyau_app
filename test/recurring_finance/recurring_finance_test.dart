import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/recurring_finance/domain/recurring_finance.dart';

void main() {
  ExpectedFinancialOccurrence expected({
    int confirmed = 0,
    String? account = 'account-a',
    String? envelope = 'food',
    String? member = 'member-a',
  }) => ExpectedFinancialOccurrence(
    id: 'occurrence',
    intentionId: 'rule',
    expectedOn: DateTime(2026, 10, 25),
    type: RecurringEconomicType.expense,
    label: 'Abonnement internet',
    expectedAmount: const Money.fromMinorUnits(65000),
    confirmedAmount: Money.fromMinorUnits(confirmed),
    status: confirmed == 0
        ? ExpectedOccurrenceStatus.expected
        : ExpectedOccurrenceStatus.partiallyRealized,
    sourceAccountId: account,
    envelopeId: envelope,
    memberId: member,
  );

  ActualFinancialCandidate actual({
    int amount = 65000,
    DateTime? date,
    String account = 'account-a',
    String envelope = 'food',
    String member = 'member-a',
  }) => ActualFinancialCandidate(
    id: 'event',
    type: RecurringEconomicType.expense,
    occurredAt: date ?? DateTime(2026, 10, 25),
    amount: Money.fromMinorUnits(amount),
    description: 'Paiement abonnement internet',
    accountId: account,
    envelopeId: envelope,
    memberId: member,
  );

  test('matching exact remains explainable and eligible', () {
    final result = assessExpectedMatch(
      expected(),
      actual(),
      const MatchingTolerance(),
    );
    expect(result.exact, isTrue);
    expect(result.eligible, isTrue);
    expect(result.reasons, containsAll(['Même date', 'Même montant']));
  });

  test('date and amount tolerances are centralized', () {
    final result = assessExpectedMatch(
      expected(),
      actual(amount: 64500, date: DateTime(2026, 10, 27)),
      const MatchingTolerance(),
    );
    expect(result.eligible, isTrue);
    expect(result.exact, isFalse);
  });

  test('partial and split payments use the derived remaining amount', () {
    final first = assessExpectedMatch(
      expected(),
      actual(amount: 20000),
      const MatchingTolerance(),
    );
    final second = assessExpectedMatch(
      expected(confirmed: 20000),
      actual(amount: 45000),
      const MatchingTolerance(),
    );
    expect(first.eligible, isTrue);
    expect(second.eligible, isTrue);
    expect(expected(confirmed: 20000).remaining.minorUnits, 45000);
  });

  test('wrong account or member is rejected conservatively', () {
    final result = assessExpectedMatch(
      expected(),
      actual(account: 'account-b', member: 'member-b'),
      const MatchingTolerance(),
    );
    expect(result.eligible, isFalse);
    expect(result.reasons, contains('Compte différent'));
  });

  test('unknown account envelope and member remain valid', () {
    final result = assessExpectedMatch(
      expected(account: null, envelope: null, member: null),
      actual(),
      const MatchingTolerance(),
    );
    expect(result.eligible, isTrue);
  });

  test('monthly anchor survives month-end and yearly survives leap day', () {
    expect(
      nextRecurringDate(
        DateTime(2026, 1, 31),
        RecurringFrequency.monthly,
        anchorDay: 31,
      ),
      DateTime(2026, 2, 28),
    );
    expect(
      nextRecurringDate(
        DateTime(2024, 2, 29),
        RecurringFrequency.yearly,
        anchorDay: 29,
      ),
      DateTime(2025, 2, 28),
    );
  });
}
