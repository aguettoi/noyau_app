import '../../finance/domain/financial_event.dart';

enum BudgetPeriodStatus { draft, active, closed }

enum BudgetAllocationMethod { fixed, percentage, residual, target, none }

enum RolloverPolicy { reportTotal, reportDeficitOnly, reset, capRollover }

enum ContributionRule {
  proportionalIncome,
  fixedPercentage,
  memberOnly,
  custom,
}

enum BudgetFundingMode {
  personalMember,
  sharedAuto,
  sharedCustom,
  fixedByMember,
  exceptionalIncome,
}

enum BudgetSourceType {
  memberRecurringIncome,
  memberOtherRecurringIncome,
  exceptionalIncome,
  commonCapacity,
  availableSavings,
  other,
}

enum ContributionKeyStrategy {
  automaticRemainingCapacity,
  customPercentage,
  fixedByMember,
  singleMember,
  equal,
}

enum BudgetInsufficientFundsPolicy { strict, cap, skip, proportional }

enum ExceptionalIncomeTreatment {
  excluded,
  includedInSharedCapacity,
  directAllocation,
}

enum BudgetAllocationRunStatus {
  draft,
  simulated,
  approved,
  applied,
  cancelled,
}

enum BudgetEnvelopeState { available, low, exhausted, exceeded, archived }

enum GoalStatus { planned, active, completed, paused, cancelled }

class BudgetPeriod {
  BudgetPeriod({
    required this.id,
    required this.householdId,
    required this.startDate,
    required this.endDate,
    required this.status,
    this.scenarioId,
  }) : assert(!endDate.isBefore(startDate));
  final String id;
  final String householdId;
  final DateTime startDate;
  final DateTime endDate;
  final BudgetPeriodStatus status;
  final String? scenarioId;
  int get year => startDate.year;
  int get month => startDate.month;
}

class BudgetScenario {
  const BudgetScenario({
    required this.id,
    required this.householdId,
    required this.name,
    this.description,
    this.active = false,
    this.priority = 0,
    this.validFrom,
    this.validTo,
    this.triggerType,
    this.triggerDefinition,
    this.notes,
    this.isDefault = false,
    this.currentVersionId,
  });
  final String id;
  final String householdId;
  final String name;
  final String? description;
  final bool active;
  final int priority;
  final DateTime? validFrom;
  final DateTime? validTo;
  final String? triggerType;
  final Map<String, Object?>? triggerDefinition;
  final String? notes;
  final bool isDefault;
  final String? currentVersionId;
}

/// Immutable configuration revision. A monthly run snapshots this identifier;
/// changing a template therefore cannot rewrite a recorded month.
class BudgetScenarioVersion {
  const BudgetScenarioVersion({
    required this.id,
    required this.scenarioId,
    required this.version,
    required this.createdAt,
    this.notes,
  });
  final String id;
  final String scenarioId;
  final int version;
  final DateTime createdAt;
  final String? notes;
}

class BudgetSource {
  const BudgetSource({
    required this.id,
    required this.scenarioVersionId,
    required this.type,
    required this.name,
    required this.expectedCents,
    this.memberUserId,
    this.exceptionalTreatment,
    this.active = true,
  });
  final String id;
  final String scenarioVersionId;
  final BudgetSourceType type;
  final String name;
  final int expectedCents;
  final String? memberUserId;
  final ExceptionalIncomeTreatment? exceptionalTreatment;
  final bool active;
}

/// One programmable allocation step. Amount calculation and contribution key
/// are deliberately separate dimensions.
class BudgetAllocationStep {
  const BudgetAllocationStep({
    required this.id,
    required this.scenarioVersionId,
    required this.order,
    required this.groupName,
    required this.sourceId,
    required this.envelopeId,
    required this.method,
    required this.contributionKey,
    required this.insufficientFundsPolicy,
    this.amountCents,
    this.percentage,
    this.memberUserId,
    this.keyDefinition = const {},
    this.fundingSourcePreference,
    this.active = true,
  });
  final String id;
  final String scenarioVersionId;
  final int order;
  final String groupName;
  final String sourceId;
  final String envelopeId;
  final BudgetAllocationMethod method;
  final ContributionKeyStrategy contributionKey;
  final BudgetInsufficientFundsPolicy insufficientFundsPolicy;
  final int? amountCents;
  final double? percentage;
  final String? memberUserId;
  final Map<String, Object?> keyDefinition;
  final String? fundingSourcePreference;
  final bool active;
}

