import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/wealth/domain/home_auto_models.dart';

void main() {
  test('coût logement sépare réalisé, projeté et évite le double comptage', () {
    final result = calculateHomeCost(
      grossFinancingCost: const Money.fromMinorUnits(1000000),
      benefits: const [
        HomeBenefit(
          id: 'p',
          assetId: 'h',
          type: BenefitType.taxSaving,
          recognition: BenefitRecognition.projected,
          amount: Money.fromMinorUnits(100000),
        ),
        HomeBenefit(
          id: 'a',
          assetId: 'h',
          type: BenefitType.employerContribution,
          recognition: BenefitRecognition.cashReceived,
          amount: Money.fromMinorUnits(50000),
          financialEventId: 'event',
        ),
        HomeBenefit(
          id: 'duplicate',
          assetId: 'h',
          type: BenefitType.other,
          recognition: BenefitRecognition.liabilityReduction,
          amount: Money.fromMinorUnits(50000),
          financialEventId: 'event',
        ),
      ],
    );
    expect(result.projectedBenefits.minorUnits, 100000);
    expect(result.actualBenefits.minorUnits, 50000);
    expect(result.actualNetCost.minorUnits, 950000);
    expect(result.projectedNetCost.minorUnits, 900000);
  });

  test('TCO auto déduplique les coûts par FinancialEvent', () {
    final result = calculateVehicleCost(
      acquisition: const Money.fromMinorUnits(1000000),
      currentValue: const Money.fromMinorUnits(800000),
      observedMonths: 2,
      actualCosts: [
        AssetExpenseLink(
          id: '1',
          assetId: 'v',
          financialEventId: 'e',
          category: 'fuel',
          amount: const Money.fromMinorUnits(20000),
          occurredAt: DateTime(2026),
        ),
        AssetExpenseLink(
          id: '2',
          assetId: 'v',
          financialEventId: 'e',
          category: 'other',
          amount: const Money.fromMinorUnits(20000),
          occurredAt: DateTime(2026),
        ),
      ],
    );
    expect(result.actualCosts.minorUnits, 20000);
    expect(result.monthlyAverage.minorUnits, 10000);
    expect(result.totalCostOfOwnership.minorUnits, 220000);
  });
}
