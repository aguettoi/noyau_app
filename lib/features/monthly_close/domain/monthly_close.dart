import '../../../core/money/money.dart';

enum MonthlyCloseStatus { open, ready, closed, reopened }

enum CloseIssueSeverity { blocker, warning }

class CloseIssue {
  const CloseIssue({
    required this.code,
    required this.label,
    required this.count,
    required this.severity,
    required this.destination,
    this.contextId,
    this.accountId,
    this.financialEventId,
    this.reconciliationId,
    this.compensationId,
  });
  final String code, label, destination;
  final String? contextId,
      accountId,
      financialEventId,
      reconciliationId,
      compensationId;
  final int count;
  final CloseIssueSeverity severity;
}

class EnvelopeAccountPosition {
  const EnvelopeAccountPosition({
    required this.accountId,
    required this.envelopeId,
    required this.amount,
  });
  final String accountId, envelopeId;
  final Money amount;
}

class EnvelopeAccountMatrix {
  const EnvelopeAccountMatrix({
    required this.positions,
    required this.reliable,
    required this.accountGap,
    required this.envelopeGap,
    required this.fingerprint,
  });
  final List<EnvelopeAccountPosition> positions;
  final bool reliable;
  final Money accountGap, envelopeGap;
  final String fingerprint;
}

class EnvelopeAccountMove {
  const EnvelopeAccountMove({
    required this.fromAccountId,
    required this.toAccountId,
    required this.envelopeId,
    required this.amount,
  });
  final String fromAccountId, toAccountId, envelopeId;
  final Money amount;
}

class MonthlyCloseSnapshot {
  const MonthlyCloseSnapshot({
    required this.month,
    required this.status,
    required this.issues,
    this.kpis,
    this.periodId,
    this.owner = false,
    this.history = const [],
  });
  final DateTime month;
  final MonthlyCloseStatus status;
  final List<CloseIssue> issues;
  final ReliabilityKpis? kpis;
  final String? periodId;
  final bool owner;
  final List<MonthlyCloseAuditEntry> history;
  int get blockers => issues
      .where((e) => e.severity == CloseIssueSeverity.blocker)
      .fold(0, (a, b) => a + b.count);
  int get warnings => issues
      .where((e) => e.severity == CloseIssueSeverity.warning)
      .fold(0, (a, b) => a + b.count);
  bool get ready => blockers == 0;
  int get healthPercent {
    const categories = {
      'entries',
      'receipts',
      'reconciliations',
      'cash',
      'differences',
      'compensations',
      'reallocation',
    };
    var score = 0.0;
    for (final category in categories) {
      final matches = issues.where((e) => _healthCategory(e.code) == category);
      if (matches.isEmpty) {
        score += 1;
      } else if (matches.every(
        (e) => e.severity == CloseIssueSeverity.warning,
      )) {
        score += .5;
      }
    }
    return ((score / categories.length) * 100).round();
  }

  Map<String, int> get healthBreakdown => {
    for (final category in const {
      'entries',
      'receipts',
      'reconciliations',
      'cash',
      'differences',
      'compensations',
      'reallocation',
    })
      category: issues.any((e) => _healthCategory(e.code) == category)
          ? (issues
                    .where((e) => _healthCategory(e.code) == category)
                    .every((e) => e.severity == CloseIssueSeverity.warning)
                ? 50
                : 0)
          : 100,
  };
}

String _healthCategory(String code) => switch (code) {
  'receipts' => 'receipts',
  'reconciliations' => 'reconciliations',
  'cash' => 'cash',
  'differences' => 'differences',
  'compensations' => 'compensations',
  'matrix' || 'targets' || 'reallocation' => 'reallocation',
  _ => 'entries',
};

class MonthlyCloseAuditEntry {
  const MonthlyCloseAuditEntry({
    required this.kind,
    required this.actor,
    required this.at,
    this.reason,
  });
  final String kind, actor;
  final DateTime at;
  final String? reason;
}

class MonthlyEnvelopeAccountTarget {
  const MonthlyEnvelopeAccountTarget({
    required this.id,
    required this.envelopeId,
    required this.accountId,
    required this.amount,
    required this.createdAt,
    this.source = 'manual_override',
    this.sourceLabel,
    this.overrideReason,
  });

  final String id;
  final String envelopeId;
  final String accountId;
  final Money amount;
  final DateTime createdAt;
  final String source;
  final String? sourceLabel, overrideReason;
  bool get automatic => source == 'automatic';
}

