import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/finance/application/providers/financial_event_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_accounts_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_debts_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_transactions_provider.dart';
import 'package:noyau_app/features/finance/domain/financial_account.dart';
import 'package:noyau_app/features/finance/domain/transaction_history_item.dart';
import 'package:noyau_app/features/finance/infrastructure/financial_event_supabase_repository.dart';
import 'package:noyau_app/features/finance/presentation/transactions_page.dart';

void main() {
  const actor = RemoteHistoryActor(
    userId: 'actor-1',
    displayName: 'Ibrahim Aguettoi',
  );

  RemoteObligationWriteoffHistoryItem writeoff({
    List<RemoteObligationWriteoffReversal> reversals = const [],
  }) => RemoteObligationWriteoffHistoryItem(
    id: 'writeoff-1',
    recordedAt: DateTime(2026, 9, 13, 9),
    amount: Money.fromMinorUnits(7000),
    reason: 'Créance irrécouvrable',
    notes: 'Note origine',
    actor: actor,
    reversals: reversals,
  );

  RemoteObligationHistory history({
    List<RemoteObligationWriteoffReversal> reversals = const [],
  }) => RemoteObligationHistory(
    creation: RemoteObligationCreationHistoryItem(
      recordedAt: DateTime(2026, 9, 12, 8),
      actor: actor,
    ),
    settlements: const [],
    writeoffs: [writeoff(reversals: reversals)],
  );

  Future<void> openHistory(
    WidgetTester tester, {
    required String kind,
    required FinancialEventSupabaseGateway gateway,
    required RemoteObligationHistory obligationHistory,
  }) async {
    const id = 'obligation-1';
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          remoteAccountsProvider.overrideWith(
            (ref) async => const <FinancialAccount>[],
          ),
          remoteTransactionsProvider.overrideWith(
            (ref) async => const <TransactionHistoryItem>[],
          ),
          financialEventRepositoryProvider.overrideWith(
            (ref) async => FinancialEventSupabaseRepository(
              gateway: gateway,
              householdId: 'home-1',
            ),
          ),
          obligationSettlementHistoryProvider(
            id,
          ).overrideWith((ref) async => obligationHistory),
          if (kind == 'debt')
            remoteDebtBalancesProvider.overrideWith(
              (ref) async => [
                RemoteDebtBalance(
                  id: id,
                  description: 'Dette à annuler',
                  initialAmount: Money.fromMinorUnits(7000),
                  settledAmount: Money.fromMinorUnits(0),
                  writtenOffAmount: Money.fromMinorUnits(7000),
                  remainingAmount: Money.fromMinorUnits(0),
                  status: 'written_off',
                ),
              ],
            )
          else
            remoteReceivableBalancesProvider.overrideWith(
              (ref) async => [
                RemoteReceivableBalance(
                  id: id,
                  description: 'Créance à annuler',
                  kind: kind,
                  initialAmount: Money.fromMinorUnits(7000),
                  settledAmount: Money.fromMinorUnits(0),
                  writtenOffAmount: Money.fromMinorUnits(7000),
                  remainingAmount: Money.fromMinorUnits(0),
                  status: 'written_off',
                ),
              ],
            ),
        ],
        child: MaterialApp(
          home: kind == 'debt' ? const DebtsPage() : const ReceivablesPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Historique'));
    await tester.pumpAndSettle();
  }

  test('le reliquat d’un abandon provient des reversals associés', () {
    final item = writeoff(
      reversals: [
        RemoteObligationWriteoffReversal(
          id: 'reversal-20',
          recordedAt: DateTime(2026, 9, 13, 10),
          amount: Money.fromMinorUnits(2000),
          reason: 'Partiel',
          notes: null,
          actor: actor,
        ),
      ],
    );

    expect(item.reversedAmount, Money.fromMinorUnits(2000));
    expect(item.reversibleAmount, Money.fromMinorUnits(5000));
  });

  testWidgets(
    'Debt, Income et Recovery appellent leur RPC d’annulation d’abandon source',
    (tester) async {
      final expectedFunctions = <String, String>{
        'debt': 'reverse_debt_writeoff_event',
        'income': 'reverse_income_receivable_writeoff_event',
        'recovery': 'reverse_recovery_writeoff_event',
      };

      for (final entry in expectedFunctions.entries) {
        final gateway = _Gateway();
        await openHistory(
          tester,
          kind: entry.key,
          gateway: gateway,
          obligationHistory: history(),
        );
        await tester.tap(find.byKey(const Key('reverse-writeoff-writeoff-1')));
        await tester.pumpAndSettle();
        expect(find.text('Annuler l’abandon'), findsWidgets);
        expect(find.text('Abandon concerné : 70,00 MAD'), findsOneWidget);
        expect(find.text('Encore annulable : 70,00 MAD'), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('writeoff-reversal-amount-field')),
          '20',
        );
        await tester.enterText(
          find.byKey(const Key('writeoff-reversal-reason-field')),
          'Justificatif retrouvé',
        );
        await tester.enterText(
          find.byKey(const Key('writeoff-reversal-notes-field')),
          'Note de correction',
        );
        await tester.tap(
          find.byKey(const Key('writeoff-reversal-submit-button')),
        );
        await tester.pumpAndSettle();

        expect(gateway.callCount, 1);
        expect(gateway.function, entry.value);
        expect(gateway.parameters!['p_source_adjustment_id'], 'writeoff-1');
        expect(gateway.parameters!['p_amount'], '20.00');
      }
    },
  );

  testWidgets(
    'l’historique conserve write-off et annulations individuelles, sans action après reversal total',
    (tester) async {
      final reversals = [
        RemoteObligationWriteoffReversal(
          id: 'reversal-20',
          recordedAt: DateTime(2026, 9, 13, 10),
          amount: Money.fromMinorUnits(2000),
          reason: 'Première correction',
          notes: 'Pièce reçue',
          actor: actor,
        ),
        RemoteObligationWriteoffReversal(
          id: 'reversal-50',
          recordedAt: DateTime(2026, 9, 13, 11),
          amount: Money.fromMinorUnits(5000),
          reason: 'Annulation complète',
          notes: null,
          actor: const RemoteHistoryActor(
            userId: 'actor-2',
            displayName: 'Nora',
          ),
        ),
      ];
      await openHistory(
        tester,
        kind: 'income',
        gateway: _Gateway(),
        obligationHistory: history(reversals: reversals),
      );

      expect(find.text('Abandon'), findsOneWidget);
      expect(find.text('Annulation de l’abandon'), findsNWidgets(2));
      expect(find.text('Montant annulé : 20,00 MAD'), findsOneWidget);
      expect(find.text('Montant annulé : 50,00 MAD'), findsOneWidget);
      expect(find.text('Motif : Première correction'), findsOneWidget);
      expect(find.text('Notes : Pièce reçue'), findsOneWidget);
      expect(find.text('Effectuée par : Nora'), findsOneWidget);
      expect(
        find.text('Déjà annulé : 70,00 MAD • Encore annulable : 0,00 MAD'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('reverse-writeoff-writeoff-1')),
        findsNothing,
      );
      expect(find.text('reversal-20'), findsNothing);
      expect(find.text('reversal-50'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'validation locale et loading bloquent montant invalide et double clic',
    (tester) async {
      final completion = Completer<Object?>();
      final gateway = _Gateway(completion: completion);
      await openHistory(
        tester,
        kind: 'debt',
        gateway: gateway,
        obligationHistory: history(
          reversals: [
            RemoteObligationWriteoffReversal(
              id: 'reversal-20',
              recordedAt: DateTime(2026, 9, 13, 10),
              amount: Money.fromMinorUnits(2000),
              reason: 'Partiel',
              notes: null,
              actor: actor,
            ),
          ],
        ),
      );
      await tester.tap(find.byKey(const Key('reverse-writeoff-writeoff-1')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('writeoff-reversal-amount-field')),
        '0',
      );
      await tester.enterText(
        find.byKey(const Key('writeoff-reversal-reason-field')),
        'Montant nul',
      );
      await tester.tap(
        find.byKey(const Key('writeoff-reversal-submit-button')),
      );
      await tester.pump();
      expect(
        find.text(
          'Le montant doit être positif et ne pas dépasser le reliquat annulable.',
        ),
        findsOneWidget,
      );
      expect(gateway.callCount, 0);
      await tester.enterText(
        find.byKey(const Key('writeoff-reversal-amount-field')),
        '50.01',
      );
      await tester.enterText(
        find.byKey(const Key('writeoff-reversal-reason-field')),
        'Trop élevé',
      );
      await tester.tap(
        find.byKey(const Key('writeoff-reversal-submit-button')),
      );
      await tester.pump();
      expect(
        find.text(
          'Le montant doit être positif et ne pas dépasser le reliquat annulable.',
        ),
        findsOneWidget,
      );
      expect(gateway.callCount, 0);

      await tester.enterText(
        find.byKey(const Key('writeoff-reversal-amount-field')),
        '50',
      );
      await tester.tap(
        find.byKey(const Key('writeoff-reversal-submit-button')),
      );
      await tester.tap(
        find.byKey(const Key('writeoff-reversal-submit-button')),
      );
      await tester.pump();
      expect(gateway.callCount, 1);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('writeoff-reversal-submit-button')),
            )
            .onPressed,
        isNull,
      );
      completion.complete('event-1');
      await tester.pumpAndSettle();
      expect(gateway.callCount, 1);
    },
  );

  testWidgets('une erreur RPC reste visible et conserve la tentative ouverte', (
    tester,
  ) async {
    final gateway = _Gateway(
      error: StateError(
        'Write-off reversal exceeds the amount still reversible',
      ),
    );
    await openHistory(
      tester,
      kind: 'income',
      gateway: gateway,
      obligationHistory: history(),
    );
    await tester.tap(find.byKey(const Key('reverse-writeoff-writeoff-1')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('writeoff-reversal-amount-field')),
      '20',
    );
    await tester.enterText(
      find.byKey(const Key('writeoff-reversal-reason-field')),
      'Test erreur distante',
    );
    await tester.tap(find.byKey(const Key('writeoff-reversal-submit-button')));
    await tester.pumpAndSettle();

    expect(gateway.callCount, 1);
    expect(
      find.text(
        'Cet abandon est déjà totalement annulé ou le montant dépasse le reliquat annulable.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('writeoff-reversal-submit-button')),
      findsOneWidget,
    );
  });

  testWidgets('un réessai conserve la même clé d’idempotence', (tester) async {
    final gateway = _RetryGateway();
    await openHistory(
      tester,
      kind: 'recovery',
      gateway: gateway,
      obligationHistory: history(),
    );
    await tester.tap(find.byKey(const Key('reverse-writeoff-writeoff-1')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('writeoff-reversal-amount-field')),
      '20',
    );
    await tester.enterText(
      find.byKey(const Key('writeoff-reversal-reason-field')),
      'Réessai après erreur réseau',
    );

    await tester.tap(find.byKey(const Key('writeoff-reversal-submit-button')));
    await tester.pumpAndSettle();
    expect(gateway.calls, hasLength(1));
    expect(
      find.byKey(const Key('writeoff-reversal-submit-button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('writeoff-reversal-submit-button')));
    await tester.pumpAndSettle();
    expect(gateway.calls, hasLength(2));
    expect(
      gateway.calls[0]['p_idempotency_key'],
      gateway.calls[1]['p_idempotency_key'],
    );
    expect(
      find.byKey(const Key('writeoff-reversal-submit-button')),
      findsNothing,
    );
  });
}

class _Gateway implements FinancialEventSupabaseGateway {
  _Gateway({this.completion, this.error});

  final Completer<Object?>? completion;
  final Object? error;
  String? function;
  Map<String, Object?>? parameters;
  var callCount = 0;

  @override
  Future<Object?> call(String value, Map<String, Object?> data) {
    function = value;
    parameters = data;
    callCount++;
    if (error != null) return Future<Object?>.error(error!);
    return completion?.future ?? Future.value('event-1');
  }
}

class _RetryGateway implements FinancialEventSupabaseGateway {
  final calls = <Map<String, Object?>>[];

  @override
  Future<Object?> call(String _, Map<String, Object?> data) {
    calls.add(Map<String, Object?>.from(data));
    if (calls.length == 1) {
      return Future<Object?>.error(StateError('network unavailable'));
    }
    return Future.value('event-1');
  }
}
