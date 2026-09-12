import '../domain/budget_intelligence.dart';
import 'budget_contribution_calculator.dart';

/// Pure planning engine. It never writes a FinancialEvent or a ledger row.
class BudgetSimulator {
  const BudgetSimulator();

  BudgetAllocationRun simulate({
    required String runId,
    required String householdId,
    required String periodId,
    required String scenarioId,
    required int availableResourcesCents,
    required Map<String, int> previousBalancesCents,
    required List<BudgetScenarioRule> rules,
    List<BudgetScenarioMemberIncome> memberIncomes = const [],
  }) {
    var remaining = availableResourcesCents;
    final lines = <BudgetAllocationRunLine>[];
    final residualRules = <BudgetScenarioRule>[];
    final activeRules = rules.where((item) => item.active).toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));
    for (final rule in activeRules) {
      if (rule.method == BudgetAllocationMethod.residual) {
        residualRules.add(rule);
        continue;
      }
      final previous = previousBalancesCents[rule.envelopeId] ?? 0;
      final rollover = rolloverFor(
        previous,
        rule.rolloverPolicy,
        rule.rolloverCapCents,
      );
      final planned = _planned(
        rule,
        availableResourcesCents,
        previous,
        rollover,
      );
      final bounded = _bound(planned, rule.minimumCents, rule.maximumCents);
      remaining -= bounded;
      lines.add(_line(rule, previous, rollover, bounded));
    }
    for (final rule in residualRules) {
      final previous = previousBalancesCents[rule.envelopeId] ?? 0;
      final rollover = rolloverFor(
        previous,
        rule.rolloverPolicy,
        rule.rolloverCapCents,
      );
      final planned = remaining > 0 ? remaining : 0;
      remaining -= planned;
      lines.add(_line(rule, previous, rollover, planned));
    }
    final byEnvelope = {for (final line in lines) line.envelopeId: line};
    final directCharges = <String, int>{};
    for (final rule in activeRules.where(
      (rule) =>
          rule.fundingMode == BudgetFundingMode.personalMember &&
          rule.fundingMemberUserId != null,
    )) {
      directCharges[rule.fundingMemberUserId!] =
          (directCharges[rule.fundingMemberUserId!] ?? 0) +
          (byEnvelope[rule.envelopeId]?.plannedAllocationCents ?? 0);
    }
    final members = const BudgetContributionCalculator().calculate(
      incomes: memberIncomes,
      directChargesByMember: directCharges,
    );
    final enrichedLines = <BudgetAllocationRunLine>[];
    for (final line in lines) {
      final rule = activeRules.firstWhere(
        (item) => item.envelopeId == line.envelopeId,
      );
      final contributions = _contributionsFor(
        rule,
        line.plannedAllocationCents,
        members,
      );
      enrichedLines.add(
        BudgetAllocationRunLine(
          envelopeId: line.envelopeId,
          previousBalanceCents: line.previousBalanceCents,
          rolloverCents: line.rolloverCents,
          plannedAllocationCents: line.plannedAllocationCents,
          resultingAvailableCents: line.resultingAvailableCents,
          priority: line.priority,
          state: line.state,
          warning: line.warning,
          contributions: contributions,
          fundingSourcePreference: rule.fundingSourcePreference,
        ),
      );
    }
    _validateExceptionalDirectAllocations(
      rules: activeRules,
      lines: enrichedLines,
      incomes: memberIncomes,
    );
    final warnings = members
        .where((member) => member.rawCapacityCents < 0)
        .map(
          (member) =>
              'Un déficit personnel de ${-member.rawCapacityCents} centimes a été détecté.',
        )
        .toList(growable: false);
    final run = BudgetAllocationRun(
      id: runId,
      householdId: householdId,
      periodId: periodId,
      scenarioId: scenarioId,
      availableResourcesCents: availableResourcesCents,
      lines: List.unmodifiable(enrichedLines),
      status: BudgetAllocationRunStatus.simulated,
      memberContributions: members,
      warnings: warnings,
    );
    return run;
  }

  static void _validateExceptionalDirectAllocations({
    required List<BudgetScenarioRule> rules,
    required List<BudgetAllocationRunLine> lines,
    required List<BudgetScenarioMemberIncome> incomes,
  }) {
    final directIncomeByMember = <String, int>{
      for (final income in incomes)
        if (income.exceptionalTreatment ==
            ExceptionalIncomeTreatment.directAllocation)
          income.memberUserId: income.exceptionalCents,
    };
    final allocatedByMember = <String, int>{};
    for (final rule in rules.where(
      (rule) => rule.fundingMode == BudgetFundingMode.exceptionalIncome,
    )) {
      final memberId = rule.fundingMemberUserId;
      if (memberId == null || !directIncomeByMember.containsKey(memberId)) {
        throw StateError(
          'Une affectation directe requiert un revenu exceptionnel configuré.',
        );
      }
      final line = lines.firstWhere(
        (line) => line.envelopeId == rule.envelopeId,
      );
      allocatedByMember[memberId] =
          (allocatedByMember[memberId] ?? 0) + line.plannedAllocationCents;
    }
    for (final entry in allocatedByMember.entries) {
      if (entry.value > (directIncomeByMember[entry.key] ?? 0)) {
        throw StateError(
          'Le revenu exceptionnel ne couvre pas son affectation directe.',
        );
      }
    }
  }

  Map<String, int> _contributionsFor(
    BudgetScenarioRule rule,
    int total,
    List<BudgetMemberContribution> members,
  ) {
    if (rule.fundingMode == BudgetFundingMode.personalMember &&
        rule.fundingMemberUserId != null) {
      return {rule.fundingMemberUserId!: total};
    }
    if (rule.fundingMode == BudgetFundingMode.exceptionalIncome &&
        rule.fundingMemberUserId != null) {
      return {rule.fundingMemberUserId!: total};
    }
    if (rule.fundingMode == BudgetFundingMode.sharedAuto) {
      return const BudgetContributionCalculator().allocateSharedAuto(
        amountCents: total,
        members: members,
      );
    }
    final result = <String, int>{};
    if (rule.fundingMode == BudgetFundingMode.sharedCustom) {
      final shares = rule.fundingDefinition.map(
        (id, value) => MapEntry(id, (value as num).toDouble()),
      );
      BudgetContributionCalculator.validateCustomPercentages(shares);
      var assigned = 0;
      final entries = shares.entries.toList();
      for (var index = 0; index < entries.length; index++) {
        final entry = entries[index];
        final amount = index == entries.length - 1
            ? total - assigned
            : (total * entry.value / 100).round();
        result[entry.key] = amount;
        assigned += amount;
      }
    } else if (rule.fundingMode == BudgetFundingMode.fixedByMember) {
      for (final entry in rule.fundingDefinition.entries) {
        result[entry.key] = (entry.value as num).toInt();
      }
      BudgetContributionCalculator.validateFixedContributions(result, total);
    }
    return Map.unmodifiable(result);
  }

  static int rolloverFor(int balance, RolloverPolicy policy, int? capCents) =>
      switch (policy) {
        RolloverPolicy.reportTotal => balance,
        RolloverPolicy.reportDeficitOnly => balance < 0 ? balance : 0,
        RolloverPolicy.reset => 0,
        RolloverPolicy.capRollover => balance.clamp(
          -(capCents ?? 0),
          capCents ?? 0,
        ),
      };

  static BudgetProjection projectEndOfMonth({
    required int spentToDateCents,
    required int elapsedDays,
    required int daysInMonth,
    required int plannedCents,
  }) {
    if (elapsedDays <= 0 || daysInMonth <= 0) {
      throw StateError('La période de projection est invalide.');
    }
    final projected = (spentToDateCents * daysInMonth / elapsedDays).round();
    return BudgetProjection(
      projectedCents: projected,
      varianceCents: plannedCents - projected,
    );
  }

  static DateTime? goalCompletionDate({
    required DateTime from,
    required int remainingCents,
    required int monthlyAllocationCents,
  }) {
    if (remainingCents <= 0) return from;
    if (monthlyAllocationCents <= 0) return null;
    final months = (remainingCents / monthlyAllocationCents).ceil();
    return DateTime(from.year, from.month + months, from.day);
  }

  static int _planned(
    BudgetScenarioRule rule,
    int resources,
    int previous,
    int rollover,
  ) => switch (rule.method) {
    BudgetAllocationMethod.fixed => rule.amountCents ?? 0,
    BudgetAllocationMethod.percentage =>
      ((rule.percentage ?? 0) * resources / 100).round(),
    BudgetAllocationMethod.target =>
      ((rule.amountCents ?? 0) - (previous + rollover)).clamp(
        0,
        rule.amountCents ?? 0,
      ),
    BudgetAllocationMethod.none => 0,
    BudgetAllocationMethod.residual => 0,
  };

  static int _bound(int value, int? minimum, int? maximum) =>
      value.clamp(minimum ?? 0, maximum ?? value);

  static BudgetAllocationRunLine _line(
    BudgetScenarioRule rule,
    int previous,
    int rollover,
    int planned,
  ) {
    final resulting = rollover + planned;
    final state = resulting < 0
        ? BudgetEnvelopeState.exceeded
        : resulting == 0
        ? BudgetEnvelopeState.exhausted
        : BudgetEnvelopeState.available;
    return BudgetAllocationRunLine(
      envelopeId: rule.envelopeId,
      previousBalanceCents: previous,
      rolloverCents: rollover,
      plannedAllocationCents: planned,
      resultingAvailableCents: resulting,
      priority: rule.priority,
      state: state,
      warning: resulting < 0 ? 'Solde négatif prévu.' : null,
    );
  }
}
