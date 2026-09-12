enum BudgetHorizon { monthly, ytd, ltd }

class BudgetEnvelopeMetrics {
  const BudgetEnvelopeMetrics({
    required this.plannedCents,
    required this.consumptionCents,
    required this.inflowsCents,
    required this.outflowsCents,
    required this.balanceCents,
    this.hasOverspentHistory = false,
  });
  final int plannedCents;
  final int consumptionCents;
  final int inflowsCents;
  final int outflowsCents;
  final int balanceCents;
  final bool hasOverspentHistory;
  int get varianceCents => plannedCents - consumptionCents;
  double? get consumptionRate =>
      plannedCents <= 0 ? null : consumptionCents / plannedCents;
  bool get isOverspent =>
      hasOverspentHistory ||
      balanceCents < 0 ||
      consumptionCents > plannedCents;
}

class BudgetReporting {
  const BudgetReporting._();

  static BudgetEnvelopeMetrics aggregate(
    Iterable<BudgetEnvelopeMetrics> periods,
  ) {
    return periods.fold(
      const BudgetEnvelopeMetrics(
        plannedCents: 0,
        consumptionCents: 0,
        inflowsCents: 0,
        outflowsCents: 0,
        balanceCents: 0,
      ),
      (total, item) => BudgetEnvelopeMetrics(
        plannedCents: total.plannedCents + item.plannedCents,
        consumptionCents: total.consumptionCents + item.consumptionCents,
        inflowsCents: total.inflowsCents + item.inflowsCents,
        outflowsCents: total.outflowsCents + item.outflowsCents,
        balanceCents: total.balanceCents + item.balanceCents,
        hasOverspentHistory: total.hasOverspentHistory || item.isOverspent,
      ),
    );
  }
}
