import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/finance/application/providers/account_balance_observation_provider.dart';
import 'package:noyau_app/features/finance/application/providers/active_household_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_account_balances_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_accounts_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_household_members_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_transactions_provider.dart';
import 'package:noyau_app/features/finance/domain/financial_account.dart';
import 'package:noyau_app/features/finance/presentation/accounts_page.dart';

void main() {
  testWidgets(
    'le rapprochement bancaire constate un écart sans correction GL',
    (tester) async {
      final gateway = _ObservationGateway();
      await _pump(tester, _bankAccount(), gateway);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Banque A'));
      await tester.pumpAndSettle();

      expect(find.text('Rapprochement bancaire'), findsOneWidget);
      expect(
        find.textContaining('Solde théorique GL : 900,00 MAD'),
        findsOneWidget,
      );
      expect(find.textContaining('Solde réel constaté : 1 000'), findsNothing);
      expect(find.textContaining('Écart : 100,00 MAD'), findsOneWidget);
      expect(find.text('État : Écart à expliquer'), findsOneWidget);
      expect(
        find.textContaining(
          'Aucun écart ne modifie le Grand Livre ni les enveloppes',
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('record-account-balance-observation-button')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('actual-account-balance-field')),
        '900',
      );
      await tester.enterText(
        find.byKey(const Key('account-balance-observation-reason-field')),
        'Relevé du 01/10',
      );
      await tester.tap(
        find.byKey(
          const Key('record-account-balance-observation-submit-button'),
        ),
      );
      await tester.pumpAndSettle();

      expect(gateway.recordedAccountId, 'bank-1');
      expect(gateway.recordedAmount, Money.fromMinorUnits(90000));
      expect(gateway.glMutationRequested, isFalse);
      expect(gateway.envelopeMutationRequested, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('la caisse utilise le vocabulaire inventaire et non bancaire', (
    tester,
  ) async {
    await _pump(tester, _cashAccount(), _ObservationGateway());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Caisse maison'));
    await tester.pumpAndSettle();

    expect(find.text('Inventaire de caisse'), findsOneWidget);
    expect(find.text('Compter les espèces'), findsOneWidget);
    expect(find.text('Rapprochement bancaire'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(
  WidgetTester tester,
  FinancialAccount account,
  _ObservationGateway gateway,
) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      activeHouseholdProvider.overrideWith(
        (ref) async => const ActiveHouseholdState(
          status: ActiveHouseholdStatus.singleHousehold,
          householdId: 'household-1',
        ),
      ),
      remoteAccountsProvider.overrideWith((ref) async => [account]),
      remoteAccountBalancesProvider.overrideWith(
        (ref) async => {account.id: Money.fromMinorUnits(90000)},
      ),
      remoteHouseholdMembersProvider.overrideWith((ref) async => const []),
      accountTransactionHistoryProvider.overrideWith(
        (ref, accountId) async => [],
      ),
      accountBalanceObservationGatewayProvider.overrideWithValue(gateway),
    ],
    child: const MaterialApp(home: AccountsPage()),
  ),
);

FinancialAccount _bankAccount() => FinancialAccount(
  id: 'bank-1',
  name: 'Banque A',
  type: FinancialAccountType.bank,
  openingBalance: Money.fromMinorUnits(0),
);

FinancialAccount _cashAccount() => FinancialAccount(
  id: 'cash-1',
  name: 'Caisse maison',
  type: FinancialAccountType.cash,
  openingBalance: Money.fromMinorUnits(0),
);

class _ObservationGateway implements AccountBalanceObservationGateway {
  String? recordedAccountId;
  Money? recordedAmount;
  bool glMutationRequested = false;
  bool envelopeMutationRequested = false;

  @override
  Future<AccountBalanceObservation?> fetchLatest({
    required String householdId,
    required String accountId,
  }) async => AccountBalanceObservation(
    id: 'observation-1',
    accountId: accountId,
    actualBalance: Money.fromMinorUnits(100000),
    observedAt: DateTime.utc(2026, 10, 1, 8, 30),
    reason: 'Relevé bancaire',
    actorId: 'actor-1',
    actorName: 'Ibrahim',
    createdAt: DateTime.utc(2026, 10, 1, 8, 30),
  );

  @override
  Future<void> record({
    required String accountId,
    required DateTime observedAt,
    required Money actualBalance,
    required String reason,
  }) async {
    recordedAccountId = accountId;
    recordedAmount = actualBalance;
  }
}
