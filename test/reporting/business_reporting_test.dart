import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/finance/domain/transaction_draft.dart';
import 'package:noyau_app/features/finance/domain/transaction_history_item.dart';
import 'package:noyau_app/features/monthly_close/domain/monthly_close.dart';
import 'package:noyau_app/features/reporting/domain/business_reporting.dart';
import 'package:noyau_app/features/wealth/domain/wealth_history.dart';

void main() {
  TransactionHistoryItem event(
    String id,
    LedgerTransactionType type,
    DateTime date, {
    bool reversed = false,
  }) => TransactionHistoryItem(
    id: id,
    financialEventId: 'event-$id',
    type: type,
    occurredAt: date,
    description: 'Événement $id',
    amount: Money.fromDirhams(100),
    createdAt: date,
    isReversed: reversed,
  );

  test('rapport respecte les frontières mensuelles et distingue importé', () {
    final period = ReportingPeriod.month(DateTime(2026, 12));
    final imported = TimelineFact(
      identity: 'historical_analytic_line:1',
      title: 'Décision importée',
      date: DateTime(2026, 12, 15),
      amount: Money.fromDirhams(25),
      status: ReportFactStatus.imported,
      source: ReportFactSource.importedHistory,
      reason: 'Décision auditée',
    );
    final result = buildBusinessPeriodReport(
      period: period,
      transactions: [
        event('a', LedgerTransactionType.income, DateTime(2026, 12, 1)),
        event('b', LedgerTransactionType.expense, DateTime(2026, 12, 31, 23)),
        event('c', LedgerTransactionType.expense, DateTime(2027, 1, 1)),
      ],
      close: MonthlyCloseSnapshot(
        month: period.start,
        status: MonthlyCloseStatus.open,
        issues: const [],
      ),
      importedFacts: [imported],
    );

    expect(
      result.categories.map((e) => e.key),
      containsAll(['income', 'expense', 'imported']),
    );
    expect(result.categories.where((e) => e.key == 'expense').single.count, 1);
    expect(
      result.categories.where((e) => e.key == 'imported').single.status,
      ReportFactStatus.imported,
    );
    expect(result.isPartial, isTrue);
  });

  test(
    'timeline exclut le bruit, explique les faits et évite les doublons',
    () {
      final period = ReportingPeriod.month(DateTime(2026, 10));
      final ordinary = event(
        'ordinary',
        LedgerTransactionType.expense,
        DateTime(2026, 10, 2),
      );
      final debt = event(
        'debt',
        LedgerTransactionType.debtExpense,
        DateTime(2026, 10, 3),
      );
      final reversed = event(
        'reversed',
        LedgerTransactionType.expense,
        DateTime(2026, 10, 4),
        reversed: true,
      );
      final due = ConsolidatedDue(
        identity: 'obligation:o1',
        label: 'Échéance',
        date: DateTime(2026, 10, 5),
        amount: Money.fromDirhams(80),
        kind: ConsolidatedDueKind.obligation,
        state: ConsolidatedDueState.expected,
        sourceId: 'o1',
      );
      final result = buildSignificantTimeline(
        period: period,
        nativeEvents: [ordinary, debt, reversed],
        importedFacts: const [],
        closeDecisions: const [],
        dues: [due, due],
      );

      expect(
        result.map((e) => e.identity),
        isNot(contains('financial_event:event-ordinary')),
      );
      expect(
        result.map((e) => e.identity),
        containsAll([
          'financial_event:event-debt',
          'financial_event:event-reversed',
          'obligation:o1',
        ]),
      );
      expect(result.where((e) => e.identity == 'obligation:o1'), hasLength(1));
      expect(
        result.map((e) => e.date).toList(),
        orderedEquals(
          [...result.map((e) => e.date)]..sort((a, b) => b.compareTo(a)),
        ),
      );
      expect(result.every((e) => e.reason.isNotEmpty), isTrue);
    },
  );

  test('marquage manuel est déterministe, personnel et sans seuil montant', () {
    final item = event(
      'manual',
      LedgerTransactionType.expense,
      DateTime(2026, 10, 8),
    );
    final result = buildSignificantTimeline(
      period: ReportingPeriod.month(DateTime(2026, 10)),
      nativeEvents: [item],
      importedFacts: const [],
      closeDecisions: const [],
      dues: const [],
      manualMarks: const {'financial_event:event-manual'},
    );
    expect(result.single.manuallyMarked, isTrue);
    expect(result.single.reason, contains('utilisateur'));
  });

  test('composition reste linéaire sur un historique supérieur à C3', () {
    final events = List.generate(
      2000,
      (i) => event(
        '$i',
        i.isEven
            ? LedgerTransactionType.debtExpense
            : LedgerTransactionType.expense,
        DateTime(2026, 10, (i % 28) + 1),
      ),
    );
    final timeline = buildSignificantTimeline(
      period: ReportingPeriod.month(DateTime(2026, 10)),
      nativeEvents: events,
      importedFacts: const [],
      closeDecisions: const [],
      dues: const [],
    );
    expect(timeline, hasLength(1000));
  });
}
