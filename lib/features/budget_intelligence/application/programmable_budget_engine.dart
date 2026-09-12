import '../domain/budget_intelligence.dart';

enum ProgrammableBudgetDiagnosticSeverity { info, warning, blocker }

enum ProgrammableBudgetStepStatus {
  executed,
  partiallyExecuted,
  skipped,
  blocked,
  inactive,
}

class ProgrammableBudgetDiagnostic {
  const ProgrammableBudgetDiagnostic({
    required this.severity,
    required this.code,
    required this.message,
    this.stepId,
    this.sourceId,
  });
  final ProgrammableBudgetDiagnosticSeverity severity;
  final String code;
  final String message;
  final String? stepId;
  final String? sourceId;
}

class ProgrammableBudgetMemberCapacity {
  const ProgrammableBudgetMemberCapacity({
    required this.memberUserId,
    required this.resourcesCents,
    required this.directChargesCents,
    required this.rawCapacityCents,
    required this.contributionCapacityCents,
    required this.autoShare,
  });
  final String memberUserId;
  final int resourcesCents;
  final int directChargesCents;
  final int rawCapacityCents;
  final int contributionCapacityCents;
  final double autoShare;
}

class ProgrammableBudgetMemberSummary {
  const ProgrammableBudgetMemberSummary({
    required this.memberUserId,
    required this.initialResourcesCents,
    required this.allocatedCents,
    required this.remainingCents,
  });
  final String memberUserId;
  final int initialResourcesCents;
  final int allocatedCents;
  final int remainingCents;
}

class BudgetAllocationStepAllocation {
  const BudgetAllocationStepAllocation({
    required this.stepId,
    required this.envelopeId,
    required this.allocatedCents,
    this.memberContributions = const {},
  });
  final String stepId;
  final String envelopeId;
  final int allocatedCents;
  final Map<String, int> memberContributions;
}

class ProgrammableBudgetStepResult {
  const ProgrammableBudgetStepResult({
    required this.step,
    required this.requestedCents,
    required this.allocatedCents,
    required this.availableBeforeCents,
    required this.remainingAfterCents,
    required this.status,
    required this.diagnostics,
    required this.memberContributions,
    this.percentageBaseCents,
    this.reductionCoefficient,
  });
  final BudgetAllocationStep step;
  final int requestedCents;
  final int allocatedCents;
  final int availableBeforeCents;
  final int remainingAfterCents;
  final ProgrammableBudgetStepStatus status;
  final List<ProgrammableBudgetDiagnostic> diagnostics;
  final Map<String, int> memberContributions;
  final int? percentageBaseCents;
  final double? reductionCoefficient;
}

class ProgrammableBudgetResult {
  const ProgrammableBudgetResult({
    required this.allocations,
    required this.remainingCents,
    required this.warnings,
    required this.initialResourcesCents,
    this.memberCapacities = const [],
    this.memberRemainingCents = const {},
    this.memberSummaries = const [],
    this.stepResults = const [],
    this.diagnostics = const [],
  });
  final List<BudgetAllocationStepAllocation> allocations;
  final int remainingCents;
  final List<String> warnings;
  final int initialResourcesCents;
  final List<ProgrammableBudgetMemberCapacity> memberCapacities;
  final Map<String, int> memberRemainingCents;
  final List<ProgrammableBudgetMemberSummary> memberSummaries;
  final List<ProgrammableBudgetStepResult> stepResults;
  final List<ProgrammableBudgetDiagnostic> diagnostics;
  int get householdContributionCapacityCents => memberCapacities.fold<int>(
    0,
    (sum, item) => sum + item.contributionCapacityCents,
  );
  bool get hasAutomaticContributionCapacity =>
      householdContributionCapacityCents > 0;
  bool get isSimulable => diagnostics.every(
    (item) => item.severity != ProgrammableBudgetDiagnosticSeverity.blocker,
  );
  int get allocatedCents =>
      allocations.fold<int>(0, (sum, item) => sum + item.allocatedCents);
  int count(ProgrammableBudgetStepStatus status) =>
      stepResults.where((item) => item.status == status).length;
  int diagnosticsCount(ProgrammableBudgetDiagnosticSeverity severity) =>
      diagnostics.where((item) => item.severity == severity).length;
}

