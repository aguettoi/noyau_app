import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/budget_intelligence/application/monthly_quality_analysis.dart';
import 'package:noyau_app/features/budget_intelligence/application/providers/remote_budget_provider.dart';
import 'package:noyau_app/features/recurring_finance/domain/recurring_finance.dart';

void main() {
  const food = RemoteBudgetReportRow(
    envelopeId: 'food',
    plannedCents: 100000,
    actualCents: 40000,
    inflowsCents: 100000,
    outflowsCents: 40000,
    balanceCents: 60000,
  );

  ExpectedFinancialOccurrence occurrence({
    required String id,
    required RecurringEconomicType type,
    String? envelopeId,
    String? memberId,
    ExpectedOccurrenceStatus status = ExpectedOccurrenceStatus.expected,
    int cents = 20000,
  }) => ExpectedFinancialOccurrence(
    id: id,
    intentionId: 'intention-$id',
    expectedOn: DateTime(2026, 10, 20),
    type: type,
    label: id,
    expectedAmount: Money.fromMinorUnits(cents),
    confirmedAmount: const Money.fromMinorUnits(0),
    status: status,
    envelopeId: envelopeId,
    memberId: memberId,
  );

  test('BUD-10 distingue prévu, réalisé, attendu et restant', () {
    final result = analyzeMonthlyQuality(
      periodStart: DateTime(2026, 10),
      periodEnd: DateTime(2026, 10, 31),
      budget: const [food],
      occurrences: [
        occurrence(
          id: 'expense',
          type: RecurringEconomicType.expense,
          envelopeId: 'food',
        ),
      ],
      events: const [],
      reconciliations: const [],
    );
    expect(result.plannedCents, 100000);
    expect(result.actualCents, 40000);
    expect(result.expectedCents, 20000);
    expect(result.remainingCents, 40000);
  });

  test('R2-09 et R2-10 calculent rapprochements et santé justificatifs', () {
    final result = analyzeMonthlyQuality(
      periodStart: DateTime(2026, 10),
      periodEnd: DateTime(2026, 10, 31),
      budget: const [food],
      occurrences: const [],
      events: const [
        MonthlyQualityEvent(
          id: 'with-proof',
          requiresReceipt: true,
          hasReceipt: true,
          responsibility: MonthlyResponsibility.member,
        ),
        MonthlyQualityEvent(
          id: 'missing-proof',
          requiresReceipt: true,
          hasReceipt: false,
          responsibility: MonthlyResponsibility.unassigned,
        ),
      ],
      reconciliations: [
        MonthlyQualityReconciliation(open: true, observedAt: DateTime(2026, 8)),
      ],
      now: DateTime(2026, 10, 31),
    );
    expect(result.reconciliations.open, 1);
    expect(result.reconciliations.stale, 1);
    expect(result.receipts.coverage, .5);
    expect(result.receipts.missing, 1);
    expect(
      result.explanations.map((e) => e.source),
      containsAll([
        'account_reconciliation_cases',
        'financial_event_attachments',
      ]),
    );
  });

  test('R2-11 conserve membre, foyer et non attribué pour 1/2/N', () {
    final result = analyzeMonthlyQuality(
      periodStart: DateTime(2026, 10),
      periodEnd: DateTime(2026, 10, 31),
      budget: const [],
      occurrences: const [],
      events: const [
        MonthlyQualityEvent(
          id: 'household',
          requiresReceipt: false,
          hasReceipt: false,
          responsibility: MonthlyResponsibility.household,
        ),
        MonthlyQualityEvent(
          id: 'member-1',
          requiresReceipt: false,
          hasReceipt: false,
          responsibility: MonthlyResponsibility.member,
        ),
        MonthlyQualityEvent(
          id: 'member-2',
          requiresReceipt: false,
          hasReceipt: false,
          responsibility: MonthlyResponsibility.member,
        ),
        MonthlyQualityEvent(
          id: 'unknown',
          requiresReceipt: false,
          hasReceipt: false,
          responsibility: MonthlyResponsibility.unassigned,
        ),
      ],
      reconciliations: const [],
    );
    expect(result.responsibilities.household, 1);
    expect(result.responsibilities.member, 2);
    expect(result.responsibilities.unassigned, 1);
  });

  test('PLAN-07 sépare revenu variable attendu du budget récurrent', () {
    final result = analyzeMonthlyQuality(
      periodStart: DateTime(2026, 10),
      periodEnd: DateTime(2026, 10, 31),
      budget: const [food],
      occurrences: [
        occurrence(
          id: 'bonus-member-n',
          type: RecurringEconomicType.income,
          memberId: 'member-n',
          cents: 35000,
        ),
      ],
      events: const [],
      reconciliations: const [],
    );
    final bonus = result.options.singleWhere(
      (e) => e.kind == MonthlyDecisionKind.variableIncome,
    );
    expect(bonus.amountCents, 35000);
    expect(bonus.explanation.status, 'attendu');
    expect(result.plannedCents, 100000);
  });

  test('PLAN-08 produit des arbitrages read-only explicables', () {
    final result = analyzeMonthlyQuality(
      periodStart: DateTime(2026, 10),
      periodEnd: DateTime(2026, 10, 31),
      budget: const [food],
      occurrences: const [],
      events: const [],
      reconciliations: const [],
    );
    expect(
      result.options.map((e) => e.kind),
      containsAll([
        MonthlyDecisionKind.preserveLiquidity,
        MonthlyDecisionKind.savings,
        MonthlyDecisionKind.priorities,
      ]),
    );
    expect(result.options.every((e) => e.requiresConfirmation), isTrue);
    expect(
      result.options.every((e) => e.explanation.source.isNotEmpty),
      isTrue,
    );
  });

  test(
    'PLAN-08 refuse une recommandation lorsque la capacité est incomplète',
    () {
      final result = analyzeMonthlyQuality(
        periodStart: DateTime(2026, 10),
        periodEnd: DateTime(2026, 10, 31),
        budget: const [food],
        occurrences: const [],
        events: const [],
        reconciliations: const [],
        availabilityComplete: false,
      );
      final option = result.options.singleWhere(
        (e) => e.kind == MonthlyDecisionKind.priorities,
      );
      expect(option.explanation.status, 'données insuffisantes');
      expect(option.consequence, contains('aucune recommandation'));
    },
  );

  test('occurrence réalisée ou ignorée ne reste pas attendue', () {
    final result = analyzeMonthlyQuality(
      periodStart: DateTime(2026, 10),
      periodEnd: DateTime(2026, 10, 31),
      budget: const [food],
      occurrences: [
        occurrence(
          id: 'done',
          type: RecurringEconomicType.expense,
          envelopeId: 'food',
          status: ExpectedOccurrenceStatus.realized,
        ),
        occurrence(
          id: 'ignored',
          type: RecurringEconomicType.expense,
          envelopeId: 'food',
          status: ExpectedOccurrenceStatus.ignored,
        ),
      ],
      events: const [],
      reconciliations: const [],
    );
    expect(result.unresolvedOccurrences, 0);
    expect(result.expectedCents, 0);
  });
}
