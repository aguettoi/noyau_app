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
    this.provenance = PositionProvenance.openingInventoryArbitration,
    this.provenanceReference,
  });
  final String accountId, envelopeId;
  final Money amount;
  final PositionProvenance provenance;
  final String? provenanceReference;
}

enum PositionProvenance {
  sourceProof,
  balancingDeduction,
  humanConfirmation,
  openingInventoryArbitration,
}

class OpeningPositionHistoryEntry {
  const OpeningPositionHistoryEntry({
    required this.position,
    required this.batchId,
    required this.actorId,
    required this.createdAt,
    required this.note,
  });
  final EnvelopeAccountPosition position;
  final String batchId, actorId, note;
  final DateTime createdAt;
}

class InitialPositionPreview {
  const InitialPositionPreview({
    required this.positions,
    required this.sourceFingerprint,
  });

  final List<EnvelopeAccountPosition> positions;
  final String sourceFingerprint;
}

class InventoryVentilationRule {
  const InventoryVentilationRule({
    required this.envelopeId,
    required this.admissibleAccountIds,
    this.preferredAccountIds = const [],
    required this.reason,
  });

  final String envelopeId;
  final List<String> admissibleAccountIds;
  final List<String> preferredAccountIds;
  final String reason;
}

class InventoryVentilationCandidate {
  const InventoryVentilationCandidate({
    required this.position,
    required this.reason,
    required this.mathematicallyForced,
  });

  final EnvelopeAccountPosition position;
  final String reason;
  final bool mathematicallyForced;
}

class InventoryVentilationResidual {
  const InventoryVentilationResidual({
    required this.envelopeId,
    required this.amount,
    required this.admissibleAccountIds,
    required this.remainingAccountCapacities,
    required this.reason,
    required this.expectedAction,
  });

  final String envelopeId;
  final Money amount;
  final List<String> admissibleAccountIds;
  final Map<String, Money> remainingAccountCapacities;
  final String reason;
  final String expectedAction;
}

class InventoryVentilationProposal {
  const InventoryVentilationProposal({
    required this.candidates,
    required this.remainingEnvelopeAmount,
    required this.remainingAccountCapacity,
    required this.initialResidual,
    required this.unresolvedResiduals,
  });

  final List<InventoryVentilationCandidate> candidates;
  final Money remainingEnvelopeAmount;
  final Money remainingAccountCapacity;
  final Money initialResidual;
  final List<InventoryVentilationResidual> unresolvedResiduals;

  bool get balanced =>
      remainingEnvelopeAmount.minorUnits == 0 &&
      remainingAccountCapacity.minorUnits == 0;
  bool get isUnique =>
      balanced &&
      candidates.every((candidate) => candidate.mathematicallyForced);
}