/// Deterministic template interpreter. It never writes accounting data.
class ProgrammableBudgetEngine {
  const ProgrammableBudgetEngine();

  ProgrammableBudgetResult simulate({
    required List<BudgetSource> sources,
    required List<BudgetAllocationStep> steps,
    List<String> memberIds = const [],
  }) {
    final initialResources = sources
        .where((item) => item.active)
        .fold<int>(0, (sum, item) => sum + item.expectedCents);
    final memberResources = <String, int>{for (final id in memberIds) id: 0};
    var unassignedResources = 0;
    for (final source in sources.where((source) => source.active)) {
      final memberId = source.memberUserId;
      if (memberId == null) {
        unassignedResources += source.expectedCents;
      } else {
        memberResources[memberId] =
            (memberResources[memberId] ?? 0) + source.expectedCents;
      }
    }
    final initialMemberResources = Map<String, int>.from(memberResources);
    final allDiagnostics = <ProgrammableBudgetDiagnostic>[];
    final results = <ProgrammableBudgetStepResult>[];
    final sourceById = {for (final source in sources) source.id: source};
    final ordered = [...steps]..sort((a, b) => a.order.compareTo(b.order));
    List<ProgrammableBudgetMemberCapacity>? contributionSnapshot;

    for (final step in ordered) {
      final personal =
          step.contributionKey == ContributionKeyStrategy.singleMember;
      final before = personal && step.memberUserId != null
          ? memberResources[step.memberUserId] ?? 0
          : memberResources.values.fold<int>(
                  0,
                  (sum, value) => sum + (value > 0 ? value : 0),
                ) +
                unassignedResources;
      final diagnostics = <ProgrammableBudgetDiagnostic>[];
      if (!step.active) {
        diagnostics.add(
          _diagnostic(
            ProgrammableBudgetDiagnosticSeverity.info,
            'step_inactive',
            'Cette étape est inactive.',
            step,
          ),
        );
        results.add(
          _stepResult(
            step,
            0,
            0,
            before,
            before,
            ProgrammableBudgetStepStatus.inactive,
            diagnostics,
            const {},
          ),
        );
        allDiagnostics.addAll(diagnostics);
        continue;
      }
      final requested = _requested(step, before);
      final source = sourceById[step.sourceId];
      // `source_id` is a relational anchor for every persisted step. For a
      // common step it is not an economic source: funding is entirely
      // determined by the contribution key and member capacities.
      if (personal && (source == null || !source.active)) {
        diagnostics.add(
          _diagnostic(
            ProgrammableBudgetDiagnosticSeverity.blocker,
            source == null ? 'source_missing' : 'source_inactive',
            source == null
                ? 'La source requise par cette étape est introuvable.'
                : 'La source requise par cette étape est inactive.',
            step,
          ),
        );
      }
      if (step.envelopeId.trim().isEmpty) {
        diagnostics.add(
          _diagnostic(
            ProgrammableBudgetDiagnosticSeverity.blocker,
            'destination_missing',
            'Cette étape obligatoire ne possède pas de destination.',
            step,
          ),
        );
      }
      diagnostics.addAll(_configurationDiagnostics(step));
      if (diagnostics.any(
        (item) => item.severity == ProgrammableBudgetDiagnosticSeverity.blocker,
      )) {
        results.add(
          _stepResult(
            step,
            requested,
            0,
            before,
            before,
            ProgrammableBudgetStepStatus.blocked,
            diagnostics,
            const {},
          ),
        );
        allDiagnostics.addAll(diagnostics);
        continue;
      }
      if (!personal && contributionSnapshot == null) {
        contributionSnapshot = _memberCapacities(
          initialMemberResources,
          memberResources,
        );
      }
      final capacities = _memberCapacities(
        initialMemberResources,
        memberResources,
      );
      var contributions = _contributions(step, requested, capacities);
      if (!personal &&
          step.contributionKey ==
              ContributionKeyStrategy.automaticRemainingCapacity &&
          contributions.isEmpty &&
          memberResources.isNotEmpty &&
          // With proportional reduction, an empty capacity is a valid
          // financial outcome: the step simply allocates zero. It is not a
          // configuration failure and must not make the simulation invalid.
          !(step.insufficientFundsPolicy ==
                  BudgetInsufficientFundsPolicy.proportional &&
              before <= 0)) {
        diagnostics.add(
          _diagnostic(
            ProgrammableBudgetDiagnosticSeverity.blocker,
            'automatic_key_unavailable',
            'Impossible de calculer une clé automatique : aucune capacité contributive positive.',
            step,
          ),
        );
      }
      final supportedAmount = _supportedAmount(
        step,
        requested,
        before,
        capacities,
        memberResources,
      );
      final fundsEnough = requested <= before && supportedAmount >= requested;
      // A direct personal obligation records the member's real capacity even
      // when it exceeds the income available for the period. The resulting
      // deficit is intentionally excluded from subsequent automatic keys.
      var enough =
          personal &&
              step.insufficientFundsPolicy ==
                  BudgetInsufficientFundsPolicy.strict
          ? true
          : fundsEnough;
      if (diagnostics.any(
        (item) => item.severity == ProgrammableBudgetDiagnosticSeverity.blocker,
      )) {
        enough = false;
      }
      var allocated =
          diagnostics.any(
            (item) =>
                item.severity == ProgrammableBudgetDiagnosticSeverity.blocker,
          )
          ? 0
          : switch (step.insufficientFundsPolicy) {
              BudgetInsufficientFundsPolicy.strict => enough ? requested : 0,
              BudgetInsufficientFundsPolicy.cap => supportedAmount,
              BudgetInsufficientFundsPolicy.skip => enough ? requested : 0,
              BudgetInsufficientFundsPolicy.proportional => supportedAmount,
            };
      if (allocated != requested && contributions.isNotEmpty) {
        contributions = _contributions(step, allocated, capacities);
      }
      if (!enough) {
        diagnostics.add(_insufficientDiagnostic(step, requested, before));
      }
      if (contributions.isEmpty) {
        unassignedResources -= allocated;
      } else {
        for (final entry in contributions.entries) {
          memberResources[entry.key] =
              (memberResources[entry.key] ?? 0) - entry.value;
        }
      }
      final after =
          memberResources.values.fold<int>(0, (sum, value) => sum + value) +
          unassignedResources;
      results.add(
        _stepResult(
          step,
          requested,
          allocated,
          before,
          after,
          _status(step, enough, allocated),
          diagnostics,
          contributions,
        ),
      );
      allDiagnostics.addAll(diagnostics);
    }
    final finalCapacities = _memberCapacities(
      initialMemberResources,
      memberResources,
    );
    final capacities = contributionSnapshot ?? finalCapacities;
    for (final _ in capacities.where((item) => item.rawCapacityCents < 0)) {
      allDiagnostics.add(
        ProgrammableBudgetDiagnostic(
          severity: ProgrammableBudgetDiagnosticSeverity.warning,
          code: 'personal_deficit',
          message: 'Un déficit personnel a été détecté.',
        ),
      );
    }
    for (final source in sources.where(
      (source) =>
          source.active && !steps.any((step) => step.sourceId == source.id),
    )) {
      allDiagnostics.add(
        ProgrammableBudgetDiagnostic(
          severity: ProgrammableBudgetDiagnosticSeverity.info,
          code: 'source_unused',
          message: 'Une source active n’est utilisée par aucune étape.',
          sourceId: source.id,
        ),
      );
    }
    final allocations = results
        .where((item) => item.step.active)
        .map(
          (item) => BudgetAllocationStepAllocation(
            stepId: item.step.id,
            envelopeId: item.step.envelopeId,
            allocatedCents: item.allocatedCents,
            memberContributions: item.memberContributions,
          ),
        )
        .toList(growable: false);
    final memberSummaries = initialMemberResources.entries
        .map((entry) {
          final remaining = memberResources[entry.key] ?? 0;
          return ProgrammableBudgetMemberSummary(
            memberUserId: entry.key,
            initialResourcesCents: entry.value,
            allocatedCents: entry.value - remaining,
            remainingCents: remaining,
          );
        })
        .toList(growable: false);
    return ProgrammableBudgetResult(
      allocations: List.unmodifiable(allocations),
      remainingCents:
          memberResources.values.fold<int>(0, (sum, value) => sum + value) +
          unassignedResources,
      warnings: List.unmodifiable(
        allDiagnostics
            .where(
              (item) =>
                  item.severity == ProgrammableBudgetDiagnosticSeverity.warning,
            )
            .map((item) => item.message),
      ),
      initialResourcesCents: initialResources,
      memberCapacities: List.unmodifiable(capacities),
      memberRemainingCents: Map.unmodifiable(memberResources),
      memberSummaries: List.unmodifiable(memberSummaries),
      stepResults: List.unmodifiable(results),
      diagnostics: List.unmodifiable(allDiagnostics),
    );
  }

