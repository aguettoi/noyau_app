import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/budget_intelligence/application/providers/remote_budget_provider.dart';
import 'package:noyau_app/features/cashflow_projection/application/cashflow_projection_provider.dart';
import 'package:noyau_app/features/cashflow_projection/domain/cashflow_projection.dart';
import 'package:noyau_app/features/cashflow_projection/presentation/cashflow_projection_page.dart';
import 'package:noyau_app/features/envelopes/application/providers/remote_envelopes_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_accounts_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_household_members_provider.dart';
import 'package:noyau_app/features/finance/domain/financial_account.dart';
import 'package:noyau_app/features/finance/domain/household_member.dart';

void main() {
  testWidgets('projection is explainable and responsive', (tester) async {
    await initializeDateFormatting('fr');
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final projection = CashflowProjection(
      asOf: DateTime(2026, 11, 1),
      through: DateTime(2026, 11, 30),
      currentHouseholdBalance: const Money.fromMinorUnits(100000),
      projectedHouseholdBalance: const Money.fromMinorUnits(90000),
      accountBalances: const {'a': Money.fromMinorUnits(100000)},
      projectedAccountBalances: const {'a': Money.fromMinorUnits(90000)},
      envelopeBalances: const {'e': Money.fromMinorUnits(20000)},
      projectedEnvelopeBalances: const {'e': Money.fromMinorUnits(10000)},
      memberDeltas: const {'m': Money.fromMinorUnits(-10000)},
      flows: [
        ProjectionFlow(
          id: 'f',
          date: DateTime(2026, 11, 10),
          label: 'Dépense attendue',
          amount: const Money.fromMinorUnits(10000),
          kind: ProjectionFlowKind.expense,
          certainty: ProjectionCertainty.certain,
          source: 'R3.1 — opération attendue',
          sourceAccountId: 'a',
          envelopeId: 'e',
          memberId: 'm',
        ),
      ],
      risks: const [],
      unlocatedAmount: const Money.fromMinorUnits(0),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cashflowProjectionProvider.overrideWith((_) async => projection),
          remoteAccountsProvider.overrideWith(
            (_) async => [
              FinancialAccount(
                id: 'a',
                name: 'Compte A',
                type: FinancialAccountType.bank,
                openingBalance: const Money.fromMinorUnits(0),
              ),
            ],
          ),
          remoteEnvelopeBalancesProvider.overrideWith(
            (_) async => const [
              RemoteEnvelopeBalance(
                id: 'e',
                name: 'Enveloppe A',
                inflows: Money.fromMinorUnits(0),
                outflows: Money.fromMinorUnits(0),
                balance: Money.fromMinorUnits(20000),
                isSystem: false,
              ),
            ],
          ),
          remoteHouseholdMembersProvider.overrideWith(
            (_) async => const [
              HouseholdMember(id: 'm', displayName: 'Membre A'),
            ],
          ),
          remoteBudgetScenariosProvider.overrideWith((_) async => const []),
        ],
        child: const MaterialApp(home: CashflowProjectionPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Prévisions de trésorerie'), findsOneWidget);
    expect(find.text('Vue foyer'), findsOneWidget);
    expect(find.byKey(const Key('cashflow-horizon')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Chronologie et explications'),
      300,
    );
    await tester.tap(find.text('Chronologie et explications'));
    await tester.pumpAndSettle();
    expect(find.text('Dépense attendue'), findsOneWidget);
    expect(find.textContaining('R3.1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
