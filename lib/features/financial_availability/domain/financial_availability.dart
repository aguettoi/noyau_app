import '../../../core/money/money.dart';

/// Pure read model. It never writes a ledger, a FinancialEvent, or a budget.
class FinancialAvailabilityInput {
  const FinancialAvailabilityInput({
    required this.liquidity,
    required this.envelopes,
    required this.debtCommitments,
    this.commitments = const [],
    required this.potentialReceivables,
    required this.goals,
    required this.plans,
  });
  final Money liquidity;
  final List<AvailabilityEnvelope> envelopes;
  final Money debtCommitments;

  /// Open obligations with a reliable due date. They reduce the simulated
  /// capacity of their own month only; undated obligations remain explicit
  /// cautions rather than invented monthly deductions.
  final List<AvailabilityCommitment> commitments;
  final Money potentialReceivables;
  final List<AvailabilityGoal> goals;
  final List<AvailabilityPlan> plans;
}

class AvailabilityCommitment {
  const AvailabilityCommitment({required this.amount, this.dueAt});

  final Money amount;
  final DateTime? dueAt;
}

class AvailabilityEnvelope {
  const AvailabilityEnvelope({
    required this.id,
    required this.balance,
    this.isToAllocate = false,
  });
  final String id;
  final Money balance;
  final bool isToAllocate;
}

class AvailabilityGoal {
  const AvailabilityGoal({
    required this.id,
    required this.envelopeId,
    required this.target,
    required this.accumulated,
    required this.isActive,
    this.monthlyTarget,
  });
  final String id;
  final String envelopeId;
  final Money target;
  final Money accumulated;
  final bool isActive;
  final Money? monthlyTarget;
}

enum AvailabilitySourceType { goal, shopping }

class AvailabilityPlanItem {
  const AvailabilityPlanItem({
    required this.id,
    required this.rank,
    required this.type,
    required this.sourceId,
    required this.status,
    this.goalId,
    this.estimatedAmount,
  });
  final String id;
  final int rank;
  final AvailabilitySourceType type;
  final String sourceId;
  final String status;
  final String? goalId;
  final Money? estimatedAmount;
}

class AvailabilityPlan {
  const AvailabilityPlan({
    required this.id,
    required this.isActive,
    required this.monthlyCapacity,
    required this.items,
    this.monthlyCapacities = const [],
  });
  final String id;
  final bool isActive;
  final Money? monthlyCapacity;
  final List<AvailabilityPlanItem> items;

  /// Optional known month-by-month capacity. It is never extrapolated past
  /// the supplied horizon; the regular monthly capacity remains the fallback.
  final List<Money> monthlyCapacities;
}

class GoalFundingProjection {
  const GoalFundingProjection({
    required this.goalId,
    required this.realAccumulated,
    required this.securedFunding,
    required this.remaining,
    required this.reliability,
    this.completionDate,
    this.reason,
  });
  final String goalId;
  final Money realAccumulated;
  final Money securedFunding;
  final Money remaining;
  final ProjectionReliability reliability;
  final DateTime? completionDate;
  final String? reason;
}

enum ProjectionReliability { estimated, insufficientData }

class PlanProjectionEntry {
  const PlanProjectionEntry({
    required this.itemId,
    required this.remainingNeed,
    this.months,
    this.completionDate,
    this.reason,
  });
  final String itemId;
  final Money remainingNeed;
  final int? months;
  final DateTime? completionDate;
  final String? reason;
}

class FinancialAvailabilitySnapshot {
  const FinancialAvailabilitySnapshot({
    required this.realLiquidity,
    required this.envelopeTotal,
    required this.toAllocate,
    required this.debtCommitments,
    required this.potentialReceivables,
    required this.goals,
    required this.planEntries,
    required this.warnings,
  });
  final Money realLiquidity;
  final Money envelopeTotal;
  final Money toAllocate;
  final Money debtCommitments;
  final Money potentialReceivables;
  final Map<String, GoalFundingProjection> goals;
  final Map<String, List<PlanProjectionEntry>> planEntries;
  final List<String> warnings;
}