  int _requested(BudgetAllocationStep step, int available) =>
      switch (step.method) {
        BudgetAllocationMethod.fixed => step.amountCents ?? 0,
        BudgetAllocationMethod.percentage =>
          (available * (step.percentage ?? 0) / 100).round(),
        BudgetAllocationMethod.residual => available > 0 ? available : 0,
        _ => 0,
      };

  ProgrammableBudgetStepResult _stepResult(
    BudgetAllocationStep step,
    int requested,
    int allocated,
    int before,
    int after,
    ProgrammableBudgetStepStatus status,
    List<ProgrammableBudgetDiagnostic> diagnostics,
    Map<String, int> contributions,
  ) => ProgrammableBudgetStepResult(
    step: step,
    requestedCents: requested,
    allocatedCents: allocated,
    availableBeforeCents: before,
    remainingAfterCents: after,
    status: status,
    diagnostics: List.unmodifiable(diagnostics),
    memberContributions: Map.unmodifiable(contributions),
    percentageBaseCents: step.method == BudgetAllocationMethod.percentage
        ? before
        : null,
    reductionCoefficient: requested == 0 ? null : allocated / requested,
  );

  ProgrammableBudgetStepStatus _status(
    BudgetAllocationStep step,
    bool enough,
    int allocated,
  ) {
    if (enough) return ProgrammableBudgetStepStatus.executed;
    return switch (step.insufficientFundsPolicy) {
      BudgetInsufficientFundsPolicy.strict =>
        ProgrammableBudgetStepStatus.blocked,
      BudgetInsufficientFundsPolicy.skip =>
        ProgrammableBudgetStepStatus.skipped,
      BudgetInsufficientFundsPolicy.cap ||
      BudgetInsufficientFundsPolicy.proportional =>
        allocated == 0
            ? ProgrammableBudgetStepStatus.skipped
            : ProgrammableBudgetStepStatus.partiallyExecuted,
    };
  }