/// Builds a deterministic, read-only opening-inventory proposal. Existing
/// positions are immutable constraints. Structural recommendations only order
/// admissible edges and never become historical proof.
InventoryVentilationProposal proposeInventoryVentilation({
  required Map<String, Money> accountBalances,
  required Map<String, Money> envelopeBalances,
  required List<EnvelopeAccountPosition> fixedPositions,
  required List<InventoryVentilationRule> rules,
}) {
  final accountRemaining = <String, int>{
    for (final entry in accountBalances.entries)
      entry.key: entry.value.minorUnits,
  };
  final envelopeRemaining = <String, int>{
    for (final entry in envelopeBalances.entries)
      entry.key: entry.value.minorUnits,
  };
  for (final position in fixedPositions) {
    accountRemaining.update(
      position.accountId,
      (value) => value - position.amount.minorUnits,
      ifAbsent: () => -position.amount.minorUnits,
    );
    envelopeRemaining.update(
      position.envelopeId,
      (value) => value - position.amount.minorUnits,
      ifAbsent: () => -position.amount.minorUnits,
    );
  }
  final initialResidual = envelopeRemaining.values.fold<int>(
    0,
    (a, b) => a + b,
  );
  if (accountRemaining.values.any((value) => value < 0) ||
      envelopeRemaining.values.any((value) => value < 0)) {
    return InventoryVentilationProposal(
      candidates: const [],
      remainingEnvelopeAmount: Money.fromMinorUnits(
        envelopeRemaining.values
            .where((value) => value > 0)
            .fold(0, (a, b) => a + b),
      ),
      remainingAccountCapacity: Money.fromMinorUnits(
        accountRemaining.values
            .where((value) => value > 0)
            .fold(0, (a, b) => a + b),
      ),
      initialResidual: Money.fromMinorUnits(initialResidual),
      unresolvedResiduals: List.unmodifiable(
        envelopeRemaining.entries
            .where((entry) => entry.value > 0)
            .map(
              (entry) => InventoryVentilationResidual(
                envelopeId: entry.key,
                amount: Money.fromMinorUnits(entry.value),
                admissibleAccountIds: const [],
                remainingAccountCapacities: const {},
                reason:
                    'Les positions déjà saisies dépassent un solde de contrôle.',
                expectedAction:
                    'Corriger la saisie concernée avant de relancer la proposition.',
              ),
            ),
      ),
    );
  }

  final byEnvelope = {for (final rule in rules) rule.envelopeId: rule};
  final fixedCells = {
    for (final position in fixedPositions)
      if (position.amount.minorUnits > 0)
        (position.accountId, position.envelopeId),
  };
  final candidates = <InventoryVentilationCandidate>[];

  void allocate(String envelopeId, String accountId, int amount, bool forced) {
    if (amount <= 0) return;
    envelopeRemaining[envelopeId] = envelopeRemaining[envelopeId]! - amount;
    accountRemaining[accountId] = accountRemaining[accountId]! - amount;
    final rule = byEnvelope[envelopeId]!;
    candidates.add(
      InventoryVentilationCandidate(
        position: EnvelopeAccountPosition(
          accountId: accountId,
          envelopeId: envelopeId,
          amount: Money.fromMinorUnits(amount),
          provenance: PositionProvenance.openingInventoryArbitration,
          provenanceReference: 'Assistant R2.12 — ${rule.reason}',
        ),
        reason: forced
            ? 'Contrainte mathématique unique parmi les comptes admissibles'
            : rule.reason,
        mathematicallyForced: forced,
      ),
    );
  }

  var changed = true;
  while (changed) {
    changed = false;
    for (final envelopeId in envelopeRemaining.keys.toList()..sort()) {
      final amount = envelopeRemaining[envelopeId] ?? 0;
      final rule = byEnvelope[envelopeId];
      if (amount <= 0 || rule == null) continue;
      final available = rule.admissibleAccountIds
          .where(
            (id) =>
                (accountRemaining[id] ?? 0) > 0 &&
                !fixedCells.contains((id, envelopeId)),
          )
          .toList();
      if (available.length == 1) {
        final accountId = available.single;
        allocate(
          envelopeId,
          accountId,
          amount < accountRemaining[accountId]!
              ? amount
              : accountRemaining[accountId]!,
          true,
        );
        changed = true;
      }
    }
    for (final accountId in accountRemaining.keys.toList()..sort()) {
      final capacity = accountRemaining[accountId] ?? 0;
      if (capacity <= 0) continue;
      final available = envelopeRemaining.entries
          .where(
            (entry) =>
                entry.value > 0 &&
                (byEnvelope[entry.key]?.admissibleAccountIds.contains(
                      accountId,
                    ) ??
                    false) &&
                !fixedCells.contains((accountId, entry.key)),
          )
          .map((entry) => entry.key)
          .toList();
      if (available.length == 1) {
        final envelopeId = available.single;
        allocate(
          envelopeId,
          accountId,
          capacity < envelopeRemaining[envelopeId]!
              ? capacity
              : envelopeRemaining[envelopeId]!,
          true,
        );
        changed = true;
      }
    }
  }

  final openEnvelopes =
      envelopeRemaining.entries
          .where(
            (entry) => entry.value > 0 && byEnvelope.containsKey(entry.key),
          )
          .map((entry) => entry.key)
          .toList()
        ..sort((a, b) {
          final count = byEnvelope[a]!.admissibleAccountIds.length.compareTo(
            byEnvelope[b]!.admissibleAccountIds.length,
          );
          return count != 0 ? count : a.compareTo(b);
        });
  final source = '__source__', sink = '__sink__';
  final residual = <String, Map<String, int>>{};
  final adjacency = <String, List<String>>{};
  void edge(String from, String to, int capacity) {
    residual.putIfAbsent(from, () => {})[to] = capacity;
    residual.putIfAbsent(to, () => {})[from] = 0;
    adjacency.putIfAbsent(from, () => []).add(to);
    adjacency.putIfAbsent(to, () => []).add(from);
  }

  for (final envelopeId in openEnvelopes) {
    final envelopeNode = 'e:$envelopeId';
    edge(source, envelopeNode, envelopeRemaining[envelopeId]!);
    final rule = byEnvelope[envelopeId]!;
    final orderedAccounts = <String>[
      ...rule.preferredAccountIds,
      ...rule.admissibleAccountIds.where(
        (id) => !rule.preferredAccountIds.contains(id),
      ),
    ].where((id) => (accountRemaining[id] ?? 0) > 0).toSet().toList();
    orderedAccounts.removeWhere(
      (accountId) => fixedCells.contains((accountId, envelopeId)),
    );
    for (final accountId in orderedAccounts) {
      edge(envelopeNode, 'a:$accountId', envelopeRemaining[envelopeId]!);
    }
  }
  for (final entry in accountRemaining.entries.where(
    (entry) => entry.value > 0,
  )) {
    edge('a:${entry.key}', sink, entry.value);
  }
  while (true) {
    final parent = <String, String?>{source: null};
    final queue = <String>[source];
    for (
      var index = 0;
      index < queue.length && !parent.containsKey(sink);
      index++
    ) {
      final node = queue[index];
      for (final next in adjacency[node] ?? const <String>[]) {
        if (!parent.containsKey(next) && (residual[node]?[next] ?? 0) > 0) {
          parent[next] = node;
          queue.add(next);
        }
      }
    }
    if (!parent.containsKey(sink)) break;
    var flow = 1 << 60;
    var node = sink;
    while (parent[node] != null) {
      final previous = parent[node]!;
      flow = flow < residual[previous]![node]!
          ? flow
          : residual[previous]![node]!;
      node = previous;
    }
    node = sink;
    while (parent[node] != null) {
      final previous = parent[node]!;
      residual[previous]![node] = residual[previous]![node]! - flow;
      residual[node]![previous] = residual[node]![previous]! + flow;
      node = previous;
    }
  }
  for (final envelopeId in openEnvelopes) {
    final rule = byEnvelope[envelopeId]!;
    final envelopeNode = 'e:$envelopeId';
    for (final accountId in rule.admissibleAccountIds) {
      if (fixedCells.contains((accountId, envelopeId))) continue;
      final accountNode = 'a:$accountId';
      final amount = residual[accountNode]?[envelopeNode] ?? 0;
      if (amount > 0) allocate(envelopeId, accountId, amount, false);
    }
  }
  final unresolvedResiduals = <InventoryVentilationResidual>[];
  for (final entry in envelopeRemaining.entries.where(
    (entry) => entry.value > 0,
  )) {
    final rule = byEnvelope[entry.key];
    final admissible = List<String>.unmodifiable(
      rule?.admissibleAccountIds ?? const <String>[],
    );
    final capacities = <String, Money>{
      for (final accountId in admissible)
        accountId: Money.fromMinorUnits(
          (accountRemaining[accountId] ?? 0).clamp(0, 1 << 62),
        ),
    };
    final available = capacities.values.fold<int>(
      0,
      (sum, amount) => sum + amount.minorUnits,
    );
    final (reason, expectedAction) = rule == null || admissible.isEmpty
        ? (
            'Aucune règle structurelle ne définit de compte admissible.',
            'Configurer la règle structurelle de cette enveloppe ou saisir son inventaire manuellement.',
          )
        : available == 0
        ? (
            'Les comptes admissibles ne disposent plus de capacité résiduelle.',
            'Vérifier les positions déjà saisies ou arbitrer manuellement la localisation restante.',
          )
        : available < entry.value
        ? (
            'La capacité résiduelle des comptes admissibles est insuffisante.',
            'Vérifier les soldes de contrôle ou arbitrer la part qui ne peut pas être localisée.',
          )
        : (
            'Plusieurs ventilations restent possibles avec les contraintes disponibles.',
            'Choisir manuellement la localisation physique réelle entre les comptes admissibles.',
          );
    unresolvedResiduals.add(
      InventoryVentilationResidual(
        envelopeId: entry.key,
        amount: Money.fromMinorUnits(entry.value),
        admissibleAccountIds: admissible,
        remainingAccountCapacities: Map.unmodifiable(capacities),
        reason: reason,
        expectedAction: expectedAction,
      ),
    );
  }
  unresolvedResiduals.sort((a, b) => a.envelopeId.compareTo(b.envelopeId));
  return InventoryVentilationProposal(
    candidates: List.unmodifiable(candidates),
    remainingEnvelopeAmount: Money.fromMinorUnits(
      envelopeRemaining.values
          .where((value) => value > 0)
          .fold(0, (a, b) => a + b),
    ),
    remainingAccountCapacity: Money.fromMinorUnits(
      accountRemaining.values
          .where((value) => value > 0)
          .fold(0, (a, b) => a + b),
    ),
    initialResidual: Money.fromMinorUnits(initialResidual),
    unresolvedResiduals: List.unmodifiable(unresolvedResiduals),
  );
}

