import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/organization/domain/cycle_tracking.dart';

void main() {
  group('CycleForecastEngine v2', () {
    test(
      'abstains when history is insufficient instead of inventing a date',
      () {
        final forecast = CycleForecastEngine.estimate(_periods([28]));
        expect(forecast.engineVersion, CycleForecastEngine.version);
        expect(forecast.hasEstimate, isFalse);
        expect(forecast.confidence, CycleConfidence.insufficient);
        expect(
          forecast.abstentionReason,
          CycleAbstentionReason.insufficientHistory,
        );
        expect(forecast.nextPeriodFrom, isNull);
        expect(forecast.estimatedOvulationFrom, isNull);
      },
    );

    test('regular history produces an explainable bounded estimate', () {
      final forecast = CycleForecastEngine.estimate(
        _periods([28, 28, 28, 28, 28, 28, 28]),
      );
      expect(forecast.hasEstimate, isTrue);
      expect(forecast.averageCycleDays, 28);
      expect(forecast.variabilityDays, 0);
      expect(forecast.uncertaintyDays, 2);
      expect(forecast.regularity, CycleRegularity.regular);
      expect(forecast.confidence, CycleConfidence.high);
      expect(forecast.sampleSize, 7);
      expect(forecast.historyCount, 8);
      expect(forecast.estimatedFertileWindowFrom, isNotNull);
      expect(forecast.estimatedFertileWindowTo, isNotNull);
    });

    test('unstable history explicitly abstains', () {
      final forecast = CycleForecastEngine.estimate(
        _periods([18, 55, 20, 60, 17]),
      );
      expect(forecast.hasEstimate, isFalse);
      expect(
        forecast.abstentionReason,
        CycleAbstentionReason.excessiveVariability,
      );
      expect(forecast.confidence, CycleConfidence.insufficient);
    });

    test('incoherent and duplicate observations never become defaults', () {
      final forecast = CycleForecastEngine.estimate([
        CyclePeriod(startsOn: _day0),
        CyclePeriod(startsOn: _day0),
        CyclePeriod(startsOn: _day0.add(const Duration(days: 7))),
        CyclePeriod(startsOn: _day0.add(const Duration(days: 150))),
      ]);
      expect(forecast.hasEstimate, isFalse);
      expect(
        forecast.abstentionReason,
        CycleAbstentionReason.incoherentHistory,
      );
    });

    test(
      'a possible missing cycle widens confidence without false certainty',
      () {
        final forecast = CycleForecastEngine.estimate(
          _periods([28, 56, 28, 29, 27]),
        );
        expect(forecast.hasEstimate, isTrue);
        expect(forecast.confidence, isNot(CycleConfidence.high));
        expect(forecast.uncertaintyDays, greaterThanOrEqualTo(7));
      },
    );

    test('synthetic corpus covers short, long and progressive histories', () {
      final corpus = <String, CycleForecast>{
        'short_regular': CycleForecastEngine.estimate(
          _periods([21, 21, 22, 21, 21, 22]),
        ),
        'long_regular': CycleForecastEngine.estimate(
          _periods([40, 40, 39, 40, 41, 40, 40, 39, 40, 41]),
        ),
        'progressive_shortening': CycleForecastEngine.estimate(
          _periods([34, 32, 30, 28, 26, 24]),
        ),
        'progressive_lengthening': CycleForecastEngine.estimate(
          _periods([24, 26, 28, 30, 32, 34]),
        ),
      };
      expect(
        corpus.values,
        everyElement(predicate<CycleForecast>((f) => f.hasEstimate)),
      );
      expect(
        corpus['short_regular']!.averageCycleDays,
        inInclusiveRange(21, 22),
      );
      expect(corpus['long_regular']!.historyCount, greaterThanOrEqualTo(10));
      expect(corpus['progressive_shortening']!.uncertaintyDays, greaterThan(2));
      expect(
        corpus['progressive_lengthening']!.confidence,
        isNot(CycleConfidence.high),
      );
    });

    test('outliers and implausible gaps trigger abstention', () {
      final outlier = CycleForecastEngine.estimate(
        _periods([28, 28, 90, 28, 28]),
      );
      final incoherent = CycleForecastEngine.estimate(
        _periods([7, 120, 8, 140]),
      );
      expect(outlier.hasEstimate, isFalse);
      expect(incoherent.hasEstimate, isFalse);
    });
  });

  group('temporal backtesting', () {
    test('walk-forward benchmark reports all required metrics', () {
      final report = CycleForecastEngine.backtest(
        _periods(List<int>.filled(11, 28)),
      );
      expect(report.engineVersion, CycleForecastEngine.version);
      expect(report.predictionCount, 9);
      expect(report.maeDays, 0);
      expect(report.withinDaysRate(1), 1);
      expect(report.withinDaysRate(2), 1);
      expect(report.withinDaysRate(3), 1);
      expect(report.meanBiasDays, 0);
      expect(report.maeByHistoryBucket['minimal'], 0);
      expect(report.maeByHistoryBucket['long'], 0);
      expect(report.errorEvolution, everyElement(0));
    });

    test('future observations cannot alter earlier historical predictions', () {
      final base = CycleForecastEngine.backtest(
        _periods([28, 29, 27, 28, 30, 27]),
      );
      final changedFuture = CycleForecastEngine.backtest(
        _periods([28, 29, 27, 28, 30, 27, 44]),
      );
      expect(
        changedFuture.points.take(base.points.length).map(_signature),
        orderedEquals(base.points.map(_signature)),
      );
    });

    test('confidence calibration is evaluated against synthetic outcomes', () {
      final high = _oneStepError(
        history: [28, 28, 28, 28, 28, 28],
        actualNextInterval: 28,
      );
      final medium = _oneStepError(
        history: [25, 31, 26, 30],
        actualNextInterval: 31,
      );
      final low = _oneStepError(history: [20, 36], actualNextInterval: 38);
      expect(high.$1, CycleConfidence.high);
      expect(medium.$1, CycleConfidence.medium);
      expect(low.$1, CycleConfidence.low);
      expect(high.$2, lessThanOrEqualTo(medium.$2));
      expect(medium.$2, lessThanOrEqualTo(low.$2));
    });

    test('quality snapshot contains metrics but no raw Cycle dates', () {
      final metrics = CycleQualityMetrics.fromBacktest(
        CycleForecastEngine.backtest(_periods(List<int>.filled(8, 30))),
      );
      expect(metrics.predictionCount, greaterThan(0));
      expect(metrics.maeDays, 0);
      expect(metrics.withinThreeDaysRate, 1);
      expect(metrics.toString(), isNot(contains('2026-')));
    });
  });
}

final _day0 = DateTime.utc(2026, 1, 1);

List<CyclePeriod> _periods(List<int> intervals) {
  var current = _day0;
  final result = <CyclePeriod>[CyclePeriod(startsOn: current)];
  for (final interval in intervals) {
    current = current.add(Duration(days: interval));
    result.add(CyclePeriod(startsOn: current));
  }
  return result;
}

String _signature(CycleBacktestPoint point) =>
    '${point.historyCount}:${point.predictedOn.toIso8601String()}:'
    '${point.observedOn.toIso8601String()}';

(CycleConfidence, int) _oneStepError({
  required List<int> history,
  required int actualNextInterval,
}) {
  final observations = _periods(history);
  final forecast = CycleForecastEngine.estimate(observations);
  final midpoint = forecast.nextPeriodFrom!.add(
    Duration(
      milliseconds:
          forecast.nextPeriodTo!
              .difference(forecast.nextPeriodFrom!)
              .inMilliseconds ~/
          2,
    ),
  );
  final actual = observations.last.startsOn.add(
    Duration(days: actualNextInterval),
  );
  return (forecast.confidence, midpoint.difference(actual).inDays.abs());
}
