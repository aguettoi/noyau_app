import '../../../core/money/money.dart';

enum EconomicResponsibility { household, member, unassigned }

class KpiExplanation {
  const KpiExplanation({
    required this.id,
    required this.rule,
    required this.source,
    required this.period,
    required this.reason,
    required this.completeness,
    this.memberId,
    this.limitations = const [],
  });

  final String id;
  final String rule, source, period, reason, completeness;
  final String? memberId;
  final List<String> limitations;
}

class OperationalEntry {
  const OperationalEntry({
    required this.id,
    required this.economicDate,
    required this.enteredAt,
    required this.actorUserId,
    required this.responsibility,
    required this.requiresEnvelope,
    required this.hasEnvelope,
    required this.requiresReceipt,
    required this.hasReceipt,
    this.categorized = true,
    this.economicMemberId,
    this.economicMemberIds = const [],
  });

  final String id, actorUserId;
  final DateTime economicDate, enteredAt;
  final EconomicResponsibility responsibility;
  final String? economicMemberId;

  /// Explicit responsibilities only. Multiple members are supported; an empty
  /// list means that no individual responsibility was recorded.
  final List<String> economicMemberIds;
  final bool requiresEnvelope, hasEnvelope, requiresReceipt, hasReceipt;
  final bool categorized;

  int get entryDelayDays {
    final economic = DateTime(
      economicDate.year,
      economicDate.month,
      economicDate.day,
    );
    final entered = DateTime(enteredAt.year, enteredAt.month, enteredAt.day);
    final value = entered.difference(economic).inDays;
    return value < 0 ? 0 : value;
  }
}

enum EntryAttributionDimension { economicResponsibility, entryAuthor }

class ReconciliationDatum {
  const ReconciliationDatum({
    required this.id,
    required this.openedAt,
    required this.resolved,
    this.accountId,
    this.accountType,
    this.remaining,
    this.resolvedAt,
  });
  final String id;
  final DateTime openedAt;
  final bool resolved;
  final String? accountId, accountType;
  final Money? remaining;
  final DateTime? resolvedAt;
}

class ReconciliationBreakdown {
  const ReconciliationBreakdown({
    required this.open,
    required this.resolved,
    required this.unresolvedAmount,
    required this.oldestOpenDays,
  });
  final int open, resolved, oldestOpenDays;
  final Money unresolvedAmount;
  double get resolutionRate =>
      open + resolved == 0 ? 1 : resolved / (open + resolved);
}

class EntryDelayDistribution {
  const EntryDelayDistribution({
    required this.sameDay,
    required this.nextDay,
    required this.twoToThreeDays,
    required this.fourToSevenDays,
    required this.overSevenDays,
  });

  final int sameDay, nextDay, twoToThreeDays, fourToSevenDays, overSevenDays;
  int get total =>
      sameDay + nextDay + twoToThreeDays + fourToSevenDays + overSevenDays;
}

class OperationalQualitySnapshot {
  const OperationalQualitySnapshot({
    required this.periodStart,
    required this.periodEndExclusive,
    required this.entries,
    required this.meanDelayDays,
    required this.medianDelayDays,
    required this.delays,
    required this.withinExpectedDelay,
    required this.uncategorized,
    required this.missingEnvelope,
    required this.receiptsRequired,
    required this.receiptsPresent,
    required this.openReconciliations,
    required this.staleReconciliations,
    required this.resolvedReconciliations,
    required this.unassigned,
    required this.expectedNotMaterialized,
    required this.explanations,
    required this.drillDownIds,
    required this.reconciliation,
    required this.reconciliationByAccount,
    required this.reconciliationByAccountType,
    this.memberId,
  });

