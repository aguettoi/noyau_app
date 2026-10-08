import '../../../core/money/money.dart';

enum BenefitType { acquisitionAid, taxSaving, employerContribution, other }

enum BenefitRecognition { projected, cashReceived, liabilityReduction }

class HomeBenefit {
  const HomeBenefit({
    required this.id,
    required this.assetId,
    required this.type,
    required this.recognition,
    required this.amount,
    this.financialEventId,
  });
  final String id;
  final String assetId;
  final BenefitType type;
  final BenefitRecognition recognition;
  final Money amount;
  final String? financialEventId;

  bool get isProjected => recognition == BenefitRecognition.projected;
}

class HomeCostSummary {
  const HomeCostSummary({
    required this.grossFinancingCost,
    required this.actualBenefits,
    required this.projectedBenefits,
  });
  final Money grossFinancingCost;
  final Money actualBenefits;
  final Money projectedBenefits;
  Money get actualNetCost => grossFinancingCost - actualBenefits;
  Money get projectedNetCost => grossFinancingCost - projectedBenefits;
}

HomeCostSummary calculateHomeCost({
  required Money grossFinancingCost,
  required Iterable<HomeBenefit> benefits,
}) {
  var actual = 0;
  var projected = 0;
  final recognizedEvents = <String>{};
  for (final benefit in benefits) {
    if (benefit.isProjected) {
      projected += benefit.amount.minorUnits;
      continue;
    }
    final event = benefit.financialEventId;
    if (event != null && recognizedEvents.add(event)) {
      actual += benefit.amount.minorUnits;
    }
  }
  return HomeCostSummary(
    grossFinancingCost: grossFinancingCost,
    actualBenefits: Money.fromMinorUnits(actual),
    projectedBenefits: Money.fromMinorUnits(projected),
  );
}

enum VehicleCostCategory {
  financing,
  insurance,
  tax,
  maintenance,
  oilChange,
  repair,
  fuel,
  toll,
  parking,
  other,
}

class AssetExpenseLink {
  const AssetExpenseLink({
    required this.id,
    required this.assetId,
    required this.financialEventId,
    required this.category,
    required this.amount,
    required this.occurredAt,
  });
  final String id;
  final String assetId;
  final String financialEventId;
  final String category;
  final Money amount;
  final DateTime occurredAt;
}

class VehicleCostPlan {
  const VehicleCostPlan({
    required this.id,
    required this.assetId,
    required this.category,
    required this.label,
    required this.amount,
    required this.dueDate,
  });
  final String id;
  final String assetId;
  final VehicleCostCategory category;
  final String label;
  final Money amount;
  final DateTime dueDate;
}

class VehicleCostSummary {
  const VehicleCostSummary({
    required this.acquisition,
    required this.actualCosts,
    required this.currentValue,
    required this.monthlyAverage,
  });
  final Money acquisition;
  final Money actualCosts;
  final Money currentValue;
  final Money monthlyAverage;
  Money get totalCostOfOwnership => acquisition + actualCosts - currentValue;
}

VehicleCostSummary calculateVehicleCost({
  required Money acquisition,
  required Money currentValue,
  required Iterable<AssetExpenseLink> actualCosts,
  required int observedMonths,
}) {
  final byEvent = <String, int>{};
  for (final cost in actualCosts) {
    byEvent.putIfAbsent(cost.financialEventId, () => cost.amount.minorUnits);
  }
  final total = byEvent.values.fold(0, (sum, value) => sum + value);
  return VehicleCostSummary(
    acquisition: acquisition,
    actualCosts: Money.fromMinorUnits(total),
    currentValue: currentValue,
    monthlyAverage: Money.fromMinorUnits(
      observedMonths <= 0 ? 0 : (total / observedMonths).round(),
    ),
  );
}
