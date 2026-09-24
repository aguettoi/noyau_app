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

  testWidgets('le détail moderne propose le flux canonique manquant', (
    tester,
  ) async {
    await _pump(
      tester,
      _bankAccount(),
      _ObservationGateway(modernHistory: true),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Banque A'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('view-reconciliation-history-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Détail'));
    await tester.pumpAndSettle();
    expect(find.text('Enregistrer une opération manquante'), findsOneWidget);
    await tester.tap(find.text('Enregistrer une opération manquante'));
    await tester.pumpAndSettle();
    expect(find.text('Dépense, revenu ou virement'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'les trois parcours canoniques reviennent au constat après annulation',
    (tester) async {
      await _pump(
        tester,
        _bankAccount(),
        _ObservationGateway(modernHistory: true),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Banque A'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('view-reconciliation-history-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Détail'));
      await tester.pumpAndSettle();

      for (final choice in const [
        'Dépense, revenu ou virement',
        'Dette',
        'Créance ou remboursement',
      ]) {
        await tester.tap(find.text('Enregistrer une opération manquante'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(choice));
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('Détail du constat'), findsOneWidget);
      }

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

  testWidgets(
    'la fiche compte ouvre l’historique et rend les legacy lisibles',
    (tester) async {
      final gateway = _ObservationGateway(legacyHistory: true);
      await _pump(tester, _bankAccount(), gateway);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Banque A'));
      await tester.pumpAndSettle();
      expect(find.text('Voir l’historique'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('view-reconciliation-history-button')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Historique des rapprochements'), findsOneWidget);
      expect(
        find.textContaining('Constat historique — référence GL non figée'),
        findsNWidgets(2),
      );
      expect(find.text('Nouveau constat requis'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
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
  _ObservationGateway({this.legacyHistory = false, this.modernHistory = false});
  final bool legacyHistory;
  final bool modernHistory;
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
  Future<List<AccountReconciliationCase>> fetchHistory({
    required String householdId,
    required String accountId,
  }) async => modernHistory
      ? [
          AccountReconciliationCase(
            observation: AccountBalanceObservation(
              id: 'modern-observation',
              accountId: accountId,
              actualBalance: Money.fromMinorUnits(95000),
              observedAt: DateTime.utc(2026, 10, 2),
              reason: 'Relevé moderne',
              actorId: 'actor-1',
              actorName: 'Ibrahim',
              createdAt: DateTime.utc(2026, 10, 2),
              theoreticalBalanceSnapshot: Money.fromMinorUnits(90000),
              differenceSnapshot: Money.fromMinorUnits(5000),
            ),
            status: 'open',
            remainingDifference: Money.fromMinorUnits(5000),
            resolutions: const [],
          ),
        ]
      : legacyHistory
      ? [
          AccountReconciliationCase(
            observation: AccountBalanceObservation(
              id: 'legacy-observation',
              accountId: accountId,
              actualBalance: Money.fromMinorUnits(73500),
              observedAt: DateTime.utc(2026, 9, 24),
              reason: 'Historique',
              actorId: 'actor-1',
              actorName: 'Ibrahim',
              createdAt: DateTime.utc(2026, 9, 24),
            ),
            status: 'legacy_unfrozen',
            remainingDifference: null,
            resolutions: const [],
          ),
          AccountReconciliationCase(
            observation: AccountBalanceObservation(
              id: 'legacy-observation-685',
              accountId: accountId,
              actualBalance: Money.fromMinorUnits(68500),
              observedAt: DateTime.utc(2026, 9, 23),
              reason: 'Historique antérieur',
              actorId: 'actor-1',
              actorName: 'Ibrahim',
              createdAt: DateTime.utc(2026, 9, 23),
            ),
            status: 'legacy_unfrozen',
            remainingDifference: null,
            resolutions: const [],
          ),
        ]
      : const [];

  @override
  Future<void> explain({
    required String observationId,
    required String kind,
    required String comment,
    required String idempotencyKey,
  }) async {}

  @override
  Future<void> linkFinancialEvent({
    required String observationId,
    required String financialEventId,
    required String comment,
    required String idempotencyKey,
  }) async {}

  @override
  Future<void> resolveByFollowUp({
    required String observationId,
    required String followUpObservationId,
    required String comment,
    required String idempotencyKey,
  }) async {}

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