  ProgrammableBudgetDiagnostic _insufficientDiagnostic(
    BudgetAllocationStep step,
    int requested,
    int available,
  ) => switch (step.insufficientFundsPolicy) {
    BudgetInsufficientFundsPolicy.strict => _diagnostic(
      ProgrammableBudgetDiagnosticSeverity.blocker,
      'strict_insufficient_funds',
      'Cette étape exige ${(requested / 100).toStringAsFixed(2)} MAD mais seulement ${(available / 100).toStringAsFixed(2)} MAD sont disponibles.',
      step,
    ),
    BudgetInsufficientFundsPolicy.cap => _diagnostic(
      ProgrammableBudgetDiagnosticSeverity.warning,
      'allocation_capped',
      'Allocation plafonnée aux ressources disponibles.',
      step,
    ),
    BudgetInsufficientFundsPolicy.skip => _diagnostic(
      ProgrammableBudgetDiagnosticSeverity.info,
      'allocation_skipped',
      'Étape ignorée faute de ressources suffisantes.',
      step,
    ),
    BudgetInsufficientFundsPolicy.proportional => _diagnostic(
      ProgrammableBudgetDiagnosticSeverity.warning,
      'allocation_reduced',
      'Allocation réduite proportionnellement aux ressources disponibles.',
      step,
    ),
  };

