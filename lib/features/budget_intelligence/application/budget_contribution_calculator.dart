import '../domain/budget_intelligence.dart';

/// Computes economic funding only. It never selects nor moves money from an
/// account; payment-account preference remains a separate soft hint.
class BudgetContributionCalculator {
  const BudgetContributionCalculator();

  List<BudgetMemberContribution> calculate({
    required List<BudgetScenarioMemberIncome> incomes,
    required Map<String, int> directChargesByMember,
  }) {
    final raw = <String, int>{
      for (final income in incomes)
        income.memberUserId:
            income.eligibleIncomeCents -
            (directChargesByMember[income.memberUserId] ?? 0),
    };
    final total = raw.values.fold<int>(
      0,
      (sum, value) => sum + (value > 0 ? value : 0),
    );
    return List.unmodifiable(
      incomes.map((income) {
        final capacity = raw[income.memberUserId] ?? 0;
        return BudgetMemberContribution(
          memberUserId: income.memberUserId,
          eligibleIncomeCents: income.eligibleIncomeCents,
          directChargesCents: directChargesByMember[income.memberUserId] ?? 0,
          rawCapacityCents: capacity,
          contributionCapacityCents: capacity > 0 ? capacity : 0,
          autoShare: total == 0 || capacity <= 0 ? 0 : capacity / total,
        );
      }),
    );
  }

  Map<String, int> allocateSharedAuto({
    required int amountCents,
    required List<BudgetMemberContribution> members,
  }) {
    if (amountCents < 0) {
      throw StateError('A shared allocation cannot be negative.');
    }
    final results = <String, int>{};
    var assigned = 0;
    for (var index = 0; index < members.length; index++) {
      final member = members[index];
      final amount = index == members.length - 1
          ? amountCents - assigned
          : (amountCents * member.autoShare).round();
      results[member.memberUserId] = amount;
      assigned += amount;
    }
    return Map.unmodifiable(results);
  }

  static void validateCustomPercentages(Map<String, double> shares) {
    if (shares.isEmpty ||
        shares.values.any((share) => share < 0) ||
        (shares.values.fold<double>(0, (sum, share) => sum + share) - 100)
                .abs() >
            .0001) {
      throw StateError(
        'Les contributions personnalisées doivent totaliser 100 %.',
      );
    }
  }

  static void validateFixedContributions(
    Map<String, int> amounts,
    int totalCents,
  ) {
    if (amounts.values.any((amount) => amount < 0) ||
        amounts.values.fold<int>(0, (sum, amount) => sum + amount) !=
            totalCents) {
      throw StateError(
        'Les contributions fixes doivent égaler le budget de l’enveloppe.',
      );
    }
  }
}
