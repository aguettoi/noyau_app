import 'dart:math' as math;

class CyclePeriod {
  const CyclePeriod({required this.startsOn, this.endsOn});
  final DateTime startsOn;
  final DateTime? endsOn;
  int? get bleedingDays =>
      endsOn == null ? null : endsOn!.difference(startsOn).inDays.abs() + 1;
}

enum CycleConfidence { insufficient, low, medium, high }

enum CycleRegularity { insufficient, regular, variable, irregular }

enum CycleAbstentionReason {
  insufficientHistory,
  incoherentHistory,
  excessiveVariability,
}

enum CycleProjectionKind { observation, forecast }

/// Privacy-minimized Cycle projection. It cannot carry intimate journal data.
class AuthorizedCycleProjection {
  const AuthorizedCycleProjection({
    required this.key,
    required this.ownerUserId,
    required this.startsOn,
    required this.phase,
    required this.kind,
    this.endsOn,
    this.confidence,
    this.engineVersion,
    this.sampleSize,
    this.variabilityDays,
    this.uncertaintyDays,
    this.regularity,
  });
  final String key;
  final String ownerUserId;
  final DateTime startsOn;
  final DateTime? endsOn;
  final String phase;
  final CycleProjectionKind kind;
  final CycleConfidence? confidence;
  final String? engineVersion;
  final int? sampleSize;
  final int? variabilityDays;
  final int? uncertaintyDays;
  final CycleRegularity? regularity;
  bool get isEstimate => kind == CycleProjectionKind.forecast;
}

/// Explainable, non-medical estimate derived only from the owner's history.
class CycleForecast {
  const CycleForecast({
    required this.engineVersion,
    required this.confidence,
    required this.regularity,
    required this.sampleSize,
    required this.historyCount,
    required this.averageCycleDays,
    required this.variabilityDays,
    required this.uncertaintyDays,
    required this.nextPeriodFrom,
    required this.nextPeriodTo,
    required this.estimatedOvulationFrom,
    required this.estimatedOvulationTo,
    required this.estimatedFertileWindowFrom,
    required this.estimatedFertileWindowTo,
    this.abstentionReason,
    this.historicalMaeDays,
  });
  final String engineVersion;
  final CycleConfidence confidence;
  final CycleRegularity regularity;
  final int sampleSize;
  final int historyCount;
  final int? averageCycleDays;
  final int? variabilityDays;
  final int? uncertaintyDays;
  final DateTime? nextPeriodFrom;
  final DateTime? nextPeriodTo;
  final DateTime? estimatedOvulationFrom;
  final DateTime? estimatedOvulationTo;
  final DateTime? estimatedFertileWindowFrom;
  final DateTime? estimatedFertileWindowTo;
  final CycleAbstentionReason? abstentionReason;
  final double? historicalMaeDays;
  bool get hasEstimate => nextPeriodFrom != null && nextPeriodTo != null;

  CycleForecast withCalibration(CycleConfidence value, double? mae) =>
      CycleForecast(
        engineVersion: engineVersion,
        confidence: value,
        regularity: regularity,
        sampleSize: sampleSize,
        historyCount: historyCount,
        averageCycleDays: averageCycleDays,
        variabilityDays: variabilityDays,
        uncertaintyDays: uncertaintyDays,
        nextPeriodFrom: nextPeriodFrom,
        nextPeriodTo: nextPeriodTo,
        estimatedOvulationFrom: estimatedOvulationFrom,
        estimatedOvulationTo: estimatedOvulationTo,
        estimatedFertileWindowFrom: estimatedFertileWindowFrom,
        estimatedFertileWindowTo: estimatedFertileWindowTo,
        abstentionReason: abstentionReason,
        historicalMaeDays: mae,
      );
}

class CycleBacktestPoint {
  const CycleBacktestPoint({
    required this.historyCount,
    required this.regularity,
    required this.confidence,
    required this.predictedOn,
    required this.observedOn,
  });
  final int historyCount;
  final CycleRegularity regularity;
  final CycleConfidence confidence;
  final DateTime predictedOn;
  final DateTime observedOn;
  int get signedErrorDays => predictedOn.difference(observedOn).inDays;
  int get absoluteErrorDays => signedErrorDays.abs();
}

