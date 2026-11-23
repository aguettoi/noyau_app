import 'dart:convert';

import 'package:noyau_app/features/organization/domain/cycle_tracking.dart';

void main() {
  final scenarios = <String, List<int>>{
    'regular_28': List<int>.filled(14, 28),
    'regular_short': [21, 22, 21, 21, 22, 21, 22, 21, 21, 22, 21, 21],
    'regular_long': [40, 39, 41, 40, 40, 39, 41, 40, 40, 39, 41, 40],
    'variable': [25, 31, 27, 30, 26, 32, 28, 29, 25, 31, 27, 30],
    'progressive_shortening': [34, 33, 32, 31, 30, 29, 28, 27, 26, 25],
    'progressive_lengthening': [24, 25, 26, 27, 28, 29, 30, 31, 32, 33],
    'missing_cycle': [28, 28, 56, 28, 29, 27, 28, 28],
    'unstable_abstention': [18, 55, 20, 60, 17, 58, 19],
    'incoherent_abstention': [7, 120, 8, 140, 6],
  };

  final output = <String, Object?>{
    'engine_version': CycleForecastEngine.version,
    'synthetic_only': true,
    'scenarios': <String, Object?>{},
  };
  final scenarioOutput = output['scenarios']! as Map<String, Object?>;
  final calibration = <CycleConfidence, List<double>>{};
  var totalPredictions = 0;
  var abstentions = 0;
  for (final entry in scenarios.entries) {
    final periods = _periods(entry.value);
    final forecast = CycleForecastEngine.estimate(periods);
    final report = CycleForecastEngine.backtest(periods);
    final metrics = CycleQualityMetrics.fromBacktest(report);
    totalPredictions += metrics.predictionCount;
    if (!forecast.hasEstimate) abstentions++;
    if (metrics.maeDays != null) {
      calibration
          .putIfAbsent(forecast.confidence, () => <double>[])
          .add(metrics.maeDays!);
    }
    scenarioOutput[entry.key] = {
      'history_count': periods.length,
      'estimate_produced': forecast.hasEstimate,
      'abstention_reason': forecast.abstentionReason?.name,
      'confidence': forecast.confidence.name,
      'regularity': forecast.regularity.name,
      'sample_size': forecast.sampleSize,
      'variability_days': forecast.variabilityDays,
      'uncertainty_days': forecast.uncertaintyDays,
      'backtest_predictions': metrics.predictionCount,
      'mae_days': metrics.maeDays,
      'within_1_day': metrics.withinOneDayRate,
      'within_2_days': metrics.withinTwoDaysRate,
      'within_3_days': metrics.withinThreeDaysRate,
      'mean_bias_days': metrics.meanBiasDays,
      'mae_by_confidence': {
        for (final item in metrics.maeByConfidence.entries)
          item.key.name: item.value,
      },
    };
  }
  output['summary'] = {
    'scenario_count': scenarios.length,
    'total_walk_forward_predictions': totalPredictions,
    'abstention_count': abstentions,
    'historical_mae_by_final_confidence': {
      for (final entry in calibration.entries)
        entry.key.name:
            entry.value.reduce((a, b) => a + b) / entry.value.length,
    },
  };
  // Benchmark CLI output is the report consumed by certification.
  // ignore: avoid_print
  print(const JsonEncoder.withIndent('  ').convert(output));
}

List<CyclePeriod> _periods(List<int> intervals) {
  var current = DateTime.utc(2020, 1, 1);
  final result = <CyclePeriod>[CyclePeriod(startsOn: current)];
  for (final interval in intervals) {
    current = current.add(Duration(days: interval));
    result.add(CyclePeriod(startsOn: current));
  }
  return result;
}