class BudgetScenarioRule {
  const BudgetScenarioRule({
    required this.id,
    required this.scenarioId,
    required this.envelopeId,
    required this.method,
    required this.priority,
    required this.rolloverPolicy,
    this.amountCents,
    this.percentage,
    this.minimumCents,
    this.maximumCents,
    this.rolloverCapCents,
    this.fundingSourcePreference,
    this.contributionRule = ContributionRule.custom,
    this.notes,
    this.active = true,
    this.fundingMode = BudgetFundingMode.sharedAuto,
    this.fundingMemberUserId,
    this.fundingDefinition = const {},
  });
  final String id;
  final String scenarioId;
  final String envelopeId;
  final BudgetAllocationMethod method;
  final int priority;
  final RolloverPolicy rolloverPolicy;
  final int? amountCents;
  final double? percentage;
  final int? minimumCents;
  final int? maximumCents;
  final int? rolloverCapCents;
  final String? fundingSourcePreference;
  final ContributionRule contributionRule;
  final String? notes;
  final bool active;
  final BudgetFundingMode fundingMode;
  final String? fundingMemberUserId;
  final Map<String, Object?> fundingDefinition;
}

class BudgetScenarioMemberIncome {
  const BudgetScenarioMemberIncome({
    required this.memberUserId,
    required this.netRecurringCents,
    this.otherRecurringCents = 0,
    this.exceptionalCents = 0,
    this.exceptionalTreatment = ExceptionalIncomeTreatment.excluded,
    this.notes,
  });
  final String memberUserId;
  final int netRecurringCents;
  final int otherRecurringCents;
  final int exceptionalCents;
  final ExceptionalIncomeTreatment exceptionalTreatment;
  final String? notes;
  int get eligibleIncomeCents =>
      netRecurringCents +
      otherRecurringCents +
      (exceptionalTreatment ==
              ExceptionalIncomeTreatment.includedInSharedCapacity
          ? exceptionalCents
          : 0);
}

class BudgetMemberContribution {
  const BudgetMemberContribution({
    required this.memberUserId,
    required this.eligibleIncomeCents,
    required this.directChargesCents,
    required this.rawCapacityCents,
    required this.contributionCapacityCents,
    required this.autoShare,
  });
  final String memberUserId;
  final int eligibleIncomeCents;
  final int directChargesCents;
  final int rawCapacityCents;
  final int contributionCapacityCents;
  final double autoShare;
}

class BudgetAllocationRunLine {
  const BudgetAllocationRunLine({
    required this.envelopeId,
    required this.previousBalanceCents,
    required this.rolloverCents,
    required this.plannedAllocationCents,
    required this.resultingAvailableCents,
    required this.priority,
    required this.state,
    this.warning,
    this.contributions = const {},
    this.fundingSourcePreference,
  });
  final String envelopeId;
  final int previousBalanceCents;
  final int rolloverCents;
  final int plannedAllocationCents;
  final int resultingAvailableCents;
  final int priority;
  final BudgetEnvelopeState state;
  final String? warning;
  final Map<String, int> contributions;
  final String? fundingSourcePreference;
}

/// One source-account contribution to a persisted allocation-run line.
/// Several entries may fund the same envelope, but their sum must remain
/// exactly equal to the line planned by the immutable run snapshot.
class BudgetRunFunding {
  const BudgetRunFunding({
    required this.runLineId,
    required this.sourceAccountId,
    required this.envelopeId,
    required this.amountCents,
  });

  final String runLineId;
  final String sourceAccountId;
  final String envelopeId;
  final int amountCents;
}

class BudgetAllocationRun {
  const BudgetAllocationRun({
    required this.id,
    required this.householdId,
    required this.periodId,
    required this.scenarioId,
    required this.availableResourcesCents,
    required this.lines,
    this.status = BudgetAllocationRunStatus.draft,
    this.memberContributions = const [],
    this.warnings = const [],
  });
  final String id;
  final String householdId;
  final String periodId;
  final String scenarioId;
  final int availableResourcesCents;
  final List<BudgetAllocationRunLine> lines;
  final BudgetAllocationRunStatus status;
  final List<BudgetMemberContribution> memberContributions;
  final List<String> warnings;
  int get calculatedTotalCents =>
      lines.fold(0, (sum, line) => sum + line.plannedAllocationCents);
  int get remainingUnallocatedCents =>
      availableResourcesCents - calculatedTotalCents;
  bool get isOverAllocated => remainingUnallocatedCents < 0;
}

class BudgetGoal {
  const BudgetGoal({
    required this.id,
    required this.householdId,
    required this.name,
    required this.targetCents,
    required this.priority,
    required this.status,
    this.currentCents = 0,
    this.targetDate,
    this.fundingEnvelopeId,
    this.monthlyTargetCents,
    this.notes,
  });
  final String id;
  final String householdId;
  final String name;
  final int targetCents;
  final int currentCents;
  final int priority;
  final GoalStatus status;
  final DateTime? targetDate;
  final String? fundingEnvelopeId;
  final int? monthlyTargetCents;
  final String? notes;
  int get remainingCents => (targetCents - currentCents).clamp(0, targetCents);
}

class BudgetProjection {
  const BudgetProjection({
    required this.projectedCents,
    required this.varianceCents,
  });
  final int projectedCents;
  final int varianceCents;
}

FinancialEventType? financialEventTypeForBudgetApplication() =>
    FinancialEventType.budgetAllocation;