class CycleBacktestReport {
  const CycleBacktestReport({
    required this.engineVersion,
    required this.points,
  });
  final String engineVersion;
  final List<CycleBacktestPoint> points;
  int get predictionCount => points.length;
  double? get maeDays => _mae(points);
  double? get meanBiasDays => points.isEmpty
      ? null
      : points.fold<int>(0, (sum, item) => sum + item.signedErrorDays) /
            points.length;
  double withinDaysRate(int days) => points.isEmpty
      ? 0
      : points.where((item) => item.absoluteErrorDays <= days).length /
            points.length;
  Map<String, double?> get maeByHistoryBucket => {
    'minimal': _mae(points.where((item) => item.historyCount <= 4)),
    'established': _mae(
      points.where((item) => item.historyCount >= 5 && item.historyCount <= 8),
    ),
    'long': _mae(points.where((item) => item.historyCount >= 9)),
  };
  Map<CycleRegularity, double?> get maeByRegularity => {
    for (final value in CycleRegularity.values)
      value: _mae(points.where((item) => item.regularity == value)),
  };
  Map<CycleConfidence, double?> get maeByConfidence => {
    for (final value in CycleConfidence.values)
      value: _mae(points.where((item) => item.confidence == value)),
  };
  List<int> get errorEvolution => [
    for (final point in points) point.absoluteErrorDays,
  ];
  static double? _mae(Iterable<CycleBacktestPoint> values) {
    final list = values.toList(growable: false);
    if (list.isEmpty) return null;
    return list.fold<int>(0, (sum, item) => sum + item.absoluteErrorDays) /
        list.length;
  }
}

/// Quality metrics intentionally contain no raw dates or intimate observations.
class CycleQualityMetrics {
  const CycleQualityMetrics({
    required this.engineVersion,
    required this.predictionCount,
    required this.maeDays,
    required this.withinOneDayRate,
    required this.withinTwoDaysRate,
    required this.withinThreeDaysRate,
    required this.meanBiasDays,
    required this.maeByConfidence,
  });
  factory CycleQualityMetrics.fromBacktest(CycleBacktestReport report) =>
      CycleQualityMetrics(
        engineVersion: report.engineVersion,
        predictionCount: report.predictionCount,
        maeDays: report.maeDays,
        withinOneDayRate: report.withinDaysRate(1),
        withinTwoDaysRate: report.withinDaysRate(2),
        withinThreeDaysRate: report.withinDaysRate(3),
        meanBiasDays: report.meanBiasDays,
        maeByConfidence: report.maeByConfidence,
      );
  final String engineVersion;
  final int predictionCount;
  final double? maeDays;
  final double withinOneDayRate;
  final double withinTwoDaysRate;
  final double withinThreeDaysRate;
  final double? meanBiasDays;
  final Map<CycleConfidence, double?> maeByConfidence;
}

class CycleForecastEngine {
  const CycleForecastEngine._();
  static const version = 'cycle-v2.0.0';
  static const _minimumIntervalDays = 15;
  static const _maximumIntervalDays = 90;
  static const _maximumRecentIntervals = 8;

  static CycleForecast estimate(List<CyclePeriod> observations) {
    final normalized = _normalized(observations);
    final raw = _estimateCore(normalized);
    if (!raw.hasEstimate) return raw;
    final report = backtest(normalized);
    var confidence = raw.confidence;
    final mae = report.maeDays;
    if (report.predictionCount >= 3 && mae != null) {
      final withinThree = report.withinDaysRate(3);
      if (confidence == CycleConfidence.high &&
          mae <= 2 &&
          withinThree >= 0.8) {
        confidence = CycleConfidence.high;
      } else if (confidence != CycleConfidence.low &&
          mae <= 4 &&
          withinThree >= 0.6) {
        confidence = CycleConfidence.medium;
      } else {
        confidence = CycleConfidence.low;
      }
    } else if (report.predictionCount >= 2 && mae != null && mae > 7) {
      confidence = CycleConfidence.low;
    }
    return raw.withCalibration(confidence, mae);
  }

  /// Walk-forward validation: each prediction uses only earlier observations.
  static CycleBacktestReport backtest(List<CyclePeriod> observations) {
    final normalized = _normalized(observations);
    final points = <CycleBacktestPoint>[];
    for (var target = 3; target < normalized.length; target++) {
      final history = normalized.sublist(0, target);
      final forecast = _estimateCore(history);
      if (!forecast.hasEstimate) continue;
      points.add(
        CycleBacktestPoint(
          historyCount: history.length,
          regularity: forecast.regularity,
          confidence: forecast.confidence,
          predictedOn: _midpoint(
            forecast.nextPeriodFrom!,
            forecast.nextPeriodTo!,
          ),
          observedOn: normalized[target].startsOn,
        ),
      );
    }
    return CycleBacktestReport(
      engineVersion: version,
      points: List.unmodifiable(points),
    );
  }

