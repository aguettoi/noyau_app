import 'dart:math' as math;

import '../../../core/money/money.dart';

enum WealthAssetType { realEstate, vehicle, other }

enum WealthOwnershipType { household, individual, shared }

enum FinancingStructure { interestLoan, murabaha, fixedCost, other }

enum EarlyRepaymentStrategy { reduceDuration, reducePayment }

class WealthAsset {
  const WealthAsset({
    required this.id,
    required this.label,
    required this.type,
    required this.ownershipType,
    required this.currentValue,
    this.acquisitionValue = const Money.fromMinorUnits(0),
    this.valuationDate,
  });
  final String id;
  final String label;
  final WealthAssetType type;
  final WealthOwnershipType ownershipType;
  final Money currentValue;
  final Money acquisitionValue;
  final DateTime? valuationDate;
}

class InvestmentPosition {
  const InvestmentPosition({
    required this.id,
    required this.label,
    required this.currentValue,
    required this.contributed,
    required this.withdrawn,
    required this.distributions,
    required this.taxes,
    this.backingAccountId,
  });
  final String id;
  final String label;
  final String? backingAccountId;
  final Money currentValue;
  final Money contributed;
  final Money withdrawn;
  final Money distributions;
  final Money taxes;

  Money get netCapital => contributed - withdrawn;
  Money get netGain =>
      currentValue + withdrawn + distributions - contributed - taxes;
}

class FinancingProfile {
  const FinancingProfile({
    required this.id,
    required this.label,
    required this.structure,
    required this.obligationId,
    required this.principalInitial,
    required this.remainingLiability,
    required this.startDate,
    required this.durationMonths,
    required this.periodicityMonths,
    this.annualRate,
    this.fixedTotalCost,
    this.scheduledPayment,
    this.assetId,
  });
  final String id;
  final String label;
  final FinancingStructure structure;
  final String obligationId;
  final String? assetId;
  final Money principalInitial;
  final Money remainingLiability;
  final DateTime startDate;
  final int durationMonths;
  final int periodicityMonths;
  final double? annualRate;
  final Money? fixedTotalCost;
  final Money? scheduledPayment;
}

class WealthSnapshot {
  const WealthSnapshot({
    required this.liquidity,
    required this.investments,
    required this.assets,
    required this.liabilities,
  });
  final Money liquidity;
  final Money investments;
  final Money assets;
  final Money liabilities;
  Money get totalAssets => liquidity + investments + assets;
  Money get netWorth => totalAssets - liabilities;
}

WealthSnapshot calculateWealthSnapshot({
  required Iterable<Money> liquidAccountBalances,
  required Iterable<WealthAsset> assets,
  required Iterable<InvestmentPosition> investments,
  required Iterable<Money> liabilities,
}) {
  int sum(Iterable<Money> values) =>
      values.fold(0, (total, value) => total + value.minorUnits);
  return WealthSnapshot(
    liquidity: Money.fromMinorUnits(sum(liquidAccountBalances)),
    assets: Money.fromMinorUnits(sum(assets.map((item) => item.currentValue))),
    // An investment backed by an account is already included in liquidity.
    investments: Money.fromMinorUnits(
      sum(
        investments
            .where((item) => item.backingAccountId == null)
            .map((item) => item.currentValue),
      ),
    ),
    liabilities: Money.fromMinorUnits(sum(liabilities)),
  );
}

class InvestmentProjectionInput {
  const InvestmentProjectionInput({
    required this.initialCapital,
    required this.periodicContribution,
    required this.annualRate,
    required this.months,
    this.taxRate = 0,
    this.compound = true,
  });
  final Money initialCapital;
  final Money periodicContribution;
  final double annualRate;
  final double taxRate;
  final int months;
  final bool compound;
}

class InvestmentProjection {
  const InvestmentProjection({
    required this.capitalPaid,
    required this.grossGain,
    required this.tax,
    required this.netGain,
    required this.projectedValue,
  });
  final Money capitalPaid;
  final Money grossGain;
  final Money tax;
  final Money netGain;
  final Money projectedValue;
}

InvestmentProjection projectInvestment(InvestmentProjectionInput input) {
  if (input.months < 0 ||
      input.annualRate < 0 ||
      input.taxRate < 0 ||
      input.taxRate > 1) {
    throw ArgumentError('Paramètres de projection invalides.');
  }
  final monthlyRate = input.annualRate / 12;
  var value = input.initialCapital.dirhams;
  for (var month = 0; month < input.months; month++) {
    value = input.compound
        ? value * (1 + monthlyRate)
        : value + input.initialCapital.dirhams * monthlyRate;
    value += input.periodicContribution.dirhams;
  }
  final paid =
      input.initialCapital +
      Money.fromMinorUnits(
        input.periodicContribution.minorUnits * input.months,
      );
  final gross = Money.fromDirhams(math.max(0, value - paid.dirhams));
  final tax = Money.fromDirhams(gross.dirhams * input.taxRate);
  final net = gross - tax;
  return InvestmentProjection(
    capitalPaid: paid,
    grossGain: gross,
    tax: tax,
    netGain: net,
    projectedValue: paid + net,
  );
}

