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
  });
  final String code, label, destination;
  final int count;
  final CloseIssueSeverity severity;
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
    final checks = issues.length;
    if (checks == 0) return 100;
    final completed = issues.where((e) => e.count == 0).length;
    return ((completed / checks) * 100).round();
  }
}

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
  });

  final String id;
  final String envelopeId;
  final String accountId;
  final Money amount;
  final DateTime createdAt;
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
