import '../../../core/money/money.dart';

enum RecurringEconomicType { income, expense, accountTransfer }

enum RecurringFrequency { weekly, monthly, yearly }

enum RecurringCertainty { certain, estimated }

enum RecurringStatus { active, suspended, stopped }

enum ExpectedOccurrenceStatus {
  expected,
  partiallyRealized,
  realized,
  ignored,
  overdue,
}

enum MatchDecision { proposed, confirmed, rejected }

class MatchingTolerance {
  const MatchingTolerance({
    this.dateDays = 3,
    this.amount = const Money.fromMinorUnits(1000),
    this.amountPercent = 1,
    this.descriptionSimilarity = .55,
  });
  final int dateDays;
  final Money amount;
  final double amountPercent;
  final double descriptionSimilarity;
}

class RecurringFinancialIntention {
  const RecurringFinancialIntention({
    required this.id,
    required this.householdId,
    required this.type,
    required this.label,
    required this.amount,
    required this.currency,
    required this.frequency,
    required this.startsOn,
    required this.nextOccurrenceOn,
    required this.certainty,
    required this.status,
    this.endsOn,
    this.memberId,
    this.sourceAccountId,
    this.destinationAccountId,
    this.envelopeId,
    this.sourceKind = 'manual',
  });
  final String id, householdId, label, currency, sourceKind;
  final RecurringEconomicType type;
  final Money amount;
  final RecurringFrequency frequency;
  final DateTime startsOn, nextOccurrenceOn;
  final DateTime? endsOn;
  final String? memberId, sourceAccountId, destinationAccountId, envelopeId;
  final RecurringCertainty certainty;
  final RecurringStatus status;
}

class ExpectedFinancialOccurrence {
  const ExpectedFinancialOccurrence({
    required this.id,
    required this.intentionId,
    required this.expectedOn,
    required this.type,
    required this.label,
    required this.expectedAmount,
    required this.confirmedAmount,
    required this.status,
    this.sourceAccountId,
    this.destinationAccountId,
    this.envelopeId,
    this.memberId,
  });
  final String id, intentionId, label;
  final DateTime expectedOn;
  final RecurringEconomicType type;
  final Money expectedAmount, confirmedAmount;
  final ExpectedOccurrenceStatus status;
  final String? sourceAccountId, destinationAccountId, envelopeId, memberId;
  Money get remaining => Money.fromMinorUnits(
    (expectedAmount.minorUnits - confirmedAmount.minorUnits).clamp(
      0,
      expectedAmount.minorUnits,
    ),
  );
}

class ActualFinancialCandidate {
  const ActualFinancialCandidate({
    required this.id,
    required this.type,
    required this.occurredAt,
    required this.amount,
    required this.description,
    this.accountId,
    this.destinationAccountId,
    this.envelopeId,
    this.memberId,
    this.counterparty,
  });
  final String id, description;
  final RecurringEconomicType type;
  final DateTime occurredAt;
  final Money amount;
  final String? accountId,
      destinationAccountId,
      envelopeId,
      memberId,
      counterparty;
}

class RecurringPatternSuggestion {
  const RecurringPatternSuggestion({
    required this.key,
    required this.label,
    required this.type,
    required this.frequency,
    required this.typicalAmount,
    required this.nextExpectedOn,
    required this.evidenceCount,
    required this.reasons,
    this.accountId,
    this.envelopeId,
    this.memberId,
  });
  final String key, label;
  final RecurringEconomicType type;
  final RecurringFrequency frequency;
  final Money typicalAmount;
  final DateTime nextExpectedOn;
  final int evidenceCount;
  final List<String> reasons;
  final String? accountId, envelopeId, memberId;
}