  static CycleForecast _estimateCore(List<CyclePeriod> periods) {
    if (periods.length < 3) {
      return _abstain(
        periods.length,
        CycleAbstentionReason.insufficientHistory,
      );
    }
    final all = <int>[];
    final valid = <int>[];
    for (var i = 1; i < periods.length; i++) {
      final days = periods[i].startsOn
          .difference(periods[i - 1].startsOn)
          .inDays;
      all.add(days);
      if (days >= _minimumIntervalDays && days <= _maximumIntervalDays) {
        valid.add(days);
      }
    }
    final invalid = all.length - valid.length;
    if (valid.length < 2 || invalid > math.max(1, all.length ~/ 3)) {
      return _abstain(
        periods.length,
        CycleAbstentionReason.incoherentHistory,
        sampleSize: valid.length,
      );
    }
    final recent = valid.length <= _maximumRecentIntervals
        ? valid
        : valid.sublist(valid.length - _maximumRecentIntervals);
    final sorted = [...recent]..sort();
    final average = (sorted.reduce((a, b) => a + b) / sorted.length).round();
    final variance =
        sorted
            .map((days) => math.pow(days - average, 2))
            .reduce((a, b) => a + b) /
        sorted.length;
    final variability = math.sqrt(variance).ceil();
    final range = sorted.last - sorted.first;
    final regularity = switch (variability) {
      <= 3 => CycleRegularity.regular,
      <= 7 => CycleRegularity.variable,
      _ => CycleRegularity.irregular,
    };
    if (variability > 14 || range > 30) {
      return _abstain(
        periods.length,
        CycleAbstentionReason.excessiveVariability,
        sampleSize: recent.length,
        variabilityDays: variability,
        regularity: regularity,
      );
    }
    final confidence = switch ((recent.length, variability)) {
      (>= 5, <= 3) => CycleConfidence.high,
      (>= 3, <= 7) => CycleConfidence.medium,
      _ => CycleConfidence.low,
    };
    final uncertainty = math.max(
      2,
      variability + (confidence == CycleConfidence.low ? 2 : 0),
    );
    final nextCenter = periods.last.startsOn.add(Duration(days: average));
    final ovulationCenter = nextCenter.subtract(const Duration(days: 14));
    return CycleForecast(
      engineVersion: version,
      confidence: confidence,
      regularity: regularity,
      sampleSize: recent.length,
      historyCount: periods.length,
      averageCycleDays: average,
      variabilityDays: variability,
      uncertaintyDays: uncertainty,
      nextPeriodFrom: nextCenter.subtract(Duration(days: uncertainty)),
      nextPeriodTo: nextCenter.add(Duration(days: uncertainty)),
      estimatedOvulationFrom: ovulationCenter.subtract(
        Duration(days: uncertainty + 1),
      ),
      estimatedOvulationTo: ovulationCenter.add(
        Duration(days: uncertainty + 1),
      ),
      estimatedFertileWindowFrom: ovulationCenter.subtract(
        Duration(days: uncertainty + 5),
      ),
      estimatedFertileWindowTo: ovulationCenter.add(
        Duration(days: uncertainty + 1),
      ),
    );
  }

  static CycleForecast _abstain(
    int historyCount,
    CycleAbstentionReason reason, {
    int sampleSize = 0,
    int? variabilityDays,
    CycleRegularity regularity = CycleRegularity.insufficient,
  }) => CycleForecast(
    engineVersion: version,
    confidence: CycleConfidence.insufficient,
    regularity: regularity,
    sampleSize: sampleSize,
    historyCount: historyCount,
    averageCycleDays: null,
    variabilityDays: variabilityDays,
    uncertaintyDays: null,
    nextPeriodFrom: null,
    nextPeriodTo: null,
    estimatedOvulationFrom: null,
    estimatedOvulationTo: null,
    estimatedFertileWindowFrom: null,
    estimatedFertileWindowTo: null,
    abstentionReason: reason,
  );

  static List<CyclePeriod> _normalized(List<CyclePeriod> observations) {
    final byDay = <String, CyclePeriod>{};
    for (final item in observations) {
      final day = DateTime.utc(
        item.startsOn.year,
        item.startsOn.month,
        item.startsOn.day,
      );
      byDay[day.toIso8601String()] = CyclePeriod(
        startsOn: day,
        endsOn: item.endsOn,
      );
    }
    final result = byDay.values.toList()
      ..sort((a, b) => a.startsOn.compareTo(b.startsOn));
    return result;
  }

  static DateTime _midpoint(DateTime from, DateTime to) =>
      from.add(Duration(milliseconds: to.difference(from).inMilliseconds ~/ 2));
}

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
  'basal_temperature',
  'lh_test',
  'weight',
  'spotting',
  'contraception',
  'intimacy',
};