  final DateTime periodStart, periodEndExclusive;
  final String? memberId;
  final int entries;
  final double meanDelayDays, medianDelayDays;
  final EntryDelayDistribution delays;
  final int withinExpectedDelay;
  final int uncategorized, missingEnvelope;
  final int receiptsRequired, receiptsPresent;
  final int openReconciliations, staleReconciliations, resolvedReconciliations;
  final int unassigned, expectedNotMaterialized;
  final List<KpiExplanation> explanations;
  final Map<String, List<String>> drillDownIds;
  final ReconciliationBreakdown reconciliation;
  final Map<String, ReconciliationBreakdown> reconciliationByAccount;
  final Map<String, ReconciliationBreakdown> reconciliationByAccountType;

  double get expectedDelayRate =>
      entries == 0 ? 1 : withinExpectedDelay / entries;
  double get receiptCoverage =>
      receiptsRequired == 0 ? 1 : receiptsPresent / receiptsRequired;
  bool get complete =>
      explanations.every((item) => item.completeness == 'complet');
}

OperationalQualitySnapshot analyzeOperationalQuality({
  required DateTime periodStart,
  required DateTime periodEndExclusive,
  required List<OperationalEntry> entries,
  required List<ReconciliationDatum> reconciliations,
  required int expectedNotMaterialized,
  DateTime? evaluatedAt,
  String? memberId,
  int expectedDelayDays = 1,
  EntryAttributionDimension attributionDimension =
      EntryAttributionDimension.economicResponsibility,
}) {
  final now = evaluatedAt ?? periodEndExclusive;
  bool inPeriod(DateTime value) =>
      !value.isBefore(periodStart) && value.isBefore(periodEndExclusive);
  final scoped = entries
      .where((item) {
        if (!inPeriod(item.economicDate)) return false;
        if (memberId == null) return true;
        // The actor is deliberately ignored here. Only an explicit economic
        // member can attribute an entry to a member profile.
        if (attributionDimension == EntryAttributionDimension.entryAuthor) {
          return item.actorUserId == memberId;
        }
        return item.responsibility == EconomicResponsibility.member &&
            (item.economicMemberIds.contains(memberId) ||
                item.economicMemberId == memberId);
      })
      .toList(growable: false);
  final delayValues = scoped.map((item) => item.entryDelayDays).toList()
    ..sort();
  final mean = delayValues.isEmpty
      ? 0.0
      : delayValues.fold<int>(0, (sum, item) => sum + item) /
            delayValues.length;
  final median = delayValues.isEmpty
      ? 0.0
      : delayValues.length.isOdd
      ? delayValues[delayValues.length ~/ 2].toDouble()
      : (delayValues[delayValues.length ~/ 2 - 1] +
                delayValues[delayValues.length ~/ 2]) /
            2;
  List<String> ids(bool Function(OperationalEntry) test) =>
      scoped.where(test).map((item) => item.id).toList(growable: false);
  final requiredReceipts = scoped
      .where((item) => item.requiresReceipt)
      .toList();
  final open = reconciliations.where((item) => !item.resolved).toList();
  ReconciliationBreakdown reconciliationBreakdown(
    Iterable<ReconciliationDatum> values,
  ) {
    final list = values.toList(growable: false);
    final openItems = list.where((item) => !item.resolved).toList();
    final unresolvedMinor = openItems.fold<int>(
      0,
      (sum, item) => sum + (item.remaining?.minorUnits.abs() ?? 0),
    );
    final oldest = openItems.isEmpty
        ? 0
        : openItems
              .map(
                (item) => now.difference(item.openedAt).inDays.clamp(0, 100000),
              )
              .reduce((a, b) => a > b ? a : b);
    return ReconciliationBreakdown(
      open: openItems.length,
      resolved: list.where((item) => item.resolved).length,
      unresolvedAmount: Money.fromMinorUnits(unresolvedMinor),
      oldestOpenDays: oldest,
    );
  }

  Map<String, ReconciliationBreakdown> groupedBreakdown(
    String? Function(ReconciliationDatum) keyOf,
  ) {
    final groups = <String, List<ReconciliationDatum>>{};
    for (final item in reconciliations) {
      final key = keyOf(item);
      if (key != null) groups.putIfAbsent(key, () => []).add(item);
    }
    return Map.unmodifiable({
      for (final entry in groups.entries)
        entry.key: reconciliationBreakdown(entry.value),
    });
  }

  final period =
      '${periodStart.toIso8601String().substring(0, 10)} → '
      '${periodEndExclusive.subtract(const Duration(days: 1)).toIso8601String().substring(0, 10)}';
  final hasUnassigned = scoped.any(
    (item) => item.responsibility == EconomicResponsibility.unassigned,
  );
  return OperationalQualitySnapshot(
    periodStart: periodStart,
    periodEndExclusive: periodEndExclusive,
    memberId: memberId,
    entries: scoped.length,
    meanDelayDays: mean,
    medianDelayDays: median,
    delays: EntryDelayDistribution(
      sameDay: delayValues.where((value) => value == 0).length,
      nextDay: delayValues.where((value) => value == 1).length,
      twoToThreeDays: delayValues
          .where((value) => value >= 2 && value <= 3)
          .length,
      fourToSevenDays: delayValues
          .where((value) => value >= 4 && value <= 7)
          .length,
      overSevenDays: delayValues.where((value) => value > 7).length,
    ),
    withinExpectedDelay: delayValues
        .where((value) => value <= expectedDelayDays)
        .length,
    uncategorized: scoped.where((item) => !item.categorized).length,
    missingEnvelope: scoped
        .where((item) => item.requiresEnvelope && !item.hasEnvelope)
        .length,
    receiptsRequired: requiredReceipts.length,
    receiptsPresent: requiredReceipts.where((item) => item.hasReceipt).length,
    openReconciliations: open.length,
    staleReconciliations: open
        .where((item) => now.difference(item.openedAt).inDays > 30)
        .length,
    resolvedReconciliations: reconciliations
        .where((item) => item.resolved)
        .length,
    unassigned: scoped
        .where(
          (item) => item.responsibility == EconomicResponsibility.unassigned,
        )
        .length,
    expectedNotMaterialized: expectedNotMaterialized,
    explanations: List.unmodifiable([
      KpiExplanation(
        id: 'punctuality',
        rule: 'Ponctualité de saisie',
        source: 'FinancialEvent : date économique et date de création',
        period: period,
        reason:
            'Une saisie est dans le délai attendu à J+${expectedDelayDays.clamp(0, 30)}.',
        completeness: 'complet',
        memberId: memberId,
      ),
      KpiExplanation(
        id: 'attribution',
        rule: 'Attribution économique explicite',
        source: 'Responsabilité métier documentée',
        period: period,
        reason:
            'L’acteur technique n’est jamais utilisé comme responsable économique.',
        completeness: hasUnassigned ? 'partiel' : 'complet',
        memberId: memberId,
        limitations: hasUnassigned
            ? const ['Des éléments restent volontairement non attribués.']
            : const [],
      ),
      KpiExplanation(
        id: 'receipts',
        rule: 'Complétude des justificatifs',
        source: 'FinancialEvent et métadonnées des justificatifs autorisés',
        period: period,
        reason:
            'Les dépenses réalisées exigent un justificatif dans la règle V1.',
        completeness: 'complet',
        memberId: memberId,
      ),
    ]),
    drillDownIds: Map.unmodifiable({
      'late': ids((item) => item.entryDelayDays > expectedDelayDays),
      'missingEnvelope': ids(
        (item) => item.requiresEnvelope && !item.hasEnvelope,
      ),
      'uncategorized': ids((item) => !item.categorized),
      'missingReceipt': ids((item) => item.requiresReceipt && !item.hasReceipt),
      'unassigned': ids(
        (item) => item.responsibility == EconomicResponsibility.unassigned,
      ),
      'openReconciliations': open
          .map((item) => item.id)
          .toList(growable: false),
    }),
    reconciliation: reconciliationBreakdown(reconciliations),
    reconciliationByAccount: groupedBreakdown((item) => item.accountId),
    reconciliationByAccountType: groupedBreakdown((item) => item.accountType),
  );
}

