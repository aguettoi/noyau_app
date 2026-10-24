import '../../../core/money/money.dart';
import 'wealth_models.dart';

enum FinancingCapacityStatus { sufficient, insufficient, unavailable }

class FinancingSimulationAssumption {
  const FinancingSimulationAssumption({
    required this.rule,
    required this.source,
    required this.period,
    required this.reason,
  });

  final String rule;
  final String source;
  final String period;
  final String reason;
}

class FinancingSimulationInput {
  const FinancingSimulationInput({
    required this.id,
    required this.label,
    required this.structure,
    required this.financedAmount,
    required this.downPayment,
    required this.startDate,
    required this.durationMonths,
    this.periodicityMonths = 1,
    this.annualRate,
    this.fixedTotalCost,
    this.scheduledPayment,
    this.projectedBenefits = const Money.fromMinorUnits(0),
  });

  final String id;
  final String label;
  final FinancingStructure structure;
  final Money financedAmount;
  final Money downPayment;
  final DateTime startDate;
  final int durationMonths;
  final int periodicityMonths;
  final double? annualRate;
  final Money? fixedTotalCost;
  final Money? scheduledPayment;
  final Money projectedBenefits;
}

class FinancingSimulationResult {
  const FinancingSimulationResult({
    required this.input,
    required this.schedule,
    required this.totalCost,
    required this.totalPaid,
    required this.netProjectedCost,
    required this.endDate,
    required this.capacityStatus,
    required this.assumptions,
  });

  final FinancingSimulationInput input;
  final List<FinancingScheduleLine> schedule;
  final Money totalCost;
  final Money totalPaid;
  final Money netProjectedCost;
  final DateTime endDate;
  final FinancingCapacityStatus capacityStatus;
  final List<FinancingSimulationAssumption> assumptions;

  Money get periodicPayment =>
      schedule.isEmpty ? const Money.fromMinorUnits(0) : schedule.first.payment;
}

FinancingSimulationResult simulateFinancingOffer(
  FinancingSimulationInput input, {
  Money? authorizedLiquidity,
  bool availabilityComplete = false,
}) {
  if (input.financedAmount.minorUnits <= 0 ||
      input.downPayment.minorUnits < 0 ||
      input.durationMonths <= 0 ||
      input.periodicityMonths <= 0 ||
      input.projectedBenefits.minorUnits < 0) {
    throw ArgumentError('Hypothèses de financement invalides.');
  }
  if (input.structure == FinancingStructure.interestLoan &&
      (input.annualRate == null || input.annualRate! < 0)) {
    throw ArgumentError('Un prêt à intérêt exige un taux valide.');
  }
  if (input.annualRate != null && input.annualRate! < 0) {
    throw ArgumentError('Le taux ne peut pas être négatif.');
  }
  if (input.fixedTotalCost != null && input.fixedTotalCost!.minorUnits < 0) {
    throw ArgumentError('Le coût fixe ne peut pas être négatif.');
  }

  final profile = FinancingProfile(
    id: 'simulation:${input.id}',
    label: input.label,
    structure: input.structure,
    obligationId: 'simulation-only',
    principalInitial: input.financedAmount,
    remainingLiability: input.financedAmount,
    startDate: input.startDate,
    durationMonths: input.durationMonths,
    periodicityMonths: input.periodicityMonths,
    annualRate: input.annualRate,
    fixedTotalCost: input.fixedTotalCost,
    scheduledPayment: input.scheduledPayment,
  );
  final schedule = buildFinancingSchedule(profile);
  final totalPaidMinor = schedule.fold<int>(
    0,
    (sum, line) => sum + line.payment.minorUnits,
  );
  final totalCostMinor = schedule.fold<int>(
    0,
    (sum, line) => sum + line.cost.minorUnits,
  );
  final grossOutflow = Money.fromMinorUnits(
    input.downPayment.minorUnits + totalPaidMinor,
  );
  final netProjected = Money.fromMinorUnits(
    (grossOutflow.minorUnits - input.projectedBenefits.minorUnits)
        .clamp(0, 1 << 62)
        .toInt(),
  );
  final capacity = !availabilityComplete || authorizedLiquidity == null
      ? FinancingCapacityStatus.unavailable
      : authorizedLiquidity.minorUnits >= input.downPayment.minorUnits
      ? FinancingCapacityStatus.sufficient
      : FinancingCapacityStatus.insufficient;
  final period =
      '${_date(input.startDate)} → ${schedule.isEmpty ? _date(input.startDate) : _date(schedule.last.date)}';
  return FinancingSimulationResult(
    input: input,
    schedule: schedule,
    totalCost: Money.fromMinorUnits(totalCostMinor),
    totalPaid: grossOutflow,
    netProjectedCost: netProjected,
    endDate: schedule.isEmpty ? input.startDate : schedule.last.date,
    capacityStatus: capacity,
    assumptions: List.unmodifiable([
      FinancingSimulationAssumption(
        rule: switch (input.structure) {
          FinancingStructure.interestLoan => 'Amortissement à taux déclaré',
          FinancingStructure.murabaha => 'Marge/coût fixe déclaré',
          FinancingStructure.fixedCost => 'Coût fixe déclaré',
          FinancingStructure.other => 'Échéance contractuelle déclarée',
        },
        source: 'Hypothèses saisies — simulation non financière',
        period: period,
        reason:
            'Montant financé, apport, durée et coût sont comparés sans modifier l’obligation canonique.',
      ),
      FinancingSimulationAssumption(
        rule: 'Avantages projetés séparés du réalisé',
        source: 'Paramètres logement/aides de la simulation',
        period: period,
        reason:
            'Les aides projetées réduisent uniquement le coût analytique projeté.',
      ),
    ]),
  );
}

class FinancingComparison {
  const FinancingComparison(this.results);

  final List<FinancingSimulationResult> results;

  bool get isComparable => results.length >= 2;

  FinancingSimulationResult? get lowestProjectedCost => results.isEmpty
      ? null
      : results.reduce(
          (a, b) =>
              a.netProjectedCost.minorUnits <= b.netProjectedCost.minorUnits
              ? a
              : b,
        );

  FinancingSimulationResult? get lowestPayment => results.isEmpty
      ? null
      : results.reduce(
          (a, b) => a.periodicPayment.minorUnits <= b.periodicPayment.minorUnits
              ? a
              : b,
        );

  FinancingSimulationResult? get shortestDuration => results.isEmpty
      ? null
      : results.reduce(
          (a, b) => a.input.durationMonths <= b.input.durationMonths ? a : b,
        );
}

FinancingComparison compareFinancingOffers(
  Iterable<FinancingSimulationInput> offers, {
  Money? authorizedLiquidity,
  bool availabilityComplete = false,
}) => FinancingComparison(
  List.unmodifiable(
    offers.map(
      (offer) => simulateFinancingOffer(
        offer,
        authorizedLiquidity: authorizedLiquidity,
        availabilityComplete: availabilityComplete,
      ),
    ),
  ),
);

String _date(DateTime value) => value.toIso8601String().split('T').first;
