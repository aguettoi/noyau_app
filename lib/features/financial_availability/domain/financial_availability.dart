import '../../../core/money/money.dart';

/// Pure read model. It never writes a ledger, a FinancialEvent, or a budget.
class FinancialAvailabilityInput {
  const FinancialAvailabilityInput({
    required this.liquidity,
    required this.envelopes,
    required this.debtCommitments,
    required this.potentialReceivables,
    required this.goals,
    required this.plans,
  });
  final Money liquidity;
  final List<AvailabilityEnvelope> envelopes;
  final Money debtCommitments;
  final Money potentialReceivables;
  final List<AvailabilityGoal> goals;
  final List<AvailabilityPlan> plans;
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
  });
  final String id;
  final String envelopeId;
  final Money target;
  final Money accumulated;
  final bool isActive;
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
  });
  final String id;
  final bool isActive;
  final Money? monthlyCapacity;
  final List<AvailabilityPlanItem> items;
}

class GoalFundingProjection {
  const GoalFundingProjection({
    required this.goalId,
    required this.realAccumulated,
    required this.securedFunding,
    required this.remaining,
    this.completionDate,
    this.reason,
  });
  final String goalId;
  final Money realAccumulated;
  final Money securedFunding;
  final Money remaining;
  final DateTime? completionDate;
  final String? reason;
}

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
  if (input.debtCommitments.minorUnits > 0) {
    warnings.add(
      'Des dettes ouvertes restent à intégrer à la capacité future.',
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
          (goal.target.minorUnits - goal.accumulated.minorUnits).clamp(
            0,
            goal.target.minorUnits,
          ),
        ),
        reason: shared.contains(goal.envelopeId)
            ? 'Enveloppe partagée : financement sécurisé à confirmer.'
            : null,
      ),
  };
  final blocking = warnings.isNotEmpty;
  final planEntries = <String, List<PlanProjectionEntry>>{};
  for (final plan in input.plans.where((p) => p.isActive)) {
    final capacity = plan.monthlyCapacity;
    final entries = <PlanProjectionEntry>[];
    final consumedKeys = <String>{};
    var cursor = from;
    for (final item in [
      ...plan.items,
    ]..sort((a, b) => a.rank.compareTo(b.rank))) {
      final linkedGoalId = item.type == AvailabilitySourceType.goal
          ? item.sourceId
          : item.goalId;
      final key = linkedGoalId == null
          ? 'shopping:${item.sourceId}'
          : 'goal:$linkedGoalId';
      final need = linkedGoalId == null
          ? (item.status == 'Acheté'
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
      if (blocking || capacity == null || capacity.minorUnits <= 0) {
        entries.add(
          PlanProjectionEntry(
            itemId: item.id,
            remainingNeed: need,
            reason: blocking
                ? 'Capacité future à confirmer.'
                : 'Capacité mensuelle non disponible.',
          ),
        );
        continue;
      }
      final months = need.minorUnits == 0
          ? 0
          : (need.minorUnits / capacity.minorUnits).ceil();
      cursor = DateTime(cursor.year, cursor.month + months, cursor.day);
      entries.add(
        PlanProjectionEntry(
          itemId: item.id,
          remainingNeed: need,
          months: months,
          completionDate: cursor,
        ),
      );
      if (linkedGoalId != null && goals[linkedGoalId] != null) {
        final goal = goals[linkedGoalId]!;
        goals[linkedGoalId] = GoalFundingProjection(
          goalId: goal.goalId,
          realAccumulated: goal.realAccumulated,
          securedFunding: goal.securedFunding,
          remaining: goal.remaining,
          completionDate: cursor,
          reason: goal.reason,
        );
      }
    }
    planEntries[plan.id] = List.unmodifiable(entries);
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
