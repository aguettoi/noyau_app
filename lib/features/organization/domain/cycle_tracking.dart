import 'dart:math' as math;

/// An observed menstrual period. These values are personal observations, not
/// medical findings.
class CyclePeriod {
  const CyclePeriod({required this.startsOn, this.endsOn});

  final DateTime startsOn;
  final DateTime? endsOn;

  int? get bleedingDays =>
      endsOn == null ? null : endsOn!.difference(startsOn).inDays.abs() + 1;
}

enum CycleConfidence { insufficient, low, medium, high }

/// Explainable, non-medical estimate derived only from the owner's history.
class CycleForecast {
  const CycleForecast({
    required this.confidence,
    required this.sampleSize,
    required this.averageCycleDays,
    required this.variabilityDays,
    required this.nextPeriodFrom,
    required this.nextPeriodTo,
    required this.estimatedOvulationFrom,
    required this.estimatedOvulationTo,
  });

  final CycleConfidence confidence;
  final int sampleSize;
  final int? averageCycleDays;
  final int? variabilityDays;
  final DateTime? nextPeriodFrom;
  final DateTime? nextPeriodTo;
  final DateTime? estimatedOvulationFrom;
  final DateTime? estimatedOvulationTo;

  bool get hasEstimate => nextPeriodFrom != null && nextPeriodTo != null;
}

class CycleForecastEngine {
  const CycleForecastEngine._();

  static CycleForecast estimate(List<CyclePeriod> observations) {
    final periods = [...observations]
      ..sort((a, b) => a.startsOn.compareTo(b.startsOn));
    final intervals = <int>[];
    for (var i = 1; i < periods.length; i++) {
      final days = periods[i].startsOn
          .difference(periods[i - 1].startsOn)
          .inDays;
      if (days >= 15 && days <= 90) intervals.add(days);
    }
    if (intervals.isEmpty) {
      return const CycleForecast(
        confidence: CycleConfidence.insufficient,
        sampleSize: 0,
        averageCycleDays: null,
        variabilityDays: null,
        nextPeriodFrom: null,
        nextPeriodTo: null,
        estimatedOvulationFrom: null,
        estimatedOvulationTo: null,
      );
    }

    final average = (intervals.reduce((a, b) => a + b) / intervals.length)
        .round();
    final variance =
        intervals
            .map((days) => math.pow(days - average, 2))
            .reduce((a, b) => a + b) /
        intervals.length;
    final variability = math.sqrt(variance).ceil();
    final uncertainty = math.max(2, variability);
    final nextCenter = periods.last.startsOn.add(Duration(days: average));
    final ovulationCenter = nextCenter.subtract(const Duration(days: 14));
    final confidence = switch ((intervals.length, variability)) {
      (>= 5, <= 3) => CycleConfidence.high,
      (>= 3, <= 7) => CycleConfidence.medium,
      (>= 2, _) => CycleConfidence.low,
      _ => CycleConfidence.insufficient,
    };
    final expanded = confidence == CycleConfidence.insufficient
        ? math.max(7, uncertainty)
        : uncertainty;
    return CycleForecast(
      confidence: confidence,
      sampleSize: intervals.length,
      averageCycleDays: average,
      variabilityDays: variability,
      nextPeriodFrom: nextCenter.subtract(Duration(days: expanded)),
      nextPeriodTo: nextCenter.add(Duration(days: expanded)),
      estimatedOvulationFrom: ovulationCenter.subtract(
        Duration(days: expanded + 1),
      ),
      estimatedOvulationTo: ovulationCenter.add(Duration(days: expanded + 1)),
    );
  }
}

/// Categories that must never enter household projections or sharing.
const strictlyPrivateCycleCategories = <String>{
  'symptom',
  'mood',
  'sleep',
  'energy',
  'stress',
  'libido',
  'skin',
  'appetite',
  'digestion',
  'discharge',
  'temperature',
  'weight',
  'spotting',
  'contraception',
  'intimacy',
};
