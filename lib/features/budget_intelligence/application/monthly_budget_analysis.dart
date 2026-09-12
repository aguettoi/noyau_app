import '../domain/budget_intelligence.dart';

/// Read-only presentation analysis of a simulated month.  It deliberately
/// emits no repository call and never creates a FinancialEvent.
class MonthlyBudgetAnalysis {
  const MonthlyBudgetAnalysis({
    required this.incomeCents,
    required this.personalChargesCents,
    required this.commonChargesCents,
    required this.savingsCents,
    required this.remainingCents,
    required this.cashNeedCents,
    required this.warnings,
    required this.blockers,
    required this.memberSummaries,
    required this.transferSuggestion,
  });

  final int incomeCents;
  final int personalChargesCents;
  final int commonChargesCents;
  final int savingsCents;
  final int remainingCents;
  final int cashNeedCents;
  final List<String> warnings;
  final List<String> blockers;
  final List<MonthlyMemberSummary> memberSummaries;
  final SuggestedTransfer? transferSuggestion;

  bool get isBalanced => blockers.isEmpty && remainingCents >= 0;
  double get fixedChargeRate =>
      incomeCents == 0 ? 0 : personalChargesCents / incomeCents;
  double get savingsRate => incomeCents == 0 ? 0 : savingsCents / incomeCents;
}

class MonthlyMemberSummary {
  const MonthlyMemberSummary({
    required this.memberUserId,
    required this.incomeCents,
    required this.personalChargesCents,
    required this.commonContributionCents,
  });

  final String memberUserId;
  final int incomeCents;
  final int personalChargesCents;
  final int commonContributionCents;
  int get remainingCents =>
      incomeCents - personalChargesCents - commonContributionCents;
}

class SuggestedTransfer {
  const SuggestedTransfer({
    required this.fromMemberUserId,
    required this.toMemberUserId,
    required this.amountCents,
  });

  final String fromMemberUserId;
  final String toMemberUserId;
  final int amountCents;
}

class MonthlyBudgetAnalyzer {
  const MonthlyBudgetAnalyzer();

  MonthlyBudgetAnalysis analyze({
    required BudgetAllocationRun run,
    required List<BudgetScenarioMemberIncome> incomes,
    required List<BudgetScenarioRule> rules,
    Set<String> cashFundingSourceIds = const {},
  }) {
    final warnings = <String>[...run.warnings];
    final blockers = <String>[];
    final personalByMember = <String, int>{};
    var personal = 0;
    var common = 0;
    var savings = 0;
    var cashNeed = 0;
    final ruleByEnvelope = {for (final rule in rules) rule.envelopeId: rule};
    for (final line in run.lines) {
      final rule = ruleByEnvelope[line.envelopeId];
      if (rule == null) continue;
      if (rule.fundingMode == BudgetFundingMode.personalMember &&
          rule.fundingMemberUserId != null) {
        personal += line.plannedAllocationCents;
        personalByMember.update(
          rule.fundingMemberUserId!,
          (value) => value + line.plannedAllocationCents,
          ifAbsent: () => line.plannedAllocationCents,
        );
      } else {
        common += line.plannedAllocationCents;
      }
      if (rule.method == BudgetAllocationMethod.residual) {
        savings += line.plannedAllocationCents;
      }
      if (cashFundingSourceIds.contains(rule.fundingSourcePreference) ||
          (rule.fundingSourcePreference ?? '').toLowerCase().contains('cash') ||
          (rule.fundingSourcePreference ?? '').toLowerCase().contains('esp')) {
        cashNeed += line.plannedAllocationCents;
      }
      if (line.resultingAvailableCents < 0) {
        warnings.add('Une enveloppe restera négative après cette allocation.');
      }
      if (line.warning != null && line.warning!.isNotEmpty) {
        warnings.add(line.warning!);
      }
    }
    if (run.isOverAllocated) {
      blockers.add('Le scénario alloue plus que les ressources disponibles.');
    }
    if (run.remainingUnallocatedCents < 0) {
      blockers.add('Le reste à répartir est négatif.');
    }
    for (final rule in rules.where(
      (rule) => rule.fundingMode == BudgetFundingMode.sharedCustom,
    )) {
      final total = rule.fundingDefinition.values.fold<double>(
        0,
        (sum, value) => sum + (value as num).toDouble(),
      );
      if ((total - 100).abs() > 0.001) {
        blockers.add('Une clé personnalisée doit totaliser 100 %.');
      }
    }
    if (savings == 0 && run.availableResourcesCents > 0) {
      warnings.add('Aucune épargne n’est prévue par cette simulation.');
    }
    final summaries = incomes
        .map(
          (income) => MonthlyMemberSummary(
            memberUserId: income.memberUserId,
            incomeCents: income.eligibleIncomeCents,
            personalChargesCents: personalByMember[income.memberUserId] ?? 0,
            commonContributionCents: run.memberContributions
                .where((value) => value.memberUserId == income.memberUserId)
                .fold(0, (sum, value) => sum + value.contributionCapacityCents),
          ),
        )
        .toList(growable: false);
    return MonthlyBudgetAnalysis(
      incomeCents: run.availableResourcesCents,
      personalChargesCents: personal,
      commonChargesCents: common,
      savingsCents: savings,
      remainingCents: run.remainingUnallocatedCents,
      cashNeedCents: cashNeed,
      warnings: List.unmodifiable(warnings.toSet()),
      blockers: List.unmodifiable(blockers.toSet()),
      memberSummaries: List.unmodifiable(summaries),
      transferSuggestion: _suggestTransfer(summaries),
    );
  }

  SuggestedTransfer? _suggestTransfer(List<MonthlyMemberSummary> members) {
    if (members.length < 2) return null;
    final sorted = [...members]
      ..sort((a, b) => a.remainingCents.compareTo(b.remainingCents));
    final from = sorted.last;
    final to = sorted.first;
    final amount = (from.remainingCents - to.remainingCents) ~/ 2;
    if (amount <= 0) return null;
    return SuggestedTransfer(
      fromMemberUserId: from.memberUserId,
      toMemberUserId: to.memberUserId,
      amountCents: amount,
    );
  }
}