class CashInventoryDatum {
  const CashInventoryDatum({
    required this.id,
    required this.accountId,
    required this.observedAt,
    required this.recordedAt,
    required this.actorUserId,
    required this.denominationConsistent,
    required this.resolved,
    this.declaredHolderId,
    this.explicitResponsibleId,
    this.explicitResponsibleIds = const [],
    this.observed,
    this.theoretical,
    this.remainingDifference,
    this.resolvedAt,
  });

  final String id, accountId, actorUserId;
  final String? declaredHolderId, explicitResponsibleId;
  final List<String> explicitResponsibleIds;
  final DateTime observedAt, recordedAt;
  final DateTime? resolvedAt;
  final Money? observed, theoretical, remainingDifference;
  final bool denominationConsistent, resolved;
}

class CashQualitySnapshot {
  const CashQualitySnapshot({
    required this.periodStart,
    required this.periodEndExclusive,
    required this.inventoryCount,
    required this.lastInventoryAt,
    required this.averageFrequencyDays,
    required this.differences,
    required this.unresolvedDifferences,
    required this.regularizedDifferences,
    required this.averageResolutionDays,
    required this.localized,
    required this.unassigned,
    required this.denominationInconsistencies,
    required this.authorIsNeverResponsibleByDefault,
    required this.explanation,
    required this.drillDownIds,
    required this.unresolvedDifferenceAmount,
    required this.totalDifferenceAmount,
  });

