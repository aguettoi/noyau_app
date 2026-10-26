import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/operational_kpis/domain/operational_kpis.dart';

void main() {
  final start = DateTime(2026, 10);
  final end = DateTime(2026, 11);

  test(
    'ponctualité is deterministic and actor never implies responsibility',
    () {
      final result = analyzeOperationalQuality(
        periodStart: start,
        periodEndExclusive: end,
        evaluatedAt: DateTime(2026, 10, 31),
        expectedNotMaterialized: 2,
        entries: [
          OperationalEntry(
            id: 'same-day',
            economicDate: DateTime(2026, 10, 1, 8),
            enteredAt: DateTime(2026, 10, 1, 23),
            actorUserId: 'recorder-a',
            responsibility: EconomicResponsibility.member,
            economicMemberId: 'member-b',
            requiresEnvelope: true,
            hasEnvelope: true,
            requiresReceipt: true,
            hasReceipt: false,
          ),
          OperationalEntry(
            id: 'late-unassigned',
            economicDate: DateTime(2026, 10, 2),
            enteredAt: DateTime(2026, 10, 12),
            actorUserId: 'recorder-a',
            responsibility: EconomicResponsibility.unassigned,
            requiresEnvelope: true,
            hasEnvelope: false,
            requiresReceipt: true,
            hasReceipt: true,
          ),
        ],
        reconciliations: [
          ReconciliationDatum(
            id: 'open',
            openedAt: DateTime(2026, 9, 1),
            resolved: false,
          ),
        ],
      );
      expect(result.entries, 2);
      expect(result.medianDelayDays, 5);
      expect(result.meanDelayDays, 5);
      expect(result.delays.sameDay, 1);
      expect(result.delays.overSevenDays, 1);
      expect(result.missingEnvelope, 1);
      expect(result.receiptCoverage, .5);
      expect(result.unassigned, 1);
      expect(result.staleReconciliations, 1);
      expect(result.expectedNotMaterialized, 2);
      expect(result.drillDownIds['late'], ['late-unassigned']);

      final member = analyzeOperationalQuality(
        periodStart: start,
        periodEndExclusive: end,
        expectedNotMaterialized: 0,
        entries: [
          OperationalEntry(
            id: 'economic-b',
            economicDate: start,
            enteredAt: start,
            actorUserId: 'recorder-a',
            responsibility: EconomicResponsibility.member,
            economicMemberId: 'member-b',
            requiresEnvelope: false,
            hasEnvelope: false,
            requiresReceipt: false,
            hasReceipt: false,
          ),
        ],
        reconciliations: const [],
        memberId: 'recorder-a',
      );
      expect(member.entries, 0, reason: 'actor is not economic responsibility');
    },
  );

  test('period boundaries and empty period are explicit', () {
    final result = analyzeOperationalQuality(
      periodStart: start,
      periodEndExclusive: end,
      expectedNotMaterialized: 0,
      entries: [
        OperationalEntry(
          id: 'outside',
          economicDate: end,
          enteredAt: end,
          actorUserId: 'a',
          responsibility: EconomicResponsibility.household,
          requiresEnvelope: false,
          hasEnvelope: false,
          requiresReceipt: false,
          hasReceipt: false,
        ),
      ],
      reconciliations: const [],
    );
    expect(result.entries, 0);
    expect(result.expectedDelayRate, 1);
    expect(result.receiptCoverage, 1);
  });

  test('cash quality separates author, holder and responsibility', () {
    final result = analyzeCashQuality(
      periodStart: start,
      periodEndExclusive: end,
      inventories: [
        CashInventoryDatum(
          id: 'first',
          accountId: 'cash',
          observedAt: DateTime(2026, 10, 1),
          recordedAt: DateTime(2026, 10, 1),
          actorUserId: 'recorder',
          declaredHolderId: 'holder',
          explicitResponsibleId: null,
          observed: Money.fromDirhams(90),
          theoretical: Money.fromDirhams(100),
          remainingDifference: Money.fromDirhams(-10),
          denominationConsistent: true,
          resolved: false,
        ),
        CashInventoryDatum(
          id: 'second',
          accountId: 'cash',
          observedAt: DateTime(2026, 10, 11),
          recordedAt: DateTime(2026, 10, 11),
          actorUserId: 'another-recorder',
          explicitResponsibleId: 'responsible',
          observed: Money.fromDirhams(100),
          theoretical: Money.fromDirhams(100),
          denominationConsistent: false,
          resolved: true,
          resolvedAt: DateTime(2026, 10, 13),
        ),
      ],
    );
    expect(result.inventoryCount, 2);
    expect(result.averageFrequencyDays, 10);
    expect(result.differences, 1);
    expect(result.unresolvedDifferences, 1);
    expect(result.localized, 1);
    expect(result.unassigned, 1);
    expect(result.denominationInconsistencies, 1);
    expect(result.authorIsNeverResponsibleByDefault, isTrue);
  });

  test('one, two and N member profiles use only explicit attribution', () {
    for (final count in [1, 2, 5]) {
      final entries = [
        for (var index = 0; index < count; index++)
          OperationalEntry(
            id: 'e$index',
            economicDate: start,
            enteredAt: start,
            actorUserId: 'recorder',
            responsibility: EconomicResponsibility.member,
            economicMemberId: 'm$index',
            requiresEnvelope: false,
            hasEnvelope: false,
            requiresReceipt: false,
            hasReceipt: false,
          ),
      ];
      for (var index = 0; index < count; index++) {
        final result = analyzeOperationalQuality(
          periodStart: start,
          periodEndExclusive: end,
          expectedNotMaterialized: 0,
          entries: entries,
          reconciliations: const [],
          memberId: 'm$index',
        );
        expect(result.entries, 1);
      }
    }
  });

  test('significant history stays linear and bounded', () {
    final entries = List.generate(
      20000,
      (index) => OperationalEntry(
        id: 'e$index',
        economicDate: DateTime(2026, 10, index % 28 + 1),
        enteredAt: DateTime(2026, 10, index % 28 + 1),
        actorUserId: 'actor',
        responsibility: EconomicResponsibility.household,
        requiresEnvelope: true,
        hasEnvelope: true,
        requiresReceipt: true,
        hasReceipt: index.isEven,
      ),
    );
    final clock = Stopwatch()..start();
    final result = analyzeOperationalQuality(
      periodStart: start,
      periodEndExclusive: end,
      expectedNotMaterialized: 0,
      entries: entries,
      reconciliations: const [],
    );
    clock.stop();
    expect(result.entries, 20000);
    expect(result.receiptsPresent, 10000);
    // The complete Flutter suite runs test isolates concurrently on Windows.
    // Keep a generous regression ceiling while still catching a non-linear
    // implementation on this 20,000-entry fixture.
    expect(clock.elapsedMilliseconds, lessThan(5000));
  });
}
