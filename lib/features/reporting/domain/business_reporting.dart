import '../../../core/money/money.dart';
import '../../finance/domain/transaction_draft.dart';
import '../../finance/domain/transaction_history_item.dart';
import '../../monthly_close/domain/monthly_close.dart';
import '../../wealth/domain/wealth_history.dart';

enum ReportFactStatus { observed, expected, projected, imported }

enum ReportFactSource {
  financialEvent,
  monthlyClose,
  obligation,
  financing,
  importedHistory,
}

class ReportingPeriod {
  const ReportingPeriod({required this.start, required this.endExclusive});
  final DateTime start;
  final DateTime endExclusive;

  factory ReportingPeriod.month(DateTime value) => ReportingPeriod(
    start: DateTime(value.year, value.month),
    endExclusive: DateTime(value.year, value.month + 1),
  );

  bool contains(DateTime value) =>
      !value.isBefore(start) && value.isBefore(endExclusive);
}

class BusinessReportCategory {
  const BusinessReportCategory({
    required this.key,
    required this.label,
    required this.total,
    required this.count,
    required this.status,
  });
  final String key;
  final String label;
  final Money total;
  final int count;
  final ReportFactStatus status;
}

class BusinessPeriodReport {
  const BusinessPeriodReport({
    required this.period,
    required this.categories,
    required this.closeStatus,
    required this.blockers,
    required this.warnings,
    required this.isPartial,
    required this.explanations,
  });
  final ReportingPeriod period;
  final List<BusinessReportCategory> categories;
  final MonthlyCloseStatus closeStatus;
  final int blockers;
  final int warnings;
  final bool isPartial;
  final List<String> explanations;
}

BusinessPeriodReport buildBusinessPeriodReport({
  required ReportingPeriod period,
  required Iterable<TransactionHistoryItem> transactions,
  required MonthlyCloseSnapshot close,
  required Iterable<TimelineFact> importedFacts,
}) {
  final relevant = transactions.where((e) => period.contains(e.occurredAt));
  final groups = <String, List<TransactionHistoryItem>>{};
  for (final item in relevant) {
    final key = _categoryKey(item.type);
    groups.putIfAbsent(key, () => []).add(item);
  }
  final categories = <BusinessReportCategory>[
    for (final entry in groups.entries)
      BusinessReportCategory(
        key: entry.key,
        label: _categoryLabel(entry.key),
        total: Money.fromMinorUnits(
          entry.value.fold(0, (sum, item) => sum + item.amount.minorUnits),
        ),
        count: entry.value.length,
        status: ReportFactStatus.observed,
      ),
    if (importedFacts.isNotEmpty)
      BusinessReportCategory(
        key: 'imported',
        label: 'Historique importé',
        total: Money.fromMinorUnits(
          importedFacts.fold(
            0,
            (sum, item) => sum + (item.amount?.minorUnits ?? 0),
          ),
        ),
        count: importedFacts.length,
        status: ReportFactStatus.imported,
      ),
  ]..sort((a, b) => a.label.compareTo(b.label));
  return BusinessPeriodReport(
    period: period,
    categories: List.unmodifiable(categories),
    closeStatus: close.status,
    blockers: close.blockers,
    warnings: close.warnings,
    isPartial: close.periodId == null,
    explanations: List.unmodifiable([
      '${relevant.length} événement(s) natif(s) autorisé(s) sur la période',
      'Clôture ${close.status.name} : ${close.blockers} blocage(s), ${close.warnings} avertissement(s)',
      importedFacts.isNotEmpty
          ? 'Historique importé distingué des événements natifs'
          : 'Aucune ligne historique importée visible sur cette période',
      if (close.periodId == null)
        'Aucun snapshot de clôture figé : restitution courante partielle',
    ]),
  );
}

class TimelineFact {
  const TimelineFact({
    required this.identity,
    required this.title,
    required this.date,
    required this.status,
    required this.source,
    required this.reason,
    this.amount,
    this.manuallyMarked = false,
    this.canToggleMark = false,
  });
  final String identity;
  final String title;
  final DateTime date;
  final Money? amount;
  final ReportFactStatus status;
  final ReportFactSource source;
  final String reason;
  final bool manuallyMarked;
  final bool canToggleMark;
}

