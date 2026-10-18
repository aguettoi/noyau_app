import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/cashflow_projection/domain/cashflow_projection.dart';
import 'package:noyau_app/features/recurring_finance/domain/recurring_finance.dart';
import 'package:noyau_app/features/wealth/domain/wealth_models.dart';

ExpectedFinancialOccurrence occurrence({
  required String id,
  required RecurringEconomicType type,
  required int amount,
  int confirmed = 0,
  ExpectedOccurrenceStatus status = ExpectedOccurrenceStatus.expected,
  String? source,
  String? destination,
  String? envelope,
  String? member,
  DateTime? date,
}) => ExpectedFinancialOccurrence(
  id: id,
  intentionId: 'rule-$id',
  expectedOn: date ?? DateTime(2026, 11, 10),
  type: type,
  label: id,
  expectedAmount: Money.fromMinorUnits(amount),
  confirmedAmount: Money.fromMinorUnits(confirmed),
  status: status,
  sourceAccountId: source,
  destinationAccountId: destination,
  envelopeId: envelope,
  memberId: member,
);

void main() {
  final asOf = DateTime(2026, 11, 1);
  final through = DateTime(2026, 12, 31);

  test(
    'income, expense and internal transfer preserve household semantics',
    () {
      final result = buildCashflowProjection(
        asOf: asOf,
        through: through,
        accountBalances: const {
          'a': Money.fromMinorUnits(100000),
          'b': Money.fromMinorUnits(50000),
        },
        envelopeBalances: const {'food': Money.fromMinorUnits(30000)},
        occurrences: [
          occurrence(
            id: 'salary',
            type: RecurringEconomicType.income,
            amount: 20000,
            destination: 'a',
            member: 'm1',
          ),
          occurrence(
            id: 'food',
            type: RecurringEconomicType.expense,
            amount: 10000,
            source: 'a',
            envelope: 'food',
            member: 'm1',
          ),
          occurrence(
            id: 'move',
            type: RecurringEconomicType.accountTransfer,
            amount: 25000,
            source: 'a',
            destination: 'b',
          ),
        ],
      );
      expect(result.projectedHouseholdBalance.minorUnits, 160000);
      expect(result.projectedAccountBalances['a']!.minorUnits, 85000);
      expect(result.projectedAccountBalances['b']!.minorUnits, 75000);
      expect(result.projectedEnvelopeBalances['food']!.minorUnits, 20000);
      expect(result.transfers.minorUnits, 25000);
    },
  );

  test('unknown account remains unlocated but affects household', () {
    final result = buildCashflowProjection(
      asOf: asOf,
      through: through,
      accountBalances: const {'a': Money.fromMinorUnits(100000)},
      envelopeBalances: const {},
      occurrences: [
        occurrence(
          id: 'bill',
          type: RecurringEconomicType.expense,
          amount: 30000,
        ),
      ],
    );
    expect(result.projectedHouseholdBalance.minorUnits, 70000);
    expect(result.projectedAccountBalances['a']!.minorUnits, 100000);
    expect(result.unlocatedAmount.minorUnits, 30000);
  });

  test(
    'partial is projected only for remaining amount and terminal states excluded',
    () {
      final result = buildCashflowProjection(
        asOf: asOf,
        through: through,
        accountBalances: const {'a': Money.fromMinorUnits(100000)},
        envelopeBalances: const {},
        occurrences: [
          occurrence(
            id: 'partial',
            type: RecurringEconomicType.expense,
            amount: 30000,
            confirmed: 10000,
            source: 'a',
            status: ExpectedOccurrenceStatus.partiallyRealized,
          ),
          occurrence(
            id: 'done',
            type: RecurringEconomicType.expense,
            amount: 5000,
            source: 'a',
            status: ExpectedOccurrenceStatus.realized,
          ),
          occurrence(
            id: 'ignored',
            type: RecurringEconomicType.expense,
            amount: 5000,
            source: 'a',
            status: ExpectedOccurrenceStatus.ignored,
          ),
        ],
      );
      expect(result.flows, hasLength(1));
      expect(result.expenses.minorUnits, 20000);
    },
  );

  test('F5 schedule is included once and R3.1 takes precedence on overlap', () {
    final financing = FinancingProfile(
      id: 'loan',
      label: 'Financement',
      structure: FinancingStructure.fixedCost,
      obligationId: 'o',
      principalInitial: const Money.fromMinorUnits(120000),
      remainingLiability: const Money.fromMinorUnits(120000),
      startDate: DateTime(2026, 10, 10),
      durationMonths: 12,
      periodicityMonths: 1,
      scheduledPayment: const Money.fromMinorUnits(10000),
    );
    final result = buildCashflowProjection(
      asOf: asOf,
      through: DateTime(2026, 11, 30),
      accountBalances: const {'a': Money.fromMinorUnits(100000)},
      envelopeBalances: const {},
      occurrences: [
        occurrence(
          id: 'Financement mensuel',
          type: RecurringEconomicType.expense,
          amount: 10000,
          source: 'a',
          date: DateTime(2026, 11, 10),
        ),
      ],
      financings: [financing],
    );
    expect(result.flows, hasLength(1));
    expect(result.flows.single.source, contains('R3.1'));
  });

  test(
    'negative account risk is detected while household remains positive',
    () {
      final result = buildCashflowProjection(
        asOf: asOf,
        through: through,
        accountBalances: const {
          'a': Money.fromMinorUnits(1000),
          'b': Money.fromMinorUnits(100000),
        },
        envelopeBalances: const {},
        occurrences: [
          occurrence(
            id: 'large',
            type: RecurringEconomicType.expense,
            amount: 2000,
            source: 'a',
          ),
        ],
      );
      expect(result.projectedHouseholdBalance.minorUnits, greaterThan(0));
      expect(result.risks.single.message, contains('compte'));
    },
  );

  test(
    'active recurrence expands to horizon; suspended recurrence does not',
    () {
      RecurringFinancialIntention rule(String id, RecurringStatus status) =>
          RecurringFinancialIntention(
            id: id,
            householdId: 'h',
            type: RecurringEconomicType.expense,
            label: id,
            amount: const Money.fromMinorUnits(1000),
            currency: 'MAD',
            frequency: RecurringFrequency.monthly,
            startsOn: DateTime(2026, 11, 15),
            nextOccurrenceOn: DateTime(2026, 11, 15),
            certainty: RecurringCertainty.certain,
            status: status,
          );
      final values = expandExpectedOccurrences(
        asOf: asOf,
        through: DateTime(2027, 2, 28),
        intentions: [
          rule('active', RecurringStatus.active),
          rule('suspended', RecurringStatus.suspended),
        ],
        persisted: const [],
      );
      expect(values, hasLength(4));
      expect(values.every((e) => e.intentionId == 'active'), isTrue);
    },
  );

  test('member and multi-account envelope projections stay separate', () {
    final result = buildCashflowProjection(
      asOf: asOf,
      through: through,
      accountBalances: const {
        'a': Money.fromMinorUnits(50000),
        'b': Money.fromMinorUnits(50000),
      },
      envelopeBalances: const {
        'habits': Money.fromMinorUnits(20000),
        'saving': Money.fromMinorUnits(30000),
      },
      occurrences: [
        occurrence(
          id: 'a-clothes',
          type: RecurringEconomicType.expense,
          amount: 5000,
          source: 'a',
          envelope: 'habits',
          member: 'm1',
        ),
        occurrence(
          id: 'b-clothes',
          type: RecurringEconomicType.expense,
          amount: 7000,
          source: 'b',
          envelope: 'habits',
          member: 'm2',
        ),
      ],
    );
    expect(result.projectedEnvelopeBalances['habits']!.minorUnits, 8000);
    expect(result.memberDeltas.keys, containsAll(['m1', 'm2']));
    expect(result.projectedEnvelopeBalances['saving']!.minorUnits, 30000);
  });

  test('projection is deterministic and never mutates its inputs', () {
    final accounts = <String, Money>{'a': const Money.fromMinorUnits(1000)};
    final envelopes = <String, Money>{'e': const Money.fromMinorUnits(1000)};
    final first = buildCashflowProjection(
      asOf: asOf,
      through: through,
      accountBalances: accounts,
      envelopeBalances: envelopes,
      occurrences: const [],
    );
    final second = buildCashflowProjection(
      asOf: asOf,
      through: through,
      accountBalances: accounts,
      envelopeBalances: envelopes,
      occurrences: const [],
    );
    expect(first.projectedHouseholdBalance, second.projectedHouseholdBalance);
    expect(accounts['a']!.minorUnits, 1000);
    expect(envelopes['e']!.minorUnits, 1000);
  });
}