  final DateTime periodStart, periodEndExclusive;
  final int inventoryCount, differences, unresolvedDifferences;
  final int regularizedDifferences, localized, unassigned;
  final int denominationInconsistencies;
  final DateTime? lastInventoryAt;
  final double? averageFrequencyDays, averageResolutionDays;
  final bool authorIsNeverResponsibleByDefault;
  final KpiExplanation explanation;
  final List<String> drillDownIds;
  final Money unresolvedDifferenceAmount, totalDifferenceAmount;

  double get regularizationRate =>
      differences == 0 ? 1 : regularizedDifferences / differences;
}

CashQualitySnapshot analyzeCashQuality({
  required DateTime periodStart,
  required DateTime periodEndExclusive,
  required List<CashInventoryDatum> inventories,
}) {
  final scoped =
      inventories
          .where(
            (item) =>
                !item.observedAt.isBefore(periodStart) &&
                item.observedAt.isBefore(periodEndExclusive),
          )
          .toList()
        ..sort((a, b) => a.observedAt.compareTo(b.observedAt));
  final intervals = <int>[];
  for (var index = 1; index < scoped.length; index++) {
    intervals.add(
      scoped[index].observedAt.difference(scoped[index - 1].observedAt).inDays,
    );
  }
  final withDifference = scoped
      .where(
        (item) =>
            (item.remainingDifference ??
                    (item.observed != null && item.theoretical != null
                        ? item.observed! - item.theoretical!
                        : null))
                ?.minorUnits !=
            0,
      )
      .toList(growable: false);
  final resolvedDurations = withDifference
      .where((item) => item.resolved && item.resolvedAt != null)
      .map((item) => item.resolvedAt!.difference(item.observedAt).inDays)
      .toList(growable: false);
  final period =
      '${periodStart.toIso8601String().substring(0, 10)} → '
      '${periodEndExclusive.subtract(const Duration(days: 1)).toIso8601String().substring(0, 10)}';
  return CashQualitySnapshot(
    periodStart: periodStart,
    periodEndExclusive: periodEndExclusive,
    inventoryCount: scoped.length,
    lastInventoryAt: scoped.isEmpty ? null : scoped.last.observedAt,
    averageFrequencyDays: intervals.isEmpty
        ? null
        : intervals.reduce((a, b) => a + b) / intervals.length,
    differences: withDifference.length,
    unresolvedDifferences: withDifference
        .where((item) => !item.resolved)
        .length,
    regularizedDifferences: withDifference
        .where((item) => item.resolved)
        .length,
    averageResolutionDays: resolvedDurations.isEmpty
        ? null
        : resolvedDurations.reduce((a, b) => a + b) / resolvedDurations.length,
    localized: scoped.where((item) => item.declaredHolderId != null).length,
    unassigned: scoped
        .where(
          (item) =>
              item.explicitResponsibleId == null &&
              item.explicitResponsibleIds.isEmpty,
        )
        .length,
    denominationInconsistencies: scoped
        .where((item) => !item.denominationConsistent)
        .length,
    authorIsNeverResponsibleByDefault: true,
    explanation: KpiExplanation(
      id: 'cash_inventory',
      rule: 'Qualité des inventaires espèces',
      source: 'Observations de solde et rapprochements autorisés',
      period: period,
      reason:
          'L’auteur du comptage, le détenteur déclaré et le responsable économique restent trois concepts distincts.',
      completeness:
          scoped.any(
            (item) =>
                item.explicitResponsibleId == null &&
                item.explicitResponsibleIds.isEmpty,
          )
          ? 'partiel'
          : 'complet',
      limitations: const [
        'Les montants absents du contrat de lecture ne sont ni agrégés ni estimés.',
      ],
    ),
    drillDownIds: List.unmodifiable(withDifference.map((item) => item.id)),
    unresolvedDifferenceAmount: Money.fromMinorUnits(
      withDifference
          .where((item) => !item.resolved)
          .fold(
            0,
            (sum, item) =>
                sum + (item.remainingDifference?.minorUnits.abs() ?? 0),
          ),
    ),
    totalDifferenceAmount: Money.fromMinorUnits(
      withDifference.fold(
        0,
        (sum, item) => sum + (item.remainingDifference?.minorUnits.abs() ?? 0),
      ),
    ),
  );
}