class AutomaticTargetPreview {
  const AutomaticTargetPreview({
    required this.targets,
    required this.missingMappings,
    required this.complete,
    this.scenarioId,
    this.scenarioName,
  });
  final List<MonthlyEnvelopeAccountTarget> targets;
  final List<String> missingMappings;
  final bool complete;
  final String? scenarioId, scenarioName;
}

class ReliabilityKpis {
  const ReliabilityKpis({
    required this.totalEntries,
    required this.sameDay,
    required this.withinOneDay,
    required this.withinThreeDays,
    required this.late,
    required this.attribution,
  });
  final int totalEntries, sameDay, withinOneDay, withinThreeDays, late;
  final String attribution;
  double ratio(int value) => totalEntries == 0 ? 1 : value / totalEntries;
}

class EnvelopeAccountTarget {
  const EnvelopeAccountTarget({
    required this.memberId,
    required this.accountId,
    required this.envelopeId,
    required this.current,
    required this.target,
  });
  final String? memberId;
  final String accountId, envelopeId;
  final Money current, target;
  Money get delta => target - current;
}

class SettlementProposal {
  const SettlementProposal({
    required this.fromAccountId,
    required this.toAccountId,
    required this.amount,
    required this.explanation,
  });
  final String fromAccountId, toAccountId, explanation;
  final Money amount;
}

/// Nets deficits and surpluses deterministically. It proposes transfers only;
/// financial execution remains in the canonical account-transfer flow.
List<SettlementProposal> proposeSettlements(
  List<EnvelopeAccountTarget> targets,
) {
  final totals = <String, int>{};
  for (final target in targets) {
    totals.update(
      target.accountId,
      (v) => v + target.delta.minorUnits,
      ifAbsent: () => target.delta.minorUnits,
    );
  }
  final deficits = totals.entries
      .where((e) => e.value > 0)
      .map((e) => [e.key, e.value])
      .toList();
  final surpluses = totals.entries
      .where((e) => e.value < 0)
      .map((e) => [e.key, -e.value])
      .toList();
  final result = <SettlementProposal>[];
  var i = 0;
  var j = 0;
  while (i < surpluses.length && j < deficits.length) {
    final amount = (surpluses[i][1] as int) < (deficits[j][1] as int)
        ? surpluses[i][1] as int
        : deficits[j][1] as int;
    result.add(
      SettlementProposal(
        fromAccountId: surpluses[i][0] as String,
        toAccountId: deficits[j][0] as String,
        amount: Money.fromMinorUnits(amount),
        explanation:
            'Compte ${surpluses[i][0]} → compte ${deficits[j][0]} pour atteindre les cibles mensuelles des enveloppes.',
      ),
    );
    surpluses[i][1] = (surpluses[i][1] as int) - amount;
    deficits[j][1] = (deficits[j][1] as int) - amount;
    if (surpluses[i][1] == 0) i++;
    if (deficits[j][1] == 0) j++;
  }
  return List.unmodifiable(result);
}

/// Produces deterministic physical moves inside each envelope. No financial
/// write occurs here; confirmation is a separate server-side operation.
List<EnvelopeAccountMove> proposeEnvelopeAccountMoves(
  List<EnvelopeAccountTarget> targets,
) {
  final byEnvelope = <String, List<EnvelopeAccountTarget>>{};
  for (final target in targets) {
    byEnvelope.putIfAbsent(target.envelopeId, () => []).add(target);
  }
  final result = <EnvelopeAccountMove>[];
  for (final entry
      in byEnvelope.entries.toList()..sort((a, b) => a.key.compareTo(b.key))) {
    final rows = [...entry.value]
      ..sort((a, b) => a.accountId.compareTo(b.accountId));
    final sources = <List<Object>>[], destinations = <List<Object>>[];
    for (final row in rows) {
      final d = row.target.minorUnits - row.current.minorUnits;
      if (d < 0) sources.add([row.accountId, -d]);
      if (d > 0) destinations.add([row.accountId, d]);
    }
    var i = 0, j = 0;
    while (i < sources.length && j < destinations.length) {
      final amount = (sources[i][1] as int) < (destinations[j][1] as int)
          ? sources[i][1] as int
          : destinations[j][1] as int;
      result.add(
        EnvelopeAccountMove(
          fromAccountId: sources[i][0] as String,
          toAccountId: destinations[j][0] as String,
          envelopeId: entry.key,
          amount: Money.fromMinorUnits(amount),
        ),
      );
      sources[i][1] = (sources[i][1] as int) - amount;
      destinations[j][1] = (destinations[j][1] as int) - amount;
      if (sources[i][1] == 0) i++;
      if (destinations[j][1] == 0) j++;
    }
  }
  return List.unmodifiable(result);
}