/// Detects only stable, explainable patterns. It never persists an intention:
/// a human must confirm the suggestion through the canonical R3.1 form.
List<RecurringPatternSuggestion> detectRecurringPatterns(
  Iterable<ActualFinancialCandidate> candidates,
) {
  String normalized(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-zà-ÿ0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final groups = <String, List<ActualFinancialCandidate>>{};
  for (final item in candidates) {
    final label = normalized(item.counterparty ?? item.description);
    if (label.isEmpty) continue;
    final key =
        '${item.type.name}|$label|${item.accountId ?? ''}|${item.envelopeId ?? ''}|${item.memberId ?? ''}';
    groups.putIfAbsent(key, () => []).add(item);
  }
  final result = <RecurringPatternSuggestion>[];
  for (final entry in groups.entries) {
    final items = [...entry.value]
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    if (items.length < 3) continue;
    final intervals = <int>[
      for (var i = 1; i < items.length; i++)
        items[i].occurredAt.difference(items[i - 1].occurredAt).inDays.abs(),
    ];
    final averageDays = intervals.reduce((a, b) => a + b) / intervals.length;
    final frequency = averageDays >= 330 && averageDays <= 400
        ? RecurringFrequency.yearly
        : averageDays >= 25 && averageDays <= 35
        ? RecurringFrequency.monthly
        : averageDays >= 6 && averageDays <= 8
        ? RecurringFrequency.weekly
        : null;
    if (frequency == null) continue;
    final amounts = items.map((e) => e.amount.minorUnits).toList()..sort();
    final median = amounts[amounts.length ~/ 2];
    final tolerance = (median.abs() * .10).round().clamp(1, 5000);
    if (amounts.any((amount) => (amount - median).abs() > tolerance)) continue;
    final last = items.last;
    result.add(
      RecurringPatternSuggestion(
        key: entry.key,
        label: last.counterparty?.trim().isNotEmpty == true
            ? last.counterparty!
            : last.description,
        type: last.type,
        frequency: frequency,
        typicalAmount: Money.fromMinorUnits(median),
        nextExpectedOn: nextRecurringDate(
          last.occurredAt,
          frequency,
          anchorDay: items.first.occurredAt.day,
        ),
        evidenceCount: items.length,
        reasons: List.unmodifiable([
          '${items.length} opérations comparables',
          'Cadence ${frequency.name} stable',
          'Montants dans une tolérance déterministe de 10 %',
        ]),
        accountId: last.accountId,
        envelopeId: last.envelopeId,
        memberId: last.memberId,
      ),
    );
  }
  result.sort((a, b) => a.nextExpectedOn.compareTo(b.nextExpectedOn));
  return List.unmodifiable(result);
}

class MatchAssessment {
  const MatchAssessment({
    required this.score,
    required this.reasons,
    required this.exact,
    required this.eligible,
  });
  final double score;
  final List<String> reasons;
  final bool exact, eligible;
}

MatchAssessment assessExpectedMatch(
  ExpectedFinancialOccurrence expected,
  ActualFinancialCandidate actual,
  MatchingTolerance tolerance,
) {
  if (expected.type != actual.type) {
    return const MatchAssessment(
      score: 0,
      reasons: ['Type économique incompatible'],
      exact: false,
      eligible: false,
    );
  }
  final reasons = <String>[];
  final days =
      (DateTime(
                expected.expectedOn.year,
                expected.expectedOn.month,
                expected.expectedOn.day,
              )
              .difference(
                DateTime(
                  actual.occurredAt.year,
                  actual.occurredAt.month,
                  actual.occurredAt.day,
                ),
              )
              .inDays)
          .abs();
  if (days > tolerance.dateDays) {
    return MatchAssessment(
      score: 0,
      reasons: ['Date hors tolérance ($days jours)'],
      exact: false,
      eligible: false,
    );
  }
  final remaining = expected.remaining.minorUnits;
  final amountDiff = (remaining - actual.amount.minorUnits).abs();
  final allowed = (tolerance.amount.minorUnits).clamp(
    0,
    (remaining * tolerance.amountPercent / 100).round().clamp(
      tolerance.amount.minorUnits,
      1 << 62,
    ),
  );
  if (actual.amount.minorUnits > remaining + allowed) {
    return MatchAssessment(
      score: 0,
      reasons: ['Montant supérieur au reliquat'],
      exact: false,
      eligible: false,
    );
  }
  var score = .35;
  if (days == 0) {
    score += .2;
    reasons.add('Même date');
  } else {
    score += .2 * (1 - days / (tolerance.dateDays + 1));
    reasons.add('Date proche');
  }
  if (amountDiff <= allowed) {
    score += .25;
    reasons.add(amountDiff == 0 ? 'Même montant' : 'Montant dans la tolérance');
  } else if (actual.amount.minorUnits < remaining) {
    score += .12;
    reasons.add('Paiement partiel possible');
  } else {
    return MatchAssessment(
      score: score,
      reasons: ['Montant hors tolérance'],
      exact: false,
      eligible: false,
    );
  }
  bool compatible(String? expectedId, String? actualId, String label) {
    if (expectedId == null) return true;
    if (actualId == expectedId) {
      score += .1;
      reasons.add('$label confirmé');
      return true;
    }
    reasons.add('$label différent');
    return false;
  }

  final accountOk = compatible(
    expected.sourceAccountId,
    actual.accountId,
    'Compte',
  );
  final destinationOk = compatible(
    expected.destinationAccountId,
    actual.destinationAccountId,
    'Destination',
  );
  final envelopeOk = compatible(
    expected.envelopeId,
    actual.envelopeId,
    'Enveloppe',
  );
  final memberOk = compatible(expected.memberId, actual.memberId, 'Membre');
  final similarity = _tokenSimilarity(expected.label, actual.description);
  if (similarity >= tolerance.descriptionSimilarity) {
    score += .1;
    reasons.add('Libellé proche');
  }
  final exact =
      days == 0 &&
      amountDiff == 0 &&
      accountOk &&
      destinationOk &&
      envelopeOk &&
      memberOk &&
      similarity >= tolerance.descriptionSimilarity;
  return MatchAssessment(
    score: score.clamp(0, 1),
    reasons: List.unmodifiable(reasons),
    exact: exact,
    eligible:
        accountOk && destinationOk && envelopeOk && memberOk && score >= .55,
  );
}

double _tokenSimilarity(String a, String b) {
  Set<String> tokens(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-zà-ÿ0-9 ]'), ' ')
      .split(RegExp(r'\s+'))
      .where((e) => e.length > 1)
      .toSet();
  final aa = tokens(a), bb = tokens(b);
  if (aa.isEmpty || bb.isEmpty) return 0;
  return aa.intersection(bb).length / aa.union(bb).length;
}

DateTime nextRecurringDate(
  DateTime date,
  RecurringFrequency frequency, {
  int? anchorDay,
}) {
  if (frequency == RecurringFrequency.weekly) {
    return DateTime(date.year, date.month, date.day + 7);
  }
  final month = frequency == RecurringFrequency.monthly
      ? date.month + 1
      : date.month;
  final year = frequency == RecurringFrequency.yearly
      ? date.year + 1
      : date.year;
  final base = DateTime(year, month, 1);
  final nextMonth = DateTime(base.year, base.month + 1, 1);
  final lastDay = nextMonth.subtract(const Duration(days: 1)).day;
  return DateTime(
    base.year,
    base.month,
    (anchorDay ?? date.day).clamp(1, lastDay),
  );
}