class FinancingScheduleLine {
  const FinancingScheduleLine({
    required this.number,
    required this.date,
    required this.payment,
    required this.principal,
    required this.cost,
    required this.remaining,
  });
  final int number;
  final DateTime date;
  final Money payment;
  final Money principal;
  final Money cost;
  final Money remaining;
}

List<FinancingScheduleLine> buildFinancingSchedule(FinancingProfile profile) {
  var remaining = profile.remainingLiability.dirhams;
  if (remaining <= 0) return const [];
  final count = (profile.durationMonths / profile.periodicityMonths).ceil();
  final rate = profile.structure == FinancingStructure.interestLoan
      ? (profile.annualRate ?? 0) * profile.periodicityMonths / 12
      : 0.0;
  final fixedCost = (profile.fixedTotalCost?.dirhams ?? 0) / count;
  final computedPayment = rate == 0
      ? (remaining + (profile.fixedTotalCost?.dirhams ?? 0)) / count
      : remaining * rate / (1 - math.pow(1 + rate, -count));
  final payment = profile.scheduledPayment?.dirhams ?? computedPayment;
  final result = <FinancingScheduleLine>[];
  for (var index = 1; index <= count && remaining > 0.005; index++) {
    final cost = profile.structure == FinancingStructure.interestLoan
        ? remaining * rate
        : fixedCost;
    final principal = math.min(remaining, math.max(0, payment - cost));
    remaining = math.max(0, remaining - principal);
    result.add(
      FinancingScheduleLine(
        number: index,
        date: DateTime(
          profile.startDate.year,
          profile.startDate.month + index * profile.periodicityMonths,
          profile.startDate.day,
        ),
        payment: Money.fromDirhams(principal + cost),
        principal: Money.fromDirhams(principal),
        cost: Money.fromDirhams(cost),
        remaining: Money.fromDirhams(remaining),
      ),
    );
  }
  return List.unmodifiable(result);
}

class EarlyRepaymentProjection {
  const EarlyRepaymentProjection({
    required this.remainingAfter,
    required this.remainingMonths,
    required this.newPayment,
    required this.estimatedCostSaving,
  });
  final Money remainingAfter;
  final int remainingMonths;
  final Money newPayment;
  final Money estimatedCostSaving;
}

EarlyRepaymentProjection projectEarlyRepayment(
  FinancingProfile profile,
  Money amount,
  EarlyRepaymentStrategy strategy,
) {
  if (amount.minorUnits <= 0 ||
      amount.minorUnits > profile.remainingLiability.minorUnits) {
    throw ArgumentError('Montant anticipé invalide.');
  }
  final before = buildFinancingSchedule(profile);
  final remaining = profile.remainingLiability - amount;
  final oldPayment = before.isEmpty
      ? const Money.fromMinorUnits(0)
      : before.first.payment;
  FinancingProfile revised;
  if (strategy == EarlyRepaymentStrategy.reduceDuration) {
    revised = FinancingProfile(
      id: profile.id,
      label: profile.label,
      structure: profile.structure,
      obligationId: profile.obligationId,
      principalInitial: profile.principalInitial,
      remainingLiability: remaining,
      startDate: profile.startDate,
      durationMonths: profile.durationMonths,
      periodicityMonths: profile.periodicityMonths,
      annualRate: profile.annualRate,
      fixedTotalCost: profile.fixedTotalCost,
      scheduledPayment: oldPayment,
      assetId: profile.assetId,
    );
  } else {
    revised = FinancingProfile(
      id: profile.id,
      label: profile.label,
      structure: profile.structure,
      obligationId: profile.obligationId,
      principalInitial: profile.principalInitial,
      remainingLiability: remaining,
      startDate: profile.startDate,
      durationMonths: profile.durationMonths,
      periodicityMonths: profile.periodicityMonths,
      annualRate: profile.annualRate,
      fixedTotalCost: profile.fixedTotalCost,
      assetId: profile.assetId,
    );
  }
  final after = buildFinancingSchedule(revised);
  int costs(List<FinancingScheduleLine> lines) =>
      lines.fold(0, (sum, line) => sum + line.cost.minorUnits);
  return EarlyRepaymentProjection(
    remainingAfter: remaining,
    remainingMonths: after.length * profile.periodicityMonths,
    newPayment: after.isEmpty
        ? const Money.fromMinorUnits(0)
        : after.first.payment,
    estimatedCostSaving: Money.fromMinorUnits(
      math.max(0, costs(before) - costs(after)),
    ),
  );
}