class OperationalTrendPoint {
  const OperationalTrendPoint({
    required this.periodStart,
    required this.entryDelayDays,
    required this.reconciliationResolutionRate,
    required this.unresolvedAmount,
    required this.cashFreshnessDays,
    required this.cashDifferenceAmount,
  });
  final DateTime periodStart;
  final double entryDelayDays, reconciliationResolutionRate;
  final Money unresolvedAmount, cashDifferenceAmount;
  final double? cashFreshnessDays;
}

List<OperationalTrendPoint> buildOperationalTrends({
  required DateTime endExclusive,
  required int months,
  required List<OperationalEntry> entries,
  required List<ReconciliationDatum> reconciliations,
  required List<CashInventoryDatum> inventories,
}) => List.unmodifiable([
  for (var offset = months - 1; offset >= 0; offset--)
    (() {
      final start = DateTime(
        endExclusive.year,
        endExclusive.month - offset - 1,
      );
      final end = DateTime(start.year, start.month + 1);
      final quality = analyzeOperationalQuality(
        periodStart: start,
        periodEndExclusive: end,
        entries: entries,
        reconciliations: reconciliations
            .where((item) => item.openedAt.isBefore(end))
            .toList(growable: false),
        expectedNotMaterialized: 0,
        evaluatedAt: end,
      );
      final cash = analyzeCashQuality(
        periodStart: start,
        periodEndExclusive: end,
        inventories: inventories,
      );
      return OperationalTrendPoint(
        periodStart: start,
        entryDelayDays: quality.meanDelayDays,
        reconciliationResolutionRate: quality.reconciliation.resolutionRate,
        unresolvedAmount: quality.reconciliation.unresolvedAmount,
        cashFreshnessDays: cash.lastInventoryAt == null
            ? null
            : end.difference(cash.lastInventoryAt!).inDays.toDouble(),
        cashDifferenceAmount: cash.totalDifferenceAmount,
      );
    })(),
]);