FinancialAvailabilitySnapshot projectFinancialAvailability(
  FinancialAvailabilityInput input,
  DateTime from,
) {
  final activeGoals = input.goals
      .where((goal) => goal.isActive)
      .toList(growable: false);
  final goalInputs = {for (final goal in activeGoals) goal.id: goal};
  final envelopeUse = <String, int>{};
  for (final goal in activeGoals) {
    envelopeUse[goal.envelopeId] = (envelopeUse[goal.envelopeId] ?? 0) + 1;
  }
  final shared = envelopeUse.entries
      .where((e) => e.value > 1)
      .map((e) => e.key)
      .toSet();
  final warnings = <String>[];
  if (shared.isNotEmpty) {
    warnings.add(
      'Une enveloppe est liée à plusieurs objectifs : financement à confirmer.',
    );
  }
  if (input.envelopes.any((e) => e.balance.minorUnits < 0)) {
    warnings.add('Une enveloppe est négative : projection à confirmer.');
  }
  if (input.commitments.any((commitment) => commitment.dueAt == null)) {
    warnings.add(
      'Des dettes sans échéancier précis ne sont pas déduites automatiquement de la projection.',
    );
  }
  final goals = <String, GoalFundingProjection>{
    for (final goal in activeGoals)
      goal.id: GoalFundingProjection(
        goalId: goal.id,
        realAccumulated: goal.accumulated,
        securedFunding: shared.contains(goal.envelopeId)
            ? const Money.fromMinorUnits(0)
            : Money.fromMinorUnits(
                goal.accumulated.minorUnits.clamp(0, goal.target.minorUnits),
              ),
        remaining: Money.fromMinorUnits(
          (goal.target.minorUnits -
                  (shared.contains(goal.envelopeId)
                      ? 0
                      : goal.accumulated.minorUnits))
              .clamp(0, goal.target.minorUnits),
        ),
        reliability: shared.contains(goal.envelopeId)
            ? ProjectionReliability.insufficientData
            : ProjectionReliability.estimated,
        completionDate:
            !shared.contains(goal.envelopeId) &&
                goal.accumulated.minorUnits >= goal.target.minorUnits
            ? from
            : null,
        reason: shared.contains(goal.envelopeId)
            ? 'Enveloppe partagée : financement sécurisé à confirmer.'
            : null,
      ),
  };
  final planEntries = <String, List<PlanProjectionEntry>>{};
  final activePlans = input.plans.where((plan) => plan.isActive).toList();
  if (activePlans.length > 1) {
    warnings.add(
      'Plusieurs plans PRIOS sont actifs : aucune projection ne choisit arbitrairement une capacité.',
    );
    for (final plan in activePlans) {
      planEntries[plan.id] = List.unmodifiable([
        for (final item in plan.items)
          PlanProjectionEntry(
            itemId: item.id,
            remainingNeed: _needForItem(item, goals),
            reason:
                'Projection indisponible — plusieurs plans actifs doivent être clarifiés.',
          ),
      ]);
    }
  } else if (activePlans.isEmpty) {
    for (final goal in goals.values) {
      goals[goal.goalId] = _withGoalReason(
        goal,
        'Projection indisponible — aucun plan PRIOS actif ne fournit de capacité.',
        ProjectionReliability.insufficientData,
      );
    }
  } else {
    final plan = activePlans.single;
    final capacity = plan.monthlyCapacity;
    final entries = <PlanProjectionEntry>[];
    final consumedKeys = <String>{};
    var monthIndex = 0;
    var monthRemaining = Money.fromMinorUnits(0);
    Money? capacityForMonth(int index) {
      final Money? base;
      if (plan.monthlyCapacities.isNotEmpty) {
        base = index < plan.monthlyCapacities.length
            ? plan.monthlyCapacities[index]
            : null;
      } else {
        base = capacity;
      }
      if (base == null) {
        return null;
      }
      final monthStart = DateTime(from.year, from.month + index, 1);
      final nextMonth = DateTime(from.year, from.month + index + 1, 1);
      final due = input.commitments
          .where(
            (commitment) =>
                commitment.dueAt != null &&
                !commitment.dueAt!.isBefore(monthStart) &&
                commitment.dueAt!.isBefore(nextMonth),
          )
          .fold<int>(
            0,
            (total, commitment) => total + commitment.amount.minorUnits,
          );
      return Money.fromMinorUnits(
        (base.minorUnits - due).clamp(0, base.minorUnits),
      );
    }

    for (final item in [
      ...plan.items,
    ]..sort((a, b) => a.rank.compareTo(b.rank))) {
      final isPurchasedShopping =
          item.type == AvailabilitySourceType.shopping &&
          item.status == 'Acheté';
      final linkedGoalId = isPurchasedShopping
          ? null
          : item.type == AvailabilitySourceType.goal
          ? item.sourceId
          : item.goalId;
      final key = linkedGoalId == null
          ? 'shopping:${item.sourceId}'
          : 'goal:$linkedGoalId';
      final need = linkedGoalId == null
          ? (isPurchasedShopping
                ? const Money.fromMinorUnits(0)
                : item.estimatedAmount)
          : goals[linkedGoalId]?.remaining;
      if (need == null) {
        entries.add(
          PlanProjectionEntry(
            itemId: item.id,
            remainingNeed: const Money.fromMinorUnits(0),
            reason: 'Données insuffisantes.',
          ),
        );
        continue;
      }
      if (need.minorUnits == 0) {
        entries.add(
          PlanProjectionEntry(
            itemId: item.id,
            remainingNeed: need,
            months: 0,
            completionDate: from,
          ),
        );
        continue;
      }
      if (!consumedKeys.add(key)) {
        entries.add(
          PlanProjectionEntry(
            itemId: item.id,
            remainingNeed: need,
            reason: 'Projet déjà représenté dans ce plan.',
          ),
        );
        continue;
      }
      if (capacity == null && plan.monthlyCapacities.isEmpty) {
        entries.add(
          PlanProjectionEntry(
            itemId: item.id,
            remainingNeed: need,
            reason:
                'Projection indisponible — aucune capacité mensuelle fiable n’est connue.',
          ),
        );
        continue;
      }
      final goalCap = linkedGoalId == null
          ? null
          : goalInputs[linkedGoalId]?.monthlyTarget;
      if (goalCap != null && goalCap.minorUnits <= 0 && need.minorUnits > 0) {
        entries.add(
          PlanProjectionEntry(
            itemId: item.id,
            remainingNeed: need,
            reason:
                'Projection indisponible — la cible mensuelle de cet objectif est nulle.',
          ),
        );
        continue;
      }
      var remaining = need.minorUnits;
      var monthsUsed = 0;
      DateTime? completion;
      var goalMonthAllocated = 0;
      var currentMonth = -1;
      while (remaining > 0 && monthIndex < 1200) {
        if (currentMonth != monthIndex) {
          currentMonth = monthIndex;
          goalMonthAllocated = 0;
        }
        if (monthRemaining.minorUnits <= 0) {
          final next = capacityForMonth(monthIndex);
          if (next == null) break;
          if (next.minorUnits <= 0) {
            monthIndex++;
            continue;
          }
          monthRemaining = next;
        }
        final capForGoal = goalCap == null
            ? monthRemaining.minorUnits
            : (goalCap.minorUnits - goalMonthAllocated).clamp(
                0,
                monthRemaining.minorUnits,
              );
        if (capForGoal == 0) {
          monthIndex++;
          monthRemaining = Money.fromMinorUnits(0);
          continue;
        }
        final allocation = remaining < capForGoal ? remaining : capForGoal;
        remaining -= allocation;
        goalMonthAllocated += allocation;
        monthRemaining = Money.fromMinorUnits(
          monthRemaining.minorUnits - allocation,
        );
        monthsUsed++;
        if (remaining == 0) {
          completion = DateTime(
            from.year,
            from.month + monthIndex + 1,
            from.day,
          );
          if (monthRemaining.minorUnits == 0) {
            monthIndex++;
          }
          break;
        }
        if (monthRemaining.minorUnits == 0 ||
            goalCap != null && goalMonthAllocated >= goalCap.minorUnits) {
          monthIndex++;
          monthRemaining = Money.fromMinorUnits(0);
        }
      }
      if (completion == null && need.minorUnits > 0) {
        entries.add(
          PlanProjectionEntry(
            itemId: item.id,
            remainingNeed: need,
            reason:
                'Projection indisponible — capacité absente après l’horizon connu.',
          ),
        );
        continue;
      }
      entries.add(
        PlanProjectionEntry(
          itemId: item.id,
          remainingNeed: need,
          months: monthsUsed,
          completionDate: completion ?? from,
        ),
      );
      if (linkedGoalId != null && goals[linkedGoalId] != null) {
        final goal = goals[linkedGoalId]!;
        goals[linkedGoalId] = GoalFundingProjection(
          goalId: goal.goalId,
          realAccumulated: goal.realAccumulated,
          securedFunding: goal.securedFunding,
          remaining: goal.remaining,
          completionDate: completion ?? from,
          reason: goal.reason,
          reliability: goal.reliability,
        );
      }
    }
    planEntries[plan.id] = List.unmodifiable(entries);
    for (final goal
        in goals.values
            .where((goal) => goal.completionDate == null)
            .toList(growable: false)) {
      final isRepresented = plan.items.any(
        (item) =>
            (item.type == AvailabilitySourceType.goal &&
                item.sourceId == goal.goalId) ||
            item.goalId == goal.goalId,
      );
      if (!isRepresented) {
        goals[goal.goalId] = _withGoalReason(
          goal,
          'Projection indisponible — cet objectif n’est dans aucun plan PRIOS actif.',
          ProjectionReliability.insufficientData,
        );
      }
    }
  }
  int sum(Iterable<Money> values) =>
      values.fold(0, (s, value) => s + value.minorUnits);
  return FinancialAvailabilitySnapshot(
    realLiquidity: input.liquidity,
    envelopeTotal: Money.fromMinorUnits(
      sum(input.envelopes.where((e) => !e.isToAllocate).map((e) => e.balance)),
    ),
    toAllocate: Money.fromMinorUnits(
      sum(input.envelopes.where((e) => e.isToAllocate).map((e) => e.balance)),
    ),
    debtCommitments: input.debtCommitments,
    potentialReceivables: input.potentialReceivables,
    goals: Map.unmodifiable(goals),
    planEntries: Map.unmodifiable(planEntries),
    warnings: List.unmodifiable(warnings),
  );
}

Money _needForItem(
  AvailabilityPlanItem item,
  Map<String, GoalFundingProjection> goals,
) {
  final isPurchasedShopping =
      item.type == AvailabilitySourceType.shopping && item.status == 'Acheté';
  final goalId = isPurchasedShopping
      ? null
      : item.type == AvailabilitySourceType.goal
      ? item.sourceId
      : item.goalId;
  if (goalId != null) {
    return goals[goalId]?.remaining ?? const Money.fromMinorUnits(0);
  }
  return isPurchasedShopping
      ? const Money.fromMinorUnits(0)
      : item.estimatedAmount ?? const Money.fromMinorUnits(0);
}

GoalFundingProjection _withGoalReason(
  GoalFundingProjection goal,
  String reason,
  ProjectionReliability reliability,
) => GoalFundingProjection(
  goalId: goal.goalId,
  realAccumulated: goal.realAccumulated,
  securedFunding: goal.securedFunding,
  remaining: goal.remaining,
  completionDate: goal.completionDate,
  reason: reason,
  reliability: reliability,
);
