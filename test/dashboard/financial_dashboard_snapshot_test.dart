import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/dashboard/application/dashboard_metrics.dart';
import 'package:noyau_app/features/dashboard/application/providers/remote_financial_dashboard_provider.dart';
import 'package:noyau_app/features/envelopes/application/providers/remote_envelopes_provider.dart';
import 'package:noyau_app/features/finance/domain/financial_account.dart';

void main() {
  FinancialDashboardSnapshot snapshot({
    List<DashboardAccountBalance> accounts = const [],
    List<RemoteEnvelopeBalance> envelopes = const [],
    RemoteEnvelopeBalance? toAllocate,
  }) => FinancialDashboardSnapshot(
    accounts: accounts,
    ordinaryEnvelopes: envelopes,
    toAllocate: toAllocate,
    budget: const DashboardBudgetSummary(
      period: null,
      planned: Money.fromMinorUnits(0),
      consumed: Money.fromMinorUnits(0),
      overspentEnvelopeIds: {},
    ),
    monthlyFlow: const DashboardMonthlyFlow(
      income: Money.fromMinorUnits(0),
      expense: Money.fromMinorUnits(0),
    ),
    debts: const [],
    incomeReceivables: const [],
    recoveryReceivables: const [],
    activeGoals: const [],
    nextPriority: null,
    alerts: const [],
  );

  test('treasury is the account ledger only and keeps cash separate', () {
    final result = snapshot(
      accounts: [
        DashboardAccountBalance(
          account: FinancialAccount(
            id: 'bank',
            name: 'Banque',
            type: FinancialAccountType.bank,
            openingBalance: const Money.fromMinorUnits(0),
          ),
          balance: const Money.fromMinorUnits(100000),
        ),
        DashboardAccountBalance(
          account: FinancialAccount(
            id: 'cash',
            name: 'Caisse',
            type: FinancialAccountType.cash,
            openingBalance: const Money.fromMinorUnits(0),
          ),
          balance: const Money.fromMinorUnits(20000),
        ),
      ],
      envelopes: [_envelope('food', 'Nourriture', 50000)],
      toAllocate: _systemEnvelope('to_allocate', 'À répartir', 10000),
    );

    expect(result.cashTotal, const Money.fromMinorUnits(120000));
    expect(result.cashOnHand, const Money.fromMinorUnits(20000));
    expect(result.ordinaryEnvelopeTotal, const Money.fromMinorUnits(50000));
    expect(result.cashTotal, isNot(const Money.fromMinorUnits(180000)));
  });

  test('to allocate remains separate from ordinary envelopes', () {
    final result = snapshot(
      envelopes: [_envelope('travel', 'Voyages', 30000)],
      toAllocate: _systemEnvelope('allocate', 'À répartir', 2500),
    );

    expect(result.ordinaryEnvelopeTotal, const Money.fromMinorUnits(30000));
    expect(result.toAllocate!.balance, const Money.fromMinorUnits(2500));
  });
}

RemoteEnvelopeBalance _envelope(String id, String name, int cents) =>
    RemoteEnvelopeBalance(
      id: id,
      name: name,
      inflows: Money.fromMinorUnits(cents),
      outflows: const Money.fromMinorUnits(0),
      balance: Money.fromMinorUnits(cents),
      isSystem: false,
    );

RemoteEnvelopeBalance _systemEnvelope(String id, String name, int cents) =>
    RemoteEnvelopeBalance(
      id: id,
      name: name,
      inflows: Money.fromMinorUnits(cents),
      outflows: const Money.fromMinorUnits(0),
      balance: Money.fromMinorUnits(cents),
      isSystem: true,
      systemCode: 'to_allocate',
    );
