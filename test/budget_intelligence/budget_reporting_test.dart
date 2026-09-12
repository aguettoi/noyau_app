import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/budget_intelligence/application/budget_reporting.dart';

void main() {
  const january = BudgetEnvelopeMetrics(
    plannedCents: 200000,
    consumptionCents: 150000,
    inflowsCents: 200000,
    outflowsCents: 150000,
    balanceCents: 50000,
  );
  const february = BudgetEnvelopeMetrics(
    plannedCents: 200000,
    consumptionCents: 225000,
    inflowsCents: 200000,
    outflowsCents: 225000,
    balanceCents: -25000,
  );

  test('monthly exposes plan, actual, variance, and overspend', () {
    expect(january.varianceCents, 50000);
    expect(january.consumptionRate, .75);
    expect(february.isOverspent, isTrue);
  });

  test('YTD aggregates multiple months as flows', () {
    const march = BudgetEnvelopeMetrics(
      plannedCents: 100000,
      consumptionCents: 50000,
      inflowsCents: 100000,
      outflowsCents: 50000,
      balanceCents: 50000,
    );
    final ytd = BudgetReporting.aggregate([january, february, march]);
    expect(ytd.plannedCents, 500000);
    expect(ytd.consumptionCents, 425000);
    expect(ytd.inflowsCents, 500000);
    expect(ytd.outflowsCents, 425000);
    expect(ytd.balanceCents, 75000);
  });

  test('LTD retains a negative position across years', () {
    const priorYear = BudgetEnvelopeMetrics(
      plannedCents: 0,
      consumptionCents: 0,
      inflowsCents: 0,
      outflowsCents: 40000,
      balanceCents: -40000,
    );
    final ltd = BudgetReporting.aggregate([priorYear, january]);
    expect(ltd.balanceCents, 10000);
    expect(ltd.isOverspent, isTrue);
  });
}