  List<ProgrammableBudgetDiagnostic> _configurationDiagnostics(
    BudgetAllocationStep step,
  ) {
    final result = <ProgrammableBudgetDiagnostic>[];
    final invalidFixed =
        step.method == BudgetAllocationMethod.fixed &&
        (step.amountCents == null || step.amountCents! < 0);
    final invalidPercentage =
        step.method == BudgetAllocationMethod.percentage &&
        (step.percentage == null || step.percentage! < 0);
    if (invalidFixed || invalidPercentage) {
      result.add(
        _diagnostic(
          ProgrammableBudgetDiagnosticSeverity.blocker,
          'method_configuration_incomplete',
          'La configuration de calcul de cette étape est incomplète ou invalide.',
          step,
        ),
      );
    }
    if (step.contributionKey == ContributionKeyStrategy.customPercentage) {
      final total = step.keyDefinition.values.fold<double>(
        0,
        (sum, value) => sum + _numericValue(value),
      );
      if (step.keyDefinition.isEmpty || (total - 100).abs() >= .000001) {
        result.add(
          _diagnostic(
            ProgrammableBudgetDiagnosticSeverity.blocker,
            'custom_key_invalid',
            'La clé personnalisée doit totaliser 100 %.',
            step,
          ),
        );
      }
    }
    if (step.contributionKey == ContributionKeyStrategy.singleMember &&
        step.memberUserId == null) {
      result.add(
        _diagnostic(
          ProgrammableBudgetDiagnosticSeverity.blocker,
          'member_missing',
          'Cette étape doit désigner un membre.',
          step,
        ),
      );
    }
    if (step.contributionKey == ContributionKeyStrategy.fixedByMember) {
      final total = step.keyDefinition.values.fold<int>(
        0,
        (sum, value) => sum + (value is num ? value.toInt() : 0),
      );
      if (total != (step.amountCents ?? 0)) {
        result.add(
          _diagnostic(
            ProgrammableBudgetDiagnosticSeverity.blocker,
            'fixed_member_key_invalid',
            'Les montants par membre doivent égaler le montant de l’étape.',
            step,
          ),
        );
      }
    }
    return result;
  }

  static double _numericValue(Object? value) => switch (value) {
    num numeric => numeric.toDouble(),
    String text => double.tryParse(text.trim().replaceAll(',', '.')) ?? 0,
    _ => 0,
  };

  ProgrammableBudgetDiagnostic _diagnostic(
    ProgrammableBudgetDiagnosticSeverity severity,
    String code,
    String message,
    BudgetAllocationStep step,
  ) => ProgrammableBudgetDiagnostic(
    severity: severity,
    code: code,
    message: message,
    stepId: step.id,
    sourceId: step.sourceId,
  );

  List<ProgrammableBudgetMemberCapacity> _memberCapacities(
    Map<String, int> resources,
    Map<String, int> remaining,
  ) {
    final ids = <String>{...resources.keys, ...remaining.keys};
    final values = <String, int>{for (final id in ids) id: remaining[id] ?? 0};
    final total = values.values.fold<int>(
      0,
      (sum, value) => sum + (value > 0 ? value : 0),
    );
    return ids
        .map((id) {
          final rawValue = values[id] ?? 0;
          final usable = rawValue > 0 ? rawValue : 0;
          return ProgrammableBudgetMemberCapacity(
            memberUserId: id,
            resourcesCents: resources[id] ?? 0,
            directChargesCents: (resources[id] ?? 0) - rawValue,
            rawCapacityCents: rawValue,
            contributionCapacityCents: usable,
            autoShare: total == 0 ? 0 : usable / total,
          );
        })
        .toList(growable: false);
  }

