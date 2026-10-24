import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/wealth/domain/financing_simulation.dart';
import 'package:noyau_app/features/wealth/domain/wealth_models.dart';

void main() {
  FinancingSimulationInput offer({
    String id = 'a',
    String label = 'Offre A',
    FinancingStructure structure = FinancingStructure.interestLoan,
    int duration = 12,
    double? rate = .06,
    Money? fixedCost,
    Money downPayment = const Money.fromMinorUnits(200000),
    Money benefits = const Money.fromMinorUnits(0),
    DateTime? start,
  }) => FinancingSimulationInput(
    id: id,
    label: label,
    structure: structure,
    financedAmount: const Money.fromMinorUnits(1200000),
    downPayment: downPayment,
    startDate: start ?? DateTime(2026, 1, 31),
    durationMonths: duration,
    annualRate: structure == FinancingStructure.interestLoan ? rate : null,
    fixedTotalCost: fixedCost,
    projectedBenefits: benefits,
  );

  test('WLT-05 simule échéancier, coût, total et date sans écriture', () {
    final result = simulateFinancingOffer(
      offer(),
      authorizedLiquidity: const Money.fromMinorUnits(300000),
      availabilityComplete: true,
    );
    expect(result.schedule, hasLength(12));
    expect(result.periodicPayment.minorUnits, greaterThan(0));
    expect(result.totalCost.minorUnits, greaterThan(0));
    expect(result.totalPaid.minorUnits, greaterThan(1400000));
    expect(result.capacityStatus, FinancingCapacityStatus.sufficient);
    expect(result.assumptions, hasLength(2));
  });

  test('temporalité pince les fins de mois et traverse année', () {
    final result = simulateFinancingOffer(offer(duration: 12));
    expect(result.schedule.first.date, DateTime(2026, 2, 28));
    expect(result.schedule.last.date, DateTime(2027, 1, 31));
  });

  test('WLT-06 conserve Murabaha et avantages projetés paramétrables', () {
    final result = simulateFinancingOffer(
      offer(
        structure: FinancingStructure.murabaha,
        rate: null,
        fixedCost: const Money.fromMinorUnits(180000),
        benefits: const Money.fromMinorUnits(50000),
      ),
    );
    expect(result.input.structure, FinancingStructure.murabaha);
    expect(result.totalCost.minorUnits, closeTo(180000, 12));
    expect(
      result.netProjectedCost,
      result.totalPaid - const Money.fromMinorUnits(50000),
    );
    expect(result.capacityStatus, FinancingCapacityStatus.unavailable);
  });

  test('R4-08 compare plusieurs offres sans déclarer un gagnant global', () {
    final comparison = compareFinancingOffers([
      offer(),
      offer(
        id: 'b',
        label: 'Offre B',
        duration: 24,
        rate: .03,
        downPayment: const Money.fromMinorUnits(100000),
      ),
      offer(
        id: 'c',
        label: 'Offre C',
        structure: FinancingStructure.fixedCost,
        rate: null,
        fixedCost: const Money.fromMinorUnits(100000),
      ),
    ]);
    expect(comparison.results, hasLength(3));
    expect(comparison.isComparable, isTrue);
    expect(comparison.lowestPayment, isNotNull);
    expect(comparison.lowestProjectedCost, isNotNull);
    expect(comparison.shortestDuration, isNotNull);
  });

  test('données incomplètes refusent une conclusion de capacité', () {
    final result = simulateFinancingOffer(
      offer(),
      authorizedLiquidity: const Money.fromMinorUnits(999999999),
      availabilityComplete: false,
    );
    expect(result.capacityStatus, FinancingCapacityStatus.unavailable);
  });

  test('simulation est déterministe et idempotente', () {
    final input = offer();
    final first = simulateFinancingOffer(input);
    final second = simulateFinancingOffer(input);
    expect(first.totalPaid, second.totalPaid);
    expect(first.endDate, second.endDate);
    expect(first.schedule.length, second.schedule.length);
  });

  test('hypothèses invalides sont refusées', () {
    expect(
      () => simulateFinancingOffer(
        FinancingSimulationInput(
          id: 'bad',
          label: 'Bad',
          structure: FinancingStructure.interestLoan,
          financedAmount: const Money.fromMinorUnits(0),
          downPayment: const Money.fromMinorUnits(0),
          startDate: DateTime(2026),
          durationMonths: 0,
        ),
      ),
      throwsArgumentError,
    );
  });
}
