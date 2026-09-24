import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/finance/application/providers/remote_accounts_provider.dart';
import 'package:noyau_app/features/finance/application/providers/financial_event_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_transactions_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_debts_provider.dart';
import 'package:noyau_app/features/finance/domain/financial_account.dart';
import 'package:noyau_app/features/finance/domain/transaction_draft.dart';
import 'package:noyau_app/features/finance/domain/transaction_history_item.dart';
import 'package:noyau_app/features/finance/presentation/transactions_page.dart';
import 'package:noyau_app/features/finance/infrastructure/financial_event_supabase_repository.dart';
import 'package:noyau_app/features/envelopes/application/providers/remote_envelopes_provider.dart';

void main() {
  FinancialAccount account({
    required String id,
    required String name,
    bool system = false,
  }) => FinancialAccount(
    id: id,
    name: name,
    type: FinancialAccountType.bank,
    openingBalance: Money.fromMinorUnits(0),
    isSystem: system,
  );

  RemoteEnvelopeBalance envelope({required String id, required String name}) =>
      RemoteEnvelopeBalance(
        id: id,
        name: name,
        inflows: Money.fromMinorUnits(0),
        outflows: Money.fromMinorUnits(0),
        balance: Money.fromMinorUnits(0),
        isSystem: false,
      );

  testWidgets('les comptes système ne sont jamais proposés à la saisie', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remoteAccountsProvider.overrideWith(
            (ref) async => [
              account(id: 'ordinary', name: 'Compte bancaire'),
              account(id: 'system', name: 'Système — Dépenses', system: true),
            ],
          ),
          remoteTransactionsProvider.overrideWith(
            (ref) async => const <TransactionHistoryItem>[],
          ),
          remoteEnvelopeBalancesProvider.overrideWith(
            (ref) async => [envelope(id: 'food', name: 'Courses')],
          ),
        ],
        child: const MaterialApp(home: TransactionsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-transaction-button')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('transaction-source-account-field')).last,
    );
    await tester.pumpAndSettle();
    expect(find.text('Compte bancaire'), findsOneWidget);
    expect(find.text('Système — Dépenses'), findsNothing);
  });

  testWidgets('le double clic de validation ne crée qu une transaction', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final completion = Completer<String>();
    final financialGateway = _FinancialGateway(completion: completion);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remoteAccountsProvider.overrideWith(
            (ref) async => [account(id: 'ordinary', name: 'Compte bancaire')],
          ),
          remoteTransactionsProvider.overrideWith(
            (ref) async => const <TransactionHistoryItem>[],
          ),
          remoteEnvelopeBalancesProvider.overrideWith(
            (ref) async => [envelope(id: 'food', name: 'Courses')],
          ),
          financialEventRepositoryProvider.overrideWith(
            (ref) async => FinancialEventSupabaseRepository(
              gateway: financialGateway,
              householdId: 'home-1',
            ),
          ),
        ],
        child: const MaterialApp(home: TransactionsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-transaction-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('transaction-description-field')),
      'TEST S2 DEPENSE',
    );
    await tester.enterText(
      find.byKey(const Key('transaction-amount-field')),
      '100',
    );
    await tester.tap(
      find.byKey(const Key('transaction-source-account-field')).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compte bancaire').last);
    await tester.pumpAndSettle();
    final formScroll = find.byKey(const Key('create-transaction-form-scroll'));
    final envelopeField = find.descendant(
      of: formScroll,
      matching: find.byKey(const Key('transaction-envelope-field')),
    );
    expect(envelopeField, findsOneWidget);
    await tester.ensureVisible(envelopeField);
    await tester.tap(envelopeField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Courses').last);
    await tester.pumpAndSettle();

    final submit = find.byKey(const Key('create-transaction-button'));
    await tester.tap(submit);
    await tester.pump();

    expect(financialGateway.callCount, 1);
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);

    completion.complete('transaction-1');
    await tester.pumpAndSettle();

    expect(financialGateway.callCount, 1);
  });

  testWidgets(
    'une transaction créée avec un contexte de rapprochement renvoie succès',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final gateway = _FinancialGateway();
      bool? returned;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            remoteAccountsProvider.overrideWith(
              (ref) async => [account(id: 'ordinary', name: 'Compte bancaire')],
            ),
            remoteTransactionsProvider.overrideWith(
              (ref) async => const <TransactionHistoryItem>[],
            ),
            remoteEnvelopeBalancesProvider.overrideWith(
              (ref) async => [envelope(id: 'food', name: 'Courses')],
            ),
            financialEventRepositoryProvider.overrideWith(
              (ref) async => FinancialEventSupabaseRepository(
                gateway: gateway,
                householdId: 'home-1',
              ),
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    returned = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) =>
                            const TransactionsPage(returnAfterCreate: true),
                      ),
                    );
                  },
                  child: const Text('Ouvrir le flux canonique'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ouvrir le flux canonique'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-transaction-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('transaction-description-field')),
        'Opération manquante',
      );
      await tester.enterText(
        find.byKey(const Key('transaction-amount-field')),
        '30',
      );
      await tester.tap(
        find.byKey(const Key('transaction-source-account-field')).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compte bancaire').last);
      await tester.pumpAndSettle();
      final envelopeField = find.descendant(
        of: find.byKey(const Key('create-transaction-form-scroll')),
        matching: find.byKey(const Key('transaction-envelope-field')),
      );
      await tester.ensureVisible(envelopeField);
      await tester.tap(envelopeField);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Courses').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('create-transaction-button')));
      await tester.pumpAndSettle();

      expect(gateway.function, 'create_cash_expense_event');
      expect(returned, isTrue);
      expect(find.text('Ouvrir le flux canonique'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('une dépense simple transmet son enveloppe distante', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final financialGateway = _FinancialGateway();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remoteAccountsProvider.overrideWith(
            (ref) async => [account(id: 'ordinary', name: 'Compte bancaire')],
          ),
          remoteTransactionsProvider.overrideWith(
            (ref) async => const <TransactionHistoryItem>[],
          ),
          remoteEnvelopeBalancesProvider.overrideWith(
            (ref) async => [envelope(id: 'food', name: 'Courses')],
          ),
          createRemoteTransactionProvider.overrideWithValue((draft) async {
            return 'transaction-1';
          }),
          financialEventRepositoryProvider.overrideWith(
            (ref) async => FinancialEventSupabaseRepository(
              gateway: financialGateway,
              householdId: 'home-1',
            ),
          ),
        ],
        child: const MaterialApp(home: TransactionsPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-transaction-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('transaction-description-field')),
      'Courses',
    );
    await tester.enterText(
      find.byKey(const Key('transaction-amount-field')),
      '45.99',
    );
    await tester.tap(
      find.byKey(const Key('transaction-source-account-field')).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compte bancaire').last);
    await tester.pumpAndSettle();
    final formScroll = find.byKey(const Key('create-transaction-form-scroll'));
    final envelopeField = find.descendant(
      of: formScroll,
      matching: find.byKey(const Key('transaction-envelope-field')),
    );
    expect(envelopeField, findsOneWidget);
    await tester.ensureVisible(envelopeField);
    await tester.tap(envelopeField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Courses').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create-transaction-button')));
    await tester.pumpAndSettle();

    expect(financialGateway.function, 'create_cash_expense_event');
    expect(financialGateway.parameters!['p_envelope_allocations'], [
      {'envelope_id': 'food', 'amount': '45.99'},
    ]);
  });

  testWidgets('le revenu propose uniquement les enveloppes ordinaires', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remoteAccountsProvider.overrideWith(
            (ref) async => [
              account(id: 'first', name: 'Compte A'),
              account(id: 'second', name: 'Compte B'),
            ],
          ),
          remoteTransactionsProvider.overrideWith(
            (ref) async => const <TransactionHistoryItem>[],
          ),
          remoteEnvelopeBalancesProvider.overrideWith(
            (ref) async => [
              envelope(id: 'food', name: 'Courses'),
              RemoteEnvelopeBalance(
                id: 'to-allocate',
                name: 'À répartir',
                inflows: Money.fromMinorUnits(0),
                outflows: Money.fromMinorUnits(0),
                balance: Money.fromMinorUnits(0),
                isSystem: true,
              ),
            ],
          ),
        ],
        child: const MaterialApp(home: TransactionsPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-transaction-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('transaction-type-field')).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revenu').last);
    await tester.pumpAndSettle();
    expect(find.text('Répartition du revenu'), findsOneWidget);
    expect(find.textContaining('Reste à répartir'), findsOneWidget);
    await tester.tap(find.byKey(const Key('add-income-envelope-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enveloppe *').last);
    await tester.pumpAndSettle();
    expect(find.text('Courses'), findsOneWidget);
    expect(find.text('À répartir'), findsNothing);
  });

  testWidgets('un revenu sans répartition utilise seulement la RPC canonique', (
    tester,
  ) async {
    final gateway = _FinancialGateway();
    var legacyCalls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remoteAccountsProvider.overrideWith(
            (ref) async => [account(id: 'received', name: 'Compte encaissé')],
          ),
          remoteTransactionsProvider.overrideWith(
            (ref) async => const <TransactionHistoryItem>[],
          ),
          remoteEnvelopeBalancesProvider.overrideWith(
            (ref) async => [envelope(id: 'food', name: 'Courses')],
          ),
          createRemoteTransactionProvider.overrideWithValue((draft) async {
            legacyCalls++;
            return 'legacy';
          }),
          financialEventRepositoryProvider.overrideWith(
            (ref) async => FinancialEventSupabaseRepository(
              gateway: gateway,
              householdId: 'home-1',
            ),
          ),
        ],
        child: const MaterialApp(home: TransactionsPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-transaction-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('transaction-type-field')).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revenu').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('transaction-description-field')),
      'Salaire',
    );
    await tester.enterText(
      find.byKey(const Key('transaction-amount-field')),
      '1000',
    );
    await tester.tap(
      find.byKey(const Key('transaction-destination-account-field')).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compte encaissé').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create-transaction-button')));
    await tester.pumpAndSettle();

    expect(gateway.function, 'create_cash_income_event');
    expect(gateway.parameters!['p_envelope_allocations'], isEmpty);
    expect(legacyCalls, 0);
  });

  testWidgets('un virement visible utilise seulement la RPC canonique', (
    tester,
  ) async {
    final gateway = _FinancialGateway();
    var legacyCalls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remoteAccountsProvider.overrideWith(
            (ref) async => [
              account(id: 'source', name: 'Banque A'),
              account(id: 'destination', name: 'Caisse'),
            ],
          ),
          remoteTransactionsProvider.overrideWith(
            (ref) async => const <TransactionHistoryItem>[],
          ),
          remoteEnvelopeBalancesProvider.overrideWith(
            (ref) async => [envelope(id: 'food', name: 'Courses')],
          ),
          createRemoteTransactionProvider.overrideWithValue((draft) async {
            legacyCalls++;
            return 'legacy';
          }),
          financialEventRepositoryProvider.overrideWith(
            (ref) async => FinancialEventSupabaseRepository(
              gateway: gateway,
              householdId: 'home-1',
            ),
          ),
        ],
        child: const MaterialApp(home: TransactionsPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-transaction-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('transaction-type-field')).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Virement interne').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('transaction-description-field')),
      'Virement vers caisse',
    );
    await tester.enterText(
      find.byKey(const Key('transaction-amount-field')),
      '125',
    );
    await tester.tap(
      find.byKey(const Key('transaction-source-account-field')).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Banque A').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('transaction-destination-account-field')).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Caisse').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create-transaction-button')));
    await tester.pumpAndSettle();

    expect(gateway.function, 'create_account_transfer_event');
    expect(gateway.parameters!['p_source_account_id'], 'source');
    expect(gateway.parameters!['p_destination_account_id'], 'destination');
    expect(gateway.parameters!['p_idempotency_key'], isNotEmpty);
    expect(legacyCalls, 0);
  });

  testWidgets('un retry de virement conserve la même clé idempotente', (
    tester,
  ) async {
    final gateway = _RetryFinancialGateway();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remoteAccountsProvider.overrideWith(
            (ref) async => [
              account(id: 'source', name: 'Banque A'),
              account(id: 'destination', name: 'Caisse'),
            ],
          ),
          remoteTransactionsProvider.overrideWith(
            (ref) async => const <TransactionHistoryItem>[],
          ),
          remoteEnvelopeBalancesProvider.overrideWith(
            (ref) async => [envelope(id: 'food', name: 'Courses')],
          ),
          financialEventRepositoryProvider.overrideWith(
            (ref) async => FinancialEventSupabaseRepository(
              gateway: gateway,
              householdId: 'home-1',
            ),
          ),
        ],
        child: const MaterialApp(home: TransactionsPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-transaction-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('transaction-type-field')).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Virement interne').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('transaction-description-field')),
      'Virement vers caisse',
    );
    await tester.enterText(
      find.byKey(const Key('transaction-amount-field')),
      '125',
    );
    await tester.tap(
      find.byKey(const Key('transaction-source-account-field')).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Banque A').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('transaction-destination-account-field')).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Caisse').last);
    await tester.pumpAndSettle();

    final submit = find.byKey(const Key('create-transaction-button'));
    await tester.tap(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(gateway.requests, hasLength(2));
    expect(
      gateway.requests[0]['p_idempotency_key'],
      gateway.requests[1]['p_idempotency_key'],
    );
  });

  testWidgets('un revenu ne peut pas affecter plus que son montant', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remoteAccountsProvider.overrideWith(
            (ref) async => [account(id: 'received', name: 'Compte encaissé')],
          ),
          remoteTransactionsProvider.overrideWith(
            (ref) async => const <TransactionHistoryItem>[],
          ),
          remoteEnvelopeBalancesProvider.overrideWith(
            (ref) async => [envelope(id: 'food', name: 'Courses')],
          ),
        ],
        child: const MaterialApp(home: TransactionsPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-transaction-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('transaction-type-field')).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revenu').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('transaction-amount-field')),
      '1000',
    );
    await tester.tap(find.byKey(const Key('add-income-envelope-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enveloppe *').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Courses').last);
    await tester.enterText(
      find.byKey(const Key('income-envelope-amount-0')),
      '1000.01',
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Le total affecté ne peut pas dépasser le revenu.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('create-transaction-button')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'deux répartitions de revenu restent sans overflow à la largeur réelle de la modale',
    (tester) async {
      // At this Windows width, AlertDialog constrains its content below the
      // requested 480 px. This reproduces the compact branch used in the app.
      await tester.binding.setSurfaceSize(const Size(560, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            remoteAccountsProvider.overrideWith(
              (ref) async => [account(id: 'received', name: 'Compte encaissé')],
            ),
            remoteTransactionsProvider.overrideWith(
              (ref) async => const <TransactionHistoryItem>[],
            ),
            remoteEnvelopeBalancesProvider.overrideWith(
              (ref) async => [
                envelope(id: 'food', name: 'Nourriture'),
                envelope(id: 'transport', name: 'Navette'),
              ],
            ),
          ],
          child: const MaterialApp(home: TransactionsPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-transaction-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('transaction-type-field')).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revenu').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-income-envelope-row')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enveloppe *').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nourriture').last);
      await tester.enterText(
        find.byKey(const Key('income-envelope-amount-0')),
        '600',
      );
      await tester.tap(find.byKey(const Key('add-income-envelope-row')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enveloppe *').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Navette').last);
      await tester.enterText(
        find.byKey(const Key('income-envelope-amount-1')),
        '250',
      );
      await tester.pumpAndSettle();

      final firstRow = find.byKey(const Key('income-allocation-row-0'));
      final firstAmount = find.byKey(const Key('income-envelope-amount-0'));
      expect(tester.getSize(firstRow).width, lessThan(480));
      expect(tester.getSize(firstRow).height, greaterThan(80));
      expect(tester.getSize(firstAmount).height, greaterThan(0));
      expect(tester.takeException(), isNull);
      expect(find.text('Nourriture'), findsOneWidget);
      expect(find.text('Navette'), findsOneWidget);
    },
  );

  testWidgets('les historiques sans mouvements sont à régulariser', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remoteAccountsProvider.overrideWith((ref) async => const []),
          remoteEnvelopeBalancesProvider.overrideWith((ref) async => const []),
          remoteTransactionsProvider.overrideWith(
            (ref) async => [
              TransactionHistoryItem(
                id: 'not-rendered-id',
                type: LedgerTransactionType.expense,
                occurredAt: DateTime(2026),
                description: 'Historique',
                amount: Money.fromMinorUnits(100),
                createdAt: DateTime(2026),
                hasEnvelopeMovement: false,
              ),
            ],
          ),
        ],
        child: const MaterialApp(home: TransactionsPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('À régulariser'), findsOneWidget);
    expect(find.text('not-rendered-id'), findsNothing);
  });

  testWidgets('une opération ouvre un détail sans identifiant technique', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remoteAccountsProvider.overrideWith((ref) async => const []),
          remoteEnvelopeBalancesProvider.overrideWith((ref) async => const []),
          remoteTransactionsProvider.overrideWith(
            (ref) async => [
              TransactionHistoryItem(
                id: 'technical-id',
                type: LedgerTransactionType.incomeReceivable,
                occurredAt: DateTime(2026, 8, 10),
                description: 'Salaire à recevoir',
                amount: Money.fromMinorUnits(120000),
                createdAt: DateTime(2026, 8, 10),
              ),
            ],
          ),
        ],
        child: const MaterialApp(home: TransactionsPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salaire à recevoir'));
    await tester.pumpAndSettle();
    expect(find.text('Détail de l’opération'), findsOneWidget);
    expect(find.text('Type : Revenu à encaisser'), findsOneWidget);
    expect(find.text('technical-id'), findsNothing);
  });

  testWidgets('le mode dette ne requiert pas de compte de paiement', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remoteAccountsProvider.overrideWith(
            (ref) async => [account(id: 'ordinary', name: 'Compte bancaire')],
          ),
          remoteTransactionsProvider.overrideWith(
            (ref) async => const <TransactionHistoryItem>[],
          ),
          remoteEnvelopeBalancesProvider.overrideWith(
            (ref) async => [envelope(id: 'food', name: 'Courses')],
          ),
        ],
        child: const MaterialApp(home: TransactionsPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-transaction-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('expense-payment-mode-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('À payer plus tard / Dette').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('transaction-source-account-field')),
      findsNothing,
    );
    expect(find.byKey(const Key('debt-creditor-field')), findsOneWidget);
  });

  testWidgets('l’écran dettes affiche des données lisibles sans UUID', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remoteDebtBalancesProvider.overrideWith(
            (ref) async => [
              RemoteDebtBalance(
                id: 'private-id',
                description: 'Facture électricité',
                creditorName: 'Fournisseur',
                initialAmount: Money.fromMinorUnits(10000),
                settledAmount: Money.fromMinorUnits(4000),
                remainingAmount: Money.fromMinorUnits(6000),
                status: 'open',
              ),
            ],
          ),
          remoteAccountsProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: DebtsPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Facture électricité'), findsOneWidget);
    expect(find.textContaining('Partiellement réglée'), findsOneWidget);
    expect(find.text('private-id'), findsNothing);
  });

  testWidgets(
    'l’historique de dette conserve les auteurs distincts de création, règlement et corrections',
    (tester) async {
      final original = Money.fromMinorUnits(10000);
      const creator = RemoteHistoryActor(
        userId: 'creator-id',
        displayName: 'Ibrahim Aguettoi',
      );
      const settlementActor = RemoteHistoryActor(
        userId: 'settlement-actor-id',
        displayName: 'Ibrahim Aguettoi',
      );
      const firstCorrectionActor = RemoteHistoryActor(
        userId: 'first-correction-id',
        displayName: 'Nora',
      );
      const secondCorrectionActor = RemoteHistoryActor(
        userId: 'second-correction-id',
        displayName: 'Ibrahim Aguettoi',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            remoteDebtBalancesProvider.overrideWith(
              (ref) async => [
                RemoteDebtBalance(
                  id: 'debt-history',
                  description: 'Dette historique',
                  creditorName: 'Nora — créancière',
                  initialAmount: original,
                  settledAmount: Money.fromMinorUnits(8000),
                  remainingAmount: Money.fromMinorUnits(2000),
                  status: 'open',
                ),
              ],
            ),
            obligationSettlementHistoryProvider('debt-history').overrideWith(
              (ref) async => RemoteObligationHistory(
                creation: RemoteObligationCreationHistoryItem(
                  recordedAt: DateTime(2026, 9, 12, 8, 30),
                  actor: creator,
                ),
                settlements: [
                  RemoteSettlementHistoryItem(
                    id: 'settlement-id',
                    recordedAt: DateTime(2026, 9, 12, 9, 42),
                    grossAmount: original,
                    reversedAmount: Money.fromMinorUnits(3000),
                    accountName: 'TESTOJ',
                    envelopeMovements: const [],
                    actor: settlementActor,
                    reversals: [
                      RemoteSettlementReversal(
                        id: 'reversal-20',
                        recordedAt: DateTime(2026, 9, 12, 10, 3),
                        amount: Money.fromMinorUnits(2000),
                        reason: 'Saisie erronée',
                        notes: 'Première correction',
                        netAmountAfter: Money.fromMinorUnits(8000),
                        actor: firstCorrectionActor,
                      ),
                      RemoteSettlementReversal(
                        id: 'reversal-10',
                        recordedAt: DateTime(2026, 9, 12, 10, 15),
                        amount: Money.fromMinorUnits(1000),
                        reason: 'Montant rectifié',
                        notes: 'Seconde correction',
                        netAmountAfter: Money.fromMinorUnits(7000),
                        actor: secondCorrectionActor,
                      ),
                    ],
                  ),
                ],
                writeoffs: const [],
              ),
            ),
            remoteAccountsProvider.overrideWith((ref) async => const []),
          ],
          child: const MaterialApp(home: DebtsPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Historique'));
      await tester.pumpAndSettle();

      expect(find.text('Règlement : 100,00 MAD'), findsOneWidget);
      expect(find.text('Création de la dette'), findsOneWidget);
      expect(find.text('12/09/2026 • 09:42'), findsOneWidget);
      expect(find.text('Effectué par : Ibrahim Aguettoi'), findsNWidgets(2));
      expect(find.text('Nora — créancière'), findsOneWidget);
      expect(
        find.text('Déjà annulé : 30,00 MAD • Net : 70,00 MAD'),
        findsOneWidget,
      );
      expect(find.text('Correction du règlement'), findsNWidgets(2));
      expect(find.text('Montant annulé : 20,00 MAD'), findsOneWidget);
      expect(find.text('Montant annulé : 10,00 MAD'), findsOneWidget);
      expect(find.text('Motif : Saisie erronée'), findsOneWidget);
      expect(find.text('Motif : Montant rectifié'), findsOneWidget);
      expect(find.text('Notes : Première correction'), findsOneWidget);
      expect(find.text('Notes : Seconde correction'), findsOneWidget);
      expect(find.text('Net après correction : 80,00 MAD'), findsOneWidget);
      expect(find.text('Net après correction : 70,00 MAD'), findsOneWidget);
      expect(find.text('Effectuée par : Nora'), findsOneWidget);
      expect(find.text('Effectuée par : Ibrahim Aguettoi'), findsOneWidget);
      expect(find.text('reversal-20'), findsNothing);
      expect(find.text('reversal-10'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'l’historique Income et Recovery affiche auteurs, abandon et fallback profil absent',
    (tester) async {
      Future<void> verifyKind(String kind) async {
        await tester.pumpWidget(
          ProviderScope(
            key: ValueKey('receivable-history-$kind'),
            overrides: [
              remoteReceivableBalancesProvider.overrideWith(
                (ref) async => [
                  RemoteReceivableBalance(
                    id: '$kind-history',
                    description: 'Créance $kind historique',
                    kind: kind,
                    initialAmount: Money.fromMinorUnits(10000),
                    settledAmount: Money.fromMinorUnits(8000),
                    remainingAmount: Money.fromMinorUnits(2000),
                    status: 'open',
                  ),
                ],
              ),
              obligationSettlementHistoryProvider('$kind-history').overrideWith(
                (ref) async => RemoteObligationHistory(
                  creation: RemoteObligationCreationHistoryItem(
                    recordedAt: DateTime(2026, 9, 12, 8),
                    actor: RemoteHistoryActor(
                      userId: 'creator-$kind',
                      displayName: 'Créateur $kind',
                    ),
                  ),
                  settlements: [
                    RemoteSettlementHistoryItem(
                      id: '$kind-settlement',
                      recordedAt: DateTime(2026, 9, 12, 9, 42),
                      grossAmount: Money.fromMinorUnits(10000),
                      reversedAmount: Money.fromMinorUnits(2000),
                      accountName: 'TESTOJ',
                      envelopeMovements: const [],
                      actor: const RemoteHistoryActor(
                        userId: 'settlement-actor',
                        displayName: 'Acteur encaissement',
                      ),
                      reversals: [
                        RemoteSettlementReversal(
                          id: '$kind-reversal',
                          recordedAt: DateTime(2026, 9, 12, 10),
                          amount: Money.fromMinorUnits(2000),
                          reason: 'Correction $kind',
                          notes: null,
                          netAmountAfter: Money.fromMinorUnits(8000),
                          actor: const RemoteHistoryActor(
                            userId: 'missing-profile',
                            displayName: 'Utilisateur inconnu',
                          ),
                          envelopeMovements: kind == 'income'
                              ? const [
                                  RemoteSettlementEnvelopeMovement(
                                    id: 'income-reversal-food',
                                    envelopeName: 'Nourriture',
                                    amount: Money.fromMinorUnits(1000),
                                  ),
                                  RemoteSettlementEnvelopeMovement(
                                    id: 'income-reversal-travel',
                                    envelopeName: 'Voyages',
                                    amount: Money.fromMinorUnits(500),
                                  ),
                                  RemoteSettlementEnvelopeMovement(
                                    id: 'income-reversal-to-allocate',
                                    envelopeName: 'À répartir',
                                    amount: Money.fromMinorUnits(500),
                                  ),
                                ]
                              : const [],
                        ),
                      ],
                    ),
                  ],
                  writeoffs: [
                    RemoteObligationWriteoffHistoryItem(
                      id: 'writeoff-$kind',
                      recordedAt: DateTime(2026, 9, 12, 11),
                      amount: Money.fromMinorUnits(1000),
                      reason: 'Abandon $kind',
                      notes: null,
                      actor: const RemoteHistoryActor(
                        userId: 'writeoff-actor',
                        displayName: 'Acteur abandon',
                      ),
                    ),
                  ],
                ),
              ),
              remoteAccountsProvider.overrideWith((ref) async => const []),
              remoteEnvelopeBalancesProvider.overrideWith(
                (ref) async => const <RemoteEnvelopeBalance>[],
              ),
            ],
            child: const MaterialApp(home: ReceivablesPage()),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Historique'));
        await tester.pumpAndSettle();
        expect(find.text('Correction de l’encaissement'), findsOneWidget);
        expect(find.text('Motif : Correction $kind'), findsOneWidget);
        expect(find.text('Effectué par : Acteur encaissement'), findsOneWidget);
        expect(
          find.text('Effectuée par : Utilisateur inconnu'),
          findsOneWidget,
        );
        if (kind == 'income') {
          expect(find.text('Nourriture -10,00 MAD'), findsOneWidget);
          expect(find.text('Voyages -5,00 MAD'), findsOneWidget);
          expect(find.text('À répartir -5,00 MAD'), findsOneWidget);
          expect(find.text('income-reversal-food'), findsNothing);
          expect(find.text('income-reversal-travel'), findsNothing);
          expect(find.text('income-reversal-to-allocate'), findsNothing);
        }
        expect(find.text('Abandon'), findsOneWidget);
        expect(find.text('Effectué par : Acteur abandon'), findsOneWidget);
        expect(find.text('$kind-reversal'), findsNothing);
        await tester.tap(find.text('Fermer'));
        await tester.pumpAndSettle();
      }

      await verifyKind('income');
      await verifyKind('recovery');
    },
  );

  testWidgets('les statuts de dette sont dérivés des montants de clôture', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remoteDebtBalancesProvider.overrideWith(
            (ref) async => [
              RemoteDebtBalance(
                id: 'settled',
                description: 'Dette soldée',
                creditorName: 'Créancier A',
                initialAmount: Money.fromMinorUnits(10000),
                settledAmount: Money.fromMinorUnits(10000),
                writtenOffAmount: Money.fromMinorUnits(0),
                remainingAmount: Money.fromMinorUnits(0),
                status: 'settled',
              ),
              RemoteDebtBalance(
                id: 'written-off',
                description: 'Dette abandonnée',
                creditorName: 'Créancier B',
                initialAmount: Money.fromMinorUnits(10000),
                settledAmount: Money.fromMinorUnits(0),
                writtenOffAmount: Money.fromMinorUnits(10000),
                remainingAmount: Money.fromMinorUnits(0),
                status: 'written_off',
              ),
              RemoteDebtBalance(
                id: 'mixed-closed',
                description: 'Dette clôturée mixte',
                creditorName: 'Créancier C',
                initialAmount: Money.fromMinorUnits(10000),
                settledAmount: Money.fromMinorUnits(7000),
                writtenOffAmount: Money.fromMinorUnits(3000),
                remainingAmount: Money.fromMinorUnits(0),
                status: 'written_off',
              ),
              RemoteDebtBalance(
                id: 'mixed-open',
                description: 'Dette mixte ouverte',
                creditorName: 'Créancier D',
                initialAmount: Money.fromMinorUnits(10000),
                settledAmount: Money.fromMinorUnits(2000),
                writtenOffAmount: Money.fromMinorUnits(3000),
                remainingAmount: Money.fromMinorUnits(5000),
                status: 'open',
              ),
            ],
          ),
          remoteAccountsProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: DebtsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Soldée'), findsOneWidget);
    expect(find.text('Abandonnée'), findsOneWidget);
    expect(find.text('Clôturée — mixte'), findsOneWidget);
    expect(find.text('Partiellement réglée et abandonnée'), findsOneWidget);
    expect(find.text('Régler'), findsOneWidget);
    expect(find.text('Abandonner'), findsOneWidget);
    final closedMixedDebt = find.ancestor(
      of: find.text('Dette clôturée mixte'),
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(of: closedMixedDebt, matching: find.text('Régler')),
      findsNothing,
    );
    expect(
      find.descendant(of: closedMixedDebt, matching: find.text('Abandonner')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('les créances Income et Recovery affichent leur clôture mixte', (
    tester,
  ) async {
    // The fixture contains five cards.  Give the lazy list a viewport large
    // enough to build the closed Recovery card as well as the Income card.
    await tester.binding.setSurfaceSize(const Size(390, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remoteReceivableBalancesProvider.overrideWith(
            (ref) async => [
              RemoteReceivableBalance(
                id: 'income-settled',
                description: 'Créance Income soldée',
                kind: 'income',
                initialAmount: Money.fromMinorUnits(10000),
                settledAmount: Money.fromMinorUnits(10000),
                writtenOffAmount: Money.fromMinorUnits(0),
                remainingAmount: Money.fromMinorUnits(0),
                status: 'settled',
              ),
              RemoteReceivableBalance(
                id: 'income-written-off',
                description: 'Créance Income abandonnée',
                kind: 'income',
                initialAmount: Money.fromMinorUnits(10000),
                settledAmount: Money.fromMinorUnits(0),
                writtenOffAmount: Money.fromMinorUnits(10000),
                remainingAmount: Money.fromMinorUnits(0),
                status: 'written_off',
              ),
              RemoteReceivableBalance(
                id: 'income-mixed',
                description: 'Créance Income mixte',
                kind: 'income',
                initialAmount: Money.fromMinorUnits(10000),
                settledAmount: Money.fromMinorUnits(7000),
                writtenOffAmount: Money.fromMinorUnits(3000),
                remainingAmount: Money.fromMinorUnits(0),
                status: 'written_off',
              ),
              RemoteReceivableBalance(
                id: 'recovery-mixed-open',
                description: 'Créance Recovery mixte',
                kind: 'recovery',
                initialAmount: Money.fromMinorUnits(10000),
                settledAmount: Money.fromMinorUnits(2000),
                writtenOffAmount: Money.fromMinorUnits(3000),
                remainingAmount: Money.fromMinorUnits(5000),
                status: 'open',
              ),
              RemoteReceivableBalance(
                id: 'recovery-mixed-closed',
                description: 'Créance Recovery clôturée mixte',
                kind: 'recovery',
                initialAmount: Money.fromMinorUnits(10000),
                settledAmount: Money.fromMinorUnits(7000),
                writtenOffAmount: Money.fromMinorUnits(3000),
                remainingAmount: Money.fromMinorUnits(0),
                status: 'written_off',
              ),
            ],
          ),
          remoteAccountsProvider.overrideWith((ref) async => const []),
          remoteEnvelopeBalancesProvider.overrideWith(
            (ref) async => const <RemoteEnvelopeBalance>[],
          ),
        ],
        child: const MaterialApp(home: ReceivablesPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Soldée'), findsOneWidget);
    expect(find.text('Abandonnée'), findsOneWidget);
    // The lazy list initially builds the Income card.  Scroll to the Recovery
    // card before asserting its independently rendered mixed-close badge.
    expect(find.text('Clôturée — mixte'), findsOneWidget);
    expect(find.text('Partiellement encaissée et abandonnée'), findsOneWidget);
    expect(find.text('Encaisser'), findsOneWidget);
    expect(find.text('Abandonner'), findsOneWidget);
    final closedMixedIncome = find.ancestor(
      of: find.text('Créance Income mixte'),
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(of: closedMixedIncome, matching: find.text('Encaisser')),
      findsNothing,
    );
    expect(
      find.descendant(of: closedMixedIncome, matching: find.text('Abandonner')),
      findsNothing,
    );
    await tester.scrollUntilVisible(
      find.text('Créance Recovery clôturée mixte'),
      240,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Clôturée — mixte'), findsOneWidget);
    final closedMixedRecovery = find.ancestor(
      of: find.text('Créance Recovery clôturée mixte'),
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(
        of: closedMixedRecovery,
        matching: find.text('Encaisser'),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'le dialogue de règlement présente la dette et des champs aérés',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            remoteDebtBalancesProvider.overrideWith(
              (ref) async => [
                RemoteDebtBalance(
                  id: 'debt-1',
                  description: 'TEST DETTE SIMPLE',
                  creditorName: 'TEST CREANCIER',
                  initialAmount: Money.fromMinorUnits(12000),
                  settledAmount: Money.fromMinorUnits(0),
                  remainingAmount: Money.fromMinorUnits(12000),
                  status: 'open',
                ),
              ],
            ),
            remoteAccountsProvider.overrideWith(
              (ref) async => [account(id: 'testoj', name: 'TESTOJ')],
            ),
          ],
          child: const MaterialApp(home: DebtsPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Régler'));
      await tester.pumpAndSettle();

      expect(find.text('Régler une dette'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('TEST DETTE SIMPLE'),
        ),
        findsOneWidget,
      );
      expect(find.text('Créancier : TEST CREANCIER'), findsOneWidget);
      expect(find.text('Restant à régler : 120,00 MAD'), findsOneWidget);
      expect(find.text('Montant à régler (MAD) *'), findsOneWidget);
      expect(find.text('Compte de paiement *'), findsOneWidget);
      expect(find.text('Libellé *'), findsOneWidget);
      expect(find.text('Notes'), findsOneWidget);
      expect(find.text('Règlement : TEST DETTE SIMPLE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'la création de revenu à encaisser utilise seulement la RPC canonique',
    (tester) async {
      final gateway = _FinancialGateway();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            remoteReceivableBalancesProvider.overrideWith(
              (ref) async => const <RemoteReceivableBalance>[],
            ),
            financialEventRepositoryProvider.overrideWith(
              (ref) async => FinancialEventSupabaseRepository(
                gateway: gateway,
                householdId: 'home-1',
              ),
            ),
          ],
          child: const MaterialApp(home: ReceivablesPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('new-receivable-button')));
      await tester.pumpAndSettle();
      expect(find.text('Revenu à encaisser'), findsOneWidget);
      expect(find.text('Remboursement à récupérer'), findsOneWidget);

      await tester.tap(find.byKey(const Key('income-receivable-choice')));
      await tester.pumpAndSettle();
      expect(find.text('Compte encaissé'), findsNothing);
      expect(find.text('Enveloppe'), findsNothing);
      await tester.enterText(
        find.byKey(const Key('receivable-description-field')),
        'Prestation test',
      );
      await tester.enterText(
        find.byKey(const Key('receivable-amount-field')),
        '120',
      );
      await tester.enterText(
        find.byKey(const Key('receivable-debtor-field')),
        'TEST DEBITEUR',
      );
      await tester.tap(
        find.byKey(const Key('create-income-receivable-button')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Créer une créance'), findsOneWidget);
      expect(find.text('Montant : 120,00 MAD'), findsOneWidget);
      expect(find.textContaining('Aucun encaissement'), findsOneWidget);

      await tester.tap(find.text('Créer la créance').last);
      await tester.pumpAndSettle();
      expect(gateway.function, 'create_income_receivable_event');
      expect(gateway.parameters!['p_destination_account_id'], isNull);
      expect(gateway.parameters!['p_envelope_allocations'], isNull);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'le provider Recovery utilise explicitement le compte source de la dépense',
    () {
      final provider = File(
        'lib/features/finance/application/providers/remote_debts_provider.dart',
      ).readAsStringSync();

      expect(
        provider,
        contains(
          'accounts!financial_transactions_source_account_id_fkey(name)',
        ),
      );
      expect(provider, isNot(contains("'accounts(name), '")));
    },
  );

  test('le plafond Recovery déduit les engagements et masque un reste nul', () {
    expect(
      RecoveryExpenseSource.remainingFor(
        sourceAmount: Money.fromMinorUnits(10000),
        committedAmount: Money.fromMinorUnits(6000),
      ),
      Money.fromMinorUnits(4000),
    );
    expect(
      RecoveryExpenseSource.remainingFor(
        sourceAmount: Money.fromMinorUnits(10000),
        committedAmount: Money.fromMinorUnits(10000),
      ),
      isNull,
    );
  });

  testWidgets('le remboursement propose TEST DEPENSE SIMPLE sans UUID', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(480, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gateway = _FinancialGateway();
    final source = RecoveryExpenseSource(
      eventId: 'private-expense-event',
      description: 'TEST DEPENSE SIMPLE',
      occurredAt: DateTime(2026, 9, 3),
      sourceAmount: Money.fromMinorUnits(10000),
      committedAmount: Money.fromMinorUnits(6000),
      maximumAmount: Money.fromMinorUnits(4000),
      accountName: 'TESTOJ',
      envelopeId: 'private-food-envelope',
      envelopeName: 'Nourriture',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remoteReceivableBalancesProvider.overrideWith(
            (ref) async => const <RemoteReceivableBalance>[],
          ),
          eligibleRecoverySourcesProvider.overrideWith((ref) async => [source]),
          financialEventRepositoryProvider.overrideWith(
            (ref) async => FinancialEventSupabaseRepository(
              gateway: gateway,
              householdId: 'home-1',
            ),
          ),
        ],
        child: const MaterialApp(home: ReceivablesPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-receivable-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recovery-receivable-choice')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('create-recovery-receivable-button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Choisissez une dépense source.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('recovery-source-field')));
    await tester.pumpAndSettle();
    expect(find.textContaining('TEST DEPENSE SIMPLE'), findsOneWidget);
    expect(find.textContaining('Dépense 100,00 MAD'), findsOneWidget);
    expect(find.textContaining('Déjà engagé 60,00 MAD'), findsOneWidget);
    expect(find.textContaining('Maximum 40,00 MAD'), findsOneWidget);
    expect(find.textContaining('TESTOJ'), findsOneWidget);
    expect(find.textContaining('Nourriture'), findsOneWidget);
    expect(find.text('private-expense-event'), findsNothing);
    expect(find.text('private-food-envelope'), findsNothing);
    await tester.tap(find.textContaining('TEST DEPENSE SIMPLE').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('receivable-description-field')),
      'Remboursement courses',
    );
    await tester.enterText(
      find.byKey(const Key('receivable-amount-field')),
      '41',
    );
    await tester.enterText(
      find.byKey(const Key('receivable-debtor-field')),
      'TEST DEBITEUR',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('maximum récupérable'), findsOneWidget);
    expect(gateway.callCount, 0);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('create-recovery-receivable-button')),
          )
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const Key('receivable-amount-field')),
      '40',
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('create-recovery-receivable-button')),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('une source Recovery sans reste récupérable n’est pas proposée', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remoteReceivableBalancesProvider.overrideWith(
            (ref) async => const <RemoteReceivableBalance>[],
          ),
          eligibleRecoverySourcesProvider.overrideWith(
            (ref) async => const <RecoveryExpenseSource>[],
          ),
        ],
        child: const MaterialApp(home: ReceivablesPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-receivable-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recovery-receivable-choice')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recovery-source-field')));
    await tester.pumpAndSettle();

    expect(find.text('TEST DEPENSE SIMPLE'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'l’encaissement income ventile sans double revenu ni UUID visible',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final gateway = _FinancialGateway();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            remoteReceivableBalancesProvider.overrideWith(
              (ref) async => [
                RemoteReceivableBalance(
                  id: 'private-receivable-id',
                  description: 'Prestation septembre',
                  kind: 'income',
                  initialAmount: Money.fromMinorUnits(12000),
                  settledAmount: Money.fromMinorUnits(4500),
                  remainingAmount: Money.fromMinorUnits(7500),
                  status: 'open',
                  counterpartyName: 'Client test',
                ),
              ],
            ),
            remoteAccountsProvider.overrideWith(
              (ref) async => [account(id: 'testoj', name: 'TESTOJ')],
            ),
            remoteEnvelopeBalancesProvider.overrideWith(
              (ref) async => [
                envelope(id: 'food-id', name: 'Nourriture'),
                envelope(id: 'savings-id', name: 'Épargne'),
                RemoteEnvelopeBalance(
                  id: 'private-to-allocate-id',
                  name: 'À répartir',
                  inflows: Money.fromMinorUnits(0),
                  outflows: Money.fromMinorUnits(0),
                  balance: Money.fromMinorUnits(0),
                  isSystem: true,
                ),
              ],
            ),
            financialEventRepositoryProvider.overrideWith(
              (ref) async => FinancialEventSupabaseRepository(
                gateway: gateway,
                householdId: 'home-1',
              ),
            ),
          ],
          child: const MaterialApp(home: ReceivablesPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Encaisser').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compte à créditer *'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('TESTOJ').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('add-receivable-envelope-row')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enveloppe *').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nourriture').last);
      await tester.enterText(
        find.byKey(const Key('receivable-envelope-amount-0')),
        '30',
      );
      await tester.tap(find.byKey(const Key('add-receivable-envelope-row')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enveloppe *').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Épargne').last);
      await tester.enterText(
        find.byKey(const Key('receivable-envelope-amount-1')),
        '20',
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Reste à répartir : 25,00 MAD'),
        findsOneWidget,
      );
      expect(find.text('private-receivable-id'), findsNothing);
      expect(find.text('private-to-allocate-id'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Encaisser').last);
      await tester.pumpAndSettle();
      expect(find.text('Encaisser 75,00 MAD'), findsOneWidget);
      expect(find.text('→ Nourriture : 30,00 MAD'), findsOneWidget);
      expect(find.text('→ Épargne : 20,00 MAD'), findsOneWidget);
      expect(find.text('→ À répartir : 25,00 MAD'), findsOneWidget);
      expect(find.text('Aucun nouveau revenu ne sera créé.'), findsOneWidget);

      await tester.tap(find.text('Encaisser').last);
      await tester.pumpAndSettle();
      expect(gateway.function, 'settle_receivable_event');
      expect(gateway.parameters!['p_envelope_allocations'], [
        {'envelope_id': 'food-id', 'amount': '30.00'},
        {'envelope_id': 'savings-id', 'amount': '20.00'},
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'l’encaissement Recovery affiche et confirme la restitution obligatoire',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final gateway = _FinancialGateway();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            remoteReceivableBalancesProvider.overrideWith(
              (ref) async => [
                RemoteReceivableBalance(
                  id: 'recovery-id',
                  description: 'Remboursement courses',
                  kind: 'recovery',
                  initialAmount: Money.fromMinorUnits(6000),
                  settledAmount: Money.fromMinorUnits(0),
                  remainingAmount: Money.fromMinorUnits(6000),
                  status: 'open',
                  recoverySourceEnvelopeId: 'food-id',
                ),
              ],
            ),
            remoteAccountsProvider.overrideWith(
              (ref) async => [account(id: 'testoj', name: 'TESTOJ')],
            ),
            remoteEnvelopeBalancesProvider.overrideWith(
              (ref) async => [envelope(id: 'food-id', name: 'Nourriture')],
            ),
            financialEventRepositoryProvider.overrideWith(
              (ref) async => FinancialEventSupabaseRepository(
                gateway: gateway,
                householdId: 'home-1',
              ),
            ),
          ],
          child: const MaterialApp(home: ReceivablesPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Encaisser').first);
      await tester.pumpAndSettle();
      expect(find.text('Enveloppe restaurée : Nourriture'), findsOneWidget);
      expect(find.text('Montant restauré : 60,00 MAD'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);

      await tester.tap(find.text('Compte à créditer *'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('TESTOJ').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Encaisser').last);
      await tester.pumpAndSettle();

      expect(find.text('Enveloppe restaurée :'), findsOneWidget);
      expect(find.text('Nourriture'), findsOneWidget);
      expect(find.text('Montant restauré : 60,00 MAD'), findsNWidgets(2));
      expect(find.textContaining('À répartir'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Encaisser').last);
      await tester.pumpAndSettle();
      expect(gateway.function, 'settle_recovery_event');
      expect(gateway.parameters!['p_refund_source_envelope'], isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'l’abandon de dette est explicite, motivé et sans compte de paiement',
    (tester) async {
      final gateway = _FinancialGateway();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            remoteDebtBalancesProvider.overrideWith(
              (ref) async => [
                RemoteDebtBalance(
                  id: 'debt-writeoff-id',
                  description: 'Dette fournisseur',
                  creditorName: 'Fournisseur test',
                  initialAmount: Money.fromMinorUnits(12000),
                  settledAmount: Money.fromMinorUnits(0),
                  remainingAmount: Money.fromMinorUnits(12000),
                  status: 'open',
                ),
              ],
            ),
            remoteAccountsProvider.overrideWith(
              (ref) async => [account(id: 'testoj', name: 'TESTOJ')],
            ),
            financialEventRepositoryProvider.overrideWith(
              (ref) async => FinancialEventSupabaseRepository(
                gateway: gateway,
                householdId: 'home-1',
              ),
            ),
          ],
          child: const MaterialApp(home: DebtsPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Abandonner'));
      await tester.pumpAndSettle();
      expect(find.text('Abandonner une dette'), findsOneWidget);
      expect(find.text('Restant : 120,00 MAD'), findsOneWidget);
      expect(find.text('Motif *'), findsOneWidget);
      expect(find.text('Compte de paiement *'), findsNothing);

      await tester.enterText(find.byType(TextFormField).at(1), 'Accord écrit');
      await tester.tap(find.text('Abandonner').last);
      await tester.pumpAndSettle();
      expect(find.text('Confirmer l’abandon'), findsNWidgets(2));
      await tester.tap(find.text('Confirmer l’abandon').last);
      await tester.pumpAndSettle();
      expect(gateway.function, 'writeoff_debt_event');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'l’abandon Recovery ne restaure ni enveloppe ni compte et reste sans UUID',
    (tester) async {
      final gateway = _FinancialGateway();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            remoteReceivableBalancesProvider.overrideWith(
              (ref) async => [
                RemoteReceivableBalance(
                  id: 'private-recovery-id',
                  description: 'Remboursement fournisseur',
                  kind: 'recovery',
                  initialAmount: Money.fromMinorUnits(6000),
                  settledAmount: Money.fromMinorUnits(0),
                  remainingAmount: Money.fromMinorUnits(6000),
                  status: 'open',
                  counterpartyName: 'Fournisseur test',
                  recoverySourceEnvelopeId: 'food-id',
                ),
              ],
            ),
            remoteAccountsProvider.overrideWith(
              (ref) async => [account(id: 'testoj', name: 'TESTOJ')],
            ),
            remoteEnvelopeBalancesProvider.overrideWith(
              (ref) async => [envelope(id: 'food-id', name: 'Nourriture')],
            ),
            financialEventRepositoryProvider.overrideWith(
              (ref) async => FinancialEventSupabaseRepository(
                gateway: gateway,
                householdId: 'home-1',
              ),
            ),
          ],
          child: const MaterialApp(home: ReceivablesPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Abandonner'));
      await tester.pumpAndSettle();
      expect(
        find.text('Abandonner un remboursement à récupérer'),
        findsOneWidget,
      );
      expect(
        find.textContaining('l’enveloppe source ne sera pas restaurée.'),
        findsOneWidget,
      );
      expect(find.text('private-recovery-id'), findsNothing);

      await tester.enterText(find.byType(TextFormField).at(1), 'Irrécouvrable');
      await tester.tap(find.text('Abandonner').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmer l’abandon').last);
      await tester.pumpAndSettle();
      expect(gateway.function, 'writeoff_recovery_event');
      expect(tester.takeException(), isNull);
    },
  );
}

class _FinancialGateway implements FinancialEventSupabaseGateway {
  _FinancialGateway({this.completion});

  final Completer<String>? completion;
  String? function;
  Map<String, Object?>? parameters;
  var callCount = 0;

  @override
  Future<Object?> call(String function, Map<String, Object?> parameters) {
    callCount++;
    this.function = function;
    this.parameters = Map<String, Object?>.from(parameters);
    return completion?.future ?? Future<Object?>.value('event-1');
  }
}

class _RetryFinancialGateway implements FinancialEventSupabaseGateway {
  final requests = <Map<String, Object?>>[];

  @override
  Future<Object?> call(String function, Map<String, Object?> parameters) async {
    requests.add(Map<String, Object?>.from(parameters));
    if (requests.length == 1) {
      throw StateError('Réseau incertain');
    }
    return 'event-1';
  }
}