  Map<String, int> _contributions(
    BudgetAllocationStep step,
    int amount,
    List<ProgrammableBudgetMemberCapacity> capacities,
  ) {
    if (step.contributionKey == ContributionKeyStrategy.singleMember &&
        step.memberUserId != null) {
      return {step.memberUserId!: amount};
    }
    if (step.contributionKey == ContributionKeyStrategy.fixedByMember) {
      final configured = step.keyDefinition.map(
        (id, value) => MapEntry(id, value is num ? value.toInt() : 0),
      );
      final total = configured.values.fold<int>(0, (sum, value) => sum + value);
      if (total == amount) return Map.unmodifiable(configured);
      return _allocateByWeights(<String, int>{
        for (final entry in configured.entries) entry.key: entry.value,
      }, amount);
    }
    final ids = capacities.map((item) => item.memberUserId).toList();
    final Map<String, int> weights = switch (step.contributionKey) {
      ContributionKeyStrategy.automaticRemainingCapacity => {
        for (final item in capacities.where(
          (item) => item.contributionCapacityCents > 0,
        ))
          item.memberUserId: item.contributionCapacityCents,
      },
      ContributionKeyStrategy.equal => {for (final id in ids) id: 1},
      ContributionKeyStrategy.customPercentage => step.keyDefinition.map(
        (id, value) => MapEntry(id, _weightUnits(value)),
      ),
      _ => const <String, int>{},
    };
    return _allocateByWeights(weights, amount);
  }

  /// Splits a centime amount without creating or losing a centime.  The
  /// largest-remainder method keeps the result deterministic; equal remainders
  /// are resolved by the stable member identifier.
  Map<String, int> _allocateByWeights(Map<String, int> weights, int amount) {
    final activeEntries = weights.entries
        .where((entry) => entry.value > 0)
        .toList(growable: false);
    final totalWeight = activeEntries.fold<int>(
      0,
      (sum, entry) => sum + entry.value,
    );
    if (amount <= 0 || totalWeight <= 0) {
      return Map.unmodifiable({
        for (final entry in activeEntries) entry.key: 0,
      });
    }
    final result = <String, int>{};
    final remainders = <({String id, int remainder})>[];
    var assigned = 0;
    for (final entry in activeEntries) {
      final numerator = amount * entry.value;
      final share = numerator ~/ totalWeight;
      result[entry.key] = share;
      assigned += share;
      remainders.add((id: entry.key, remainder: numerator % totalWeight));
    }
    remainders.sort((left, right) {
      final remainderOrder = right.remainder.compareTo(left.remainder);
      return remainderOrder != 0 ? remainderOrder : left.id.compareTo(right.id);
    });
    for (var index = 0; index < amount - assigned; index++) {
      final id = remainders[index % remainders.length].id;
      result[id] = (result[id] ?? 0) + 1;
    }
    return Map.unmodifiable(result);
  }

  static int _weightUnits(Object? value) {
    final text = value?.toString().trim().replaceAll(',', '.') ?? '';
    final match = RegExp(r'^(\d+)(?:\.(\d+))?$').firstMatch(text);
    if (match == null) return 0;
    final whole = int.tryParse(match.group(1)!) ?? 0;
    final fractional = (match.group(2) ?? '').padRight(6, '0');
    return whole * 1000000 + (int.tryParse(fractional.substring(0, 6)) ?? 0);
  }

  int _supportedAmount(
    BudgetAllocationStep step,
    int requested,
    int available,
    List<ProgrammableBudgetMemberCapacity> capacities,
    Map<String, int> memberResources,
  ) {
    if (requested <= 0) return 0;
    final maximum = available.clamp(0, requested);
    bool canFund(int amount) {
      final contributions = _contributions(step, amount, capacities);
      if (contributions.isEmpty) return amount <= maximum;
      return contributions.entries.every(
        (entry) =>
            entry.value <= (memberResources[entry.key] ?? 0).clamp(0, amount),
      );
    }

    if (canFund(maximum)) return maximum;
    var low = 0;
    var high = maximum + 1;
    while (low + 1 < high) {
      final candidate = low + (high - low) ~/ 2;
      if (canFund(candidate)) {
        low = candidate;
      } else {
        high = candidate;
      }
    }
    return low;
  }
}