/// Completes only cells that are mathematically unique from simultaneous row
/// and column constraints. It never uses recommendations or proportions.
List<EnvelopeAccountPosition> deduceUniqueInitialPositions({
  required Map<String, Money> accountBalances,
  required Map<String, Money> envelopeBalances,
  required List<EnvelopeAccountPosition> known,
}) {
  final values = <(String, String), EnvelopeAccountPosition>{
    for (final item in known) (item.accountId, item.envelopeId): item,
  };
  var changed = true;
  while (changed) {
    changed = false;
    final accountRemaining = <String, int>{
      for (final entry in accountBalances.entries)
        entry.key:
            entry.value.minorUnits -
            values.values
                .where((item) => item.accountId == entry.key)
                .fold(0, (sum, item) => sum + item.amount.minorUnits),
    };
    final envelopeRemaining = <String, int>{
      for (final entry in envelopeBalances.entries)
        entry.key:
            entry.value.minorUnits -
            values.values
                .where((item) => item.envelopeId == entry.key)
                .fold(0, (sum, item) => sum + item.amount.minorUnits),
    };
    final openAccounts = accountRemaining.entries
        .where((entry) => entry.value > 0)
        .toList();
    final openEnvelopes = envelopeRemaining.entries
        .where((entry) => entry.value > 0)
        .toList();
    if (openAccounts.length == 1 && openEnvelopes.length == 1) {
      final account = openAccounts.single;
      final envelope = openEnvelopes.single;
      if (account.value == envelope.value &&
          !values.containsKey((account.key, envelope.key))) {
        values[(account.key, envelope.key)] = EnvelopeAccountPosition(
          accountId: account.key,
          envelopeId: envelope.key,
          amount: Money.fromMinorUnits(account.value),
          provenance: PositionProvenance.balancingDeduction,
          provenanceReference: 'Équilibrage unique des lignes et colonnes',
        );
        changed = true;
      }
    }
  }
  return List.unmodifiable(values.values);
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

enum PhysicalTransferKind { bankTransfer, cashWithdrawal, cashDeposit }

class PhysicalTransferAction {
  const PhysicalTransferAction({
    required this.fromAccountId,
    required this.toAccountId,
    required this.amount,
    required this.justifications,
  });

  final String fromAccountId, toAccountId;
  final Money amount;
  final List<EnvelopeAccountMove> justifications;
}

class GlobalTransferSimulation {
  const GlobalTransferSimulation({
    required this.analyticalMoves,
    required this.physicalTransfers,
  });

  final List<EnvelopeAccountMove> analyticalMoves;
  final List<PhysicalTransferAction> physicalTransfers;

  Money get grossAmount => Money.fromMinorUnits(
    analyticalMoves.fold(0, (sum, move) => sum + move.amount.minorUnits),
  );
  Money get netAmount => Money.fromMinorUnits(
    physicalTransfers.fold(0, (sum, move) => sum + move.amount.minorUnits),
  );
  int get avoidedPhysicalMoves =>
      analyticalMoves.length - physicalTransfers.length;
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

/// Globally nets the physical account flows while retaining the complete
/// envelope-level plan. Every physical action retains the complete analytical
/// plan because global netting may offset flows across otherwise independent
/// envelope paths.
GlobalTransferSimulation simulateGlobalTransfers(
  List<EnvelopeAccountTarget> targets,
) {
  final analytical = proposeEnvelopeAccountMoves(targets);
  if (analytical.isEmpty) {
    return const GlobalTransferSimulation(
      analyticalMoves: [],
      physicalTransfers: [],
    );
  }

  final moves = analytical;
  final physical = <PhysicalTransferAction>[];
  final net = <String, int>{};
  for (final move in moves) {
    net.update(
      move.fromAccountId,
      (value) => value - move.amount.minorUnits,
      ifAbsent: () => -move.amount.minorUnits,
    );
    net.update(
      move.toAccountId,
      (value) => value + move.amount.minorUnits,
      ifAbsent: () => move.amount.minorUnits,
    );
  }
  final sources =
      net.entries
          .where((entry) => entry.value < 0)
          .map((entry) => [entry.key, -entry.value])
          .toList()
        ..sort((a, b) => (a[0] as String).compareTo(b[0] as String));
  final destinations =
      net.entries
          .where((entry) => entry.value > 0)
          .map((entry) => [entry.key, entry.value])
          .toList()
        ..sort((a, b) => (a[0] as String).compareTo(b[0] as String));
  var sourceIndex = 0, destinationIndex = 0;
  while (sourceIndex < sources.length &&
      destinationIndex < destinations.length) {
    final amount =
        (sources[sourceIndex][1] as int) <
            (destinations[destinationIndex][1] as int)
        ? sources[sourceIndex][1] as int
        : destinations[destinationIndex][1] as int;
    physical.add(
      PhysicalTransferAction(
        fromAccountId: sources[sourceIndex][0] as String,
        toAccountId: destinations[destinationIndex][0] as String,
        amount: Money.fromMinorUnits(amount),
        justifications: List.unmodifiable(moves),
      ),
    );
    sources[sourceIndex][1] = (sources[sourceIndex][1] as int) - amount;
    destinations[destinationIndex][1] =
        (destinations[destinationIndex][1] as int) - amount;
    if (sources[sourceIndex][1] == 0) sourceIndex++;
    if (destinations[destinationIndex][1] == 0) destinationIndex++;
  }
  physical.sort((a, b) {
    final from = a.fromAccountId.compareTo(b.fromAccountId);
    return from != 0 ? from : a.toAccountId.compareTo(b.toAccountId);
  });
  return GlobalTransferSimulation(
    analyticalMoves: List.unmodifiable(analytical),
    physicalTransfers: List.unmodifiable(physical),
  );
}