List<TimelineFact> buildSignificantTimeline({
  required ReportingPeriod period,
  required Iterable<TransactionHistoryItem> nativeEvents,
  required Iterable<TimelineFact> importedFacts,
  required Iterable<MonthlyCloseAuditEntry> closeDecisions,
  required Iterable<ConsolidatedDue> dues,
  Set<String> manualMarks = const {},
}) {
  final facts = <TimelineFact>[];
  for (final item in nativeEvents.where((e) => period.contains(e.occurredAt))) {
    final sourceId = item.financialEventId;
    final identity = sourceId == null
        ? 'transaction:${item.id}'
        : 'financial_event:$sourceId';
    final marked = manualMarks.contains(identity);
    final reason = _nativeSignificanceReason(item, marked);
    if (reason == null) continue;
    facts.add(
      TimelineFact(
        identity: identity,
        title: item.description,
        date: item.occurredAt,
        amount: item.amount,
        status: ReportFactStatus.observed,
        source: ReportFactSource.financialEvent,
        reason: reason,
        manuallyMarked: marked,
        canToggleMark: sourceId != null,
      ),
    );
  }
  facts.addAll(importedFacts.where((e) => period.contains(e.date)));
  for (final item in closeDecisions.where((e) => period.contains(e.at))) {
    facts.add(
      TimelineFact(
        identity: 'monthly_close:${item.at.toIso8601String()}:${item.kind}',
        title: _closeTitle(item.kind),
        date: item.at,
        status: ReportFactStatus.observed,
        source: ReportFactSource.monthlyClose,
        reason: item.reason?.trim().isNotEmpty == true
            ? item.reason!
            : 'Décision de clôture auditée',
      ),
    );
  }
  for (final due in dues.where((e) => period.contains(e.date))) {
    facts.add(
      TimelineFact(
        identity: '${due.kind.name}:${due.sourceId}',
        title: due.label,
        date: due.date,
        amount: due.amount,
        status: due.state == ConsolidatedDueState.projected
            ? ReportFactStatus.projected
            : ReportFactStatus.expected,
        source: due.kind == ConsolidatedDueKind.financing
            ? ReportFactSource.financing
            : ReportFactSource.obligation,
        reason: due.state == ConsolidatedDueState.projected
            ? 'Échéance projetée par le financement canonique'
            : 'Échéance attendue sur la période',
      ),
    );
  }
  final unique = <String, TimelineFact>{};
  for (final fact in facts) {
    unique.putIfAbsent(
      '${fact.identity}|${fact.date.toIso8601String()}',
      () => fact,
    );
  }
  final result = unique.values.toList()
    ..sort((a, b) => b.date.compareTo(a.date));
  return List.unmodifiable(result);
}

String? _nativeSignificanceReason(
  TransactionHistoryItem item,
  bool manuallyMarked,
) {
  if (manuallyMarked) return 'Marqué comme significatif par l’utilisateur';
  if (item.isReversal || item.isReversed) {
    return 'Correction ou annulation auditée';
  }
  if (item.attachments.isNotEmpty) {
    return 'Événement documenté par un justificatif';
  }
  if ({
    LedgerTransactionType.debtExpense,
    LedgerTransactionType.debtSettlement,
    LedgerTransactionType.incomeReceivable,
    LedgerTransactionType.receivableSettlement,
    LedgerTransactionType.recoveryReceivable,
    LedgerTransactionType.recoverySettlement,
  }.contains(item.type)) {
    return 'Création ou évolution d’une obligation canonique';
  }
  return null;
}

String _categoryKey(LedgerTransactionType type) => switch (type) {
  LedgerTransactionType.income => 'income',
  LedgerTransactionType.expense => 'expense',
  LedgerTransactionType.accountTransfer ||
  LedgerTransactionType.transfer => 'transfer',
  LedgerTransactionType.debtExpense ||
  LedgerTransactionType.debtSettlement => 'debt',
  LedgerTransactionType.incomeReceivable ||
  LedgerTransactionType.receivableSettlement ||
  LedgerTransactionType.recovery ||
  LedgerTransactionType.recoveryReceivable ||
  LedgerTransactionType.recoverySettlement => 'receivable',
  _ => 'other',
};

String _categoryLabel(String key) => switch (key) {
  'income' => 'Revenus réalisés',
  'expense' => 'Dépenses réalisées',
  'transfer' => 'Transferts internes',
  'debt' => 'Dettes et règlements',
  'receivable' => 'Créances et encaissements',
  _ => 'Autres événements canoniques',
};

String _closeTitle(String kind) => switch (kind) {
  'closed' => 'Période clôturée',
  'reopened' => 'Période rouverte',
  _ => 'Décision de clôture',
};
