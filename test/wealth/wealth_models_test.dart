import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/wealth/domain/wealth_models.dart';

void main() {
  test('patrimoine vide et valeur nette sans double comptage', () {
    final empty = calculateWealthSnapshot(
      liquidAccountBalances: const [],
      assets: const [],
      investments: const [],
      liabilities: const [],
    );
    expect(empty.netWorth.minorUnits, 0);
    final snapshot = calculateWealthSnapshot(
      liquidAccountBalances: const [Money.fromMinorUnits(100000)],
      assets: const [
        WealthAsset(
          id: 'a',
          label: 'Actif',
          type: WealthAssetType.other,
          ownershipType: WealthOwnershipType.household,
          currentValue: Money.fromMinorUnits(500000),
        ),
      ],
      investments: const [
        InvestmentPosition(
          id: 'linked',
          label: 'Lié',
          backingAccountId: 'account',
          currentValue: Money.fromMinorUnits(100000),
          contributed: Money.fromMinorUnits(100000),
          withdrawn: Money.fromMinorUnits(0),
          distributions: Money.fromMinorUnits(0),
          taxes: Money.fromMinorUnits(0),
        ),
        InvestmentPosition(
          id: 'free',
          label: 'Libre',
          currentValue: Money.fromMinorUnits(200000),
          contributed: Money.fromMinorUnits(150000),
          withdrawn: Money.fromMinorUnits(0),
          distributions: Money.fromMinorUnits(0),
          taxes: Money.fromMinorUnits(0),
        ),
      ],
      liabilities: const [Money.fromMinorUnits(250000)],
    );
    expect(snapshot.totalAssets.minorUnits, 800000);
    expect(snapshot.netWorth.minorUnits, 550000);
  });

  test('projection investissement sépare brut retenue net', () {
    final result = projectInvestment(
      const InvestmentProjectionInput(
        initialCapital: Money.fromMinorUnits(1000000),
        periodicContribution: Money.fromMinorUnits(10000),
        annualRate: .06,
        taxRate: .30,
        months: 12,
      ),
    );
    expect(result.capitalPaid.minorUnits, 1120000);
    expect(result.grossGain.minorUnits, greaterThan(0));
    expect(result.tax.minorUnits, greaterThan(0));
    expect(result.netGain, result.grossGain - result.tax);
    expect(result.projectedValue, result.capitalPaid + result.netGain);
  });

  test('versements retraits distributions et retenues restent distincts', () {
    const position = InvestmentPosition(
      id: 'i',
      label: 'Placement',
      currentValue: Money.fromMinorUnits(125000),
      contributed: Money.fromMinorUnits(100000),
      withdrawn: Money.fromMinorUnits(10000),
      distributions: Money.fromMinorUnits(5000),
      taxes: Money.fromMinorUnits(1000),
    );
    expect(position.netCapital.minorUnits, 90000);
    expect(position.netGain.minorUnits, 39000);
  });

  test('échéancier, coût et capital restant sont cohérents', () {
    final profile = FinancingProfile(
      id: 'f',
      label: 'Test',
      structure: FinancingStructure.interestLoan,
      obligationId: 'o',
      principalInitial: const Money.fromMinorUnits(1200000),
      remainingLiability: const Money.fromMinorUnits(1200000),
      startDate: DateTime(2026, 1, 1),
      durationMonths: 12,
      periodicityMonths: 1,
      annualRate: .06,
    );
    final lines = buildFinancingSchedule(profile);
    expect(lines, hasLength(12));
    expect(lines.first.cost.minorUnits, greaterThan(0));
    expect(lines.last.remaining.minorUnits, closeTo(0, 1));
  });

  test('remboursement anticipé compare durée et échéance sans écriture', () {
    final profile = FinancingProfile(
      id: 'f',
      label: 'Test',
      structure: FinancingStructure.interestLoan,
      obligationId: 'o',
      principalInitial: const Money.fromMinorUnits(2400000),
      remainingLiability: const Money.fromMinorUnits(2400000),
      startDate: DateTime(2026, 1, 1),
      durationMonths: 24,
      periodicityMonths: 1,
      annualRate: .05,
    );
    final duration = projectEarlyRepayment(
      profile,
      const Money.fromMinorUnits(600000),
      EarlyRepaymentStrategy.reduceDuration,
    );
    final payment = projectEarlyRepayment(
      profile,
      const Money.fromMinorUnits(600000),
      EarlyRepaymentStrategy.reducePayment,
    );
    expect(duration.remainingAfter.minorUnits, 1800000);
    expect(duration.remainingMonths, lessThanOrEqualTo(24));
    expect(
      payment.newPayment.minorUnits,
      lessThan(buildFinancingSchedule(profile).first.payment.minorUnits),
    );
  });

  test('montant anticipé invalide est refusé', () {
    final profile = FinancingProfile(
      id: 'f',
      label: 'Test',
      structure: FinancingStructure.fixedCost,
      obligationId: 'o',
      principalInitial: const Money.fromMinorUnits(10000),
      remainingLiability: const Money.fromMinorUnits(10000),
      startDate: DateTime(2026),
      durationMonths: 10,
      periodicityMonths: 1,
    );
    expect(
      () => projectEarlyRepayment(
        profile,
        const Money.fromMinorUnits(20000),
        EarlyRepaymentStrategy.reduceDuration,
      ),
      throwsArgumentError,
    );
  });
}
