import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/monthly_close/application/monthly_close_provider.dart';
import 'package:noyau_app/features/monthly_close/domain/monthly_close.dart';
import 'package:noyau_app/features/monthly_close/presentation/monthly_close_page.dart';
import 'package:noyau_app/features/finance/application/providers/remote_accounts_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_account_balances_provider.dart';
import 'package:noyau_app/features/finance/domain/financial_account.dart';
import 'package:noyau_app/features/finance/presentation/accounts_page.dart';
import 'package:noyau_app/features/finance/presentation/member_compensations_page.dart';
import 'package:noyau_app/features/finance/presentation/transactions_page.dart';
import 'package:noyau_app/features/envelopes/application/providers/remote_envelopes_provider.dart';
import 'package:noyau_app/features/finance/application/providers/payment_methods_provider.dart';
import 'package:noyau_app/core/money/money.dart';

void main() {
  final snapshot = MonthlyCloseSnapshot(
    month: DateTime(2026, 10),
    status: MonthlyCloseStatus.open,
    issues: const [
      CloseIssue(
        code: 'cash',
        label: 'Inventaire espèces',
        count: 1,
        severity: CloseIssueSeverity.blocker,
        destination: 'Comptes',
      ),
      CloseIssue(
        code: 'receipt',
        label: 'Justificatifs',
        count: 2,
        severity: CloseIssueSeverity.warning,
        destination: 'Historique',
      ),
    ],
  );

  for (final size in [const Size(390, 700), const Size(1280, 800)]) {
    testWidgets('R2 reste lisible sans overflow à ${size.width}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            monthlyCloseProvider.overrideWith((ref) async => snapshot),
          ],
          child: const MaterialApp(home: MonthlyClosePage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('monthly-close-page')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('À faire financier'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('À faire financier'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('close-month-button')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('close-month-button')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('OWNER réouvre avec motif et conserve l’audit', (tester) async {
    var calls = 0;
    String? capturedReason;
    final closed = MonthlyCloseSnapshot(
      month: DateTime(2026, 10),
      status: MonthlyCloseStatus.closed,
      periodId: 'period-1',
      owner: true,
      issues: const [],
      history: [
        MonthlyCloseAuditEntry(
          kind: 'closed',
          actor: 'Membre technique',
          at: DateTime(2026, 10, 31, 20),
          reason: 'Clôture validée',
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          monthlyCloseProvider.overrideWith((ref) async => closed),
          monthlyCloseTargetsProvider.overrideWith((ref) async => const []),
          reopenMonthlyCloseProvider.overrideWithValue((period, reason) async {
            calls++;
            capturedReason = reason;
          }),
        ],
        child: const MaterialApp(home: MonthlyClosePage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('reopen-month-button')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('reopen-month-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmer la réouverture'));
    await tester.pumpAndSettle();
    expect(calls, 0);

    await tester.tap(find.byKey(const Key('reopen-month-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('reopen-reason')),
      'Correction',
    );
    await tester.tap(find.text('Confirmer la réouverture'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(capturedReason, 'Correction');
    expect(
      find.text('Membre technique • 2026-10-31 20:00:00.000\nClôture validée'),
      findsOneWidget,
    );
  });

  testWidgets('un membre non OWNER ne peut pas réouvrir', (tester) async {
    final closed = MonthlyCloseSnapshot(
      month: DateTime(2026, 10),
      status: MonthlyCloseStatus.closed,
      periodId: 'period-1',
      issues: const [],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          monthlyCloseProvider.overrideWith((ref) async => closed),
          monthlyCloseTargetsProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: MonthlyClosePage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('reopen-month-button')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('reopen-month-button')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('configure une cible compte × enveloppe via le RPC exposé', (
    tester,
  ) async {
    var saved = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          monthlyCloseProvider.overrideWith(
            (ref) async => MonthlyCloseSnapshot(
              month: DateTime(2026, 10),
              status: MonthlyCloseStatus.open,
              issues: const [],
            ),
          ),
          monthlyCloseTargetsProvider.overrideWith((ref) async => const []),
          remoteAccountsProvider.overrideWith(
            (ref) async => [
              FinancialAccount(
                id: 'account-1',
                name: 'Compte foyer',
                type: FinancialAccountType.bank,
                openingBalance: const Money.fromMinorUnits(0),
              ),
            ],
          ),
          remoteEnvelopeBalancesProvider.overrideWith(
            (ref) async => const [
              RemoteEnvelopeBalance(
                id: 'envelope-1',
                name: 'Courses',
                inflows: Money.fromMinorUnits(0),
                outflows: Money.fromMinorUnits(0),
                balance: Money.fromMinorUnits(0),
                isSystem: false,
              ),
            ],
          ),
          setMonthlyCloseTargetProvider.overrideWithValue(({
            required month,
            required envelopeId,
            required accountId,
            required amount,
            required reason,
          }) async {
            saved =
                envelopeId == 'envelope-1' &&
                accountId == 'account-1' &&
                amount == Money.fromDirhams(250);
          }),
        ],
        child: const MaterialApp(home: MonthlyClosePage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('add-monthly-target')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('add-monthly-target')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('target-amount')), '250');
    await tester.enterText(
      find.byKey(const Key('target-override-reason')),
      'Exception validée',
    );
    await tester.tap(find.byKey(const Key('save-monthly-target')));
    await tester.pumpAndSettle();
    expect(saved, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Fin de mois ouvre le paramétrage structurel puis revient', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          monthlyCloseProvider.overrideWith(
            (ref) async => MonthlyCloseSnapshot(
              month: DateTime(2026, 10),
              status: MonthlyCloseStatus.open,
              issues: const [],
            ),
          ),
          monthlyCloseTargetsProvider.overrideWith((ref) async => const []),
          automaticTargetPreviewProvider.overrideWith(
            (ref) async => const AutomaticTargetPreview(
              targets: [],
              missingMappings: ['Besoin perso'],
              complete: false,
            ),
          ),
          remoteAccountsProvider.overrideWith((ref) async => const []),
          remoteEnvelopeBalancesProvider.overrideWith(
            (ref) async => const [
              RemoteEnvelopeBalance(
                id: 'envelope-1',
                name: 'Besoin perso',
                inflows: Money.fromMinorUnits(0),
                outflows: Money.fromMinorUnits(0),
                balance: Money.fromMinorUnits(52048),
                isSystem: false,
              ),
            ],
          ),
          paymentMethodsProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: MonthlyClosePage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('configure-envelope-targets')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('configure-envelope-targets')));
    await tester.pumpAndSettle();
    expect(find.text('Paramétrage des enveloppes'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('monthly-close-page')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('le centre À faire ouvre les surfaces métier canoniques', (
    tester,
  ) async {
    final actionable = MonthlyCloseSnapshot(
      month: DateTime(2026, 10),
      status: MonthlyCloseStatus.open,
      issues: const [
        CloseIssue(
          code: 'reconciliations',
          label: 'Rapprochements',
          count: 1,
          severity: CloseIssueSeverity.blocker,
          destination: 'Comptes',
          accountId: 'account-context',
        ),
        CloseIssue(
          code: 'receipts',
          label: 'Justificatifs',
          count: 1,
          severity: CloseIssueSeverity.warning,
          destination: 'Transactions',
          financialEventId: 'event-context',
        ),
        CloseIssue(
          code: 'compensations',
          label: 'Compensations',
          count: 1,
          severity: CloseIssueSeverity.warning,
          destination: 'Compensations',
          compensationId: 'compensation-context',
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          monthlyCloseProvider.overrideWith((ref) async => actionable),
          monthlyCloseTargetsProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: MonthlyClosePage()),
      ),
    );
    await tester.pumpAndSettle();

    for (final route in [
      (const Key('todo-reconciliations'), AccountsPage),
      (const Key('todo-receipts'), TransactionsPage),
      (const Key('todo-compensations'), MemberCompensationsPage),
    ]) {
      await tester.scrollUntilVisible(
        find.byKey(route.$1),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byKey(route.$1));
      await tester.pumpAndSettle();
      expect(tester.widget<ListTile>(find.byKey(route.$1)).onTap, isNotNull);
      await tester.tap(find.byKey(route.$1));
      await tester.pumpAndSettle();
      expect(find.byType(route.$2), findsOneWidget);
      final page = tester.widget(find.byType(route.$2));
      if (page is AccountsPage) {
        expect(page.initialAccountId, 'account-context');
      } else if (page is TransactionsPage) {
        expect(page.initialFinancialEventId, 'event-context');
      } else if (page is MemberCompensationsPage) {
        expect(page.initialCompensationId, 'compensation-context');
      }
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
    'le retour de l’inventaire espèces recharge le dossier de fin de mois',
    (tester) async {
      var fetches = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            monthlyCloseProvider.overrideWith((ref) async {
              fetches++;
              return MonthlyCloseSnapshot(
                month: DateTime(2026, 10),
                status: MonthlyCloseStatus.open,
                owner: true,
                issues: fetches == 1
                    ? const [
                        CloseIssue(
                          code: 'cash',
                          label: 'Inventaire espèces',
                          count: 1,
                          severity: CloseIssueSeverity.blocker,
                          destination: 'Comptes',
                          accountId: 'cash-1',
                        ),
                      ]
                    : const [],
              );
            }),
            monthlyCloseTargetsProvider.overrideWith((ref) async => const []),
          ],
          child: const MaterialApp(home: MonthlyClosePage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(fetches, 1);
      expect(find.text('Espèces : 0 %'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('workflow-step-4')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('workflow-step-4')));
      await tester.pumpAndSettle();
      expect(find.byType(AccountsPage), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(fetches, 2);
      expect(find.text('Espèces : 100 %'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('workflow-step-4')),
          matching: find.text('TERMINÉ'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('todo-cash')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'affiche actuel cible écart puis exige une confirmation explicite',
    (tester) async {
      var executed = false;
      const matrix = EnvelopeAccountMatrix(
        positions: [
          EnvelopeAccountPosition(
            accountId: 'a',
            envelopeId: 'e',
            amount: Money.fromMinorUnits(10000),
          ),
          EnvelopeAccountPosition(
            accountId: 'b',
            envelopeId: 'e',
            amount: Money.fromMinorUnits(0),
          ),
        ],
        reliable: true,
        accountGap: Money.fromMinorUnits(0),
        envelopeGap: Money.fromMinorUnits(0),
        fingerprint: 'fp',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            monthlyCloseProvider.overrideWith(
              (ref) async => MonthlyCloseSnapshot(
                month: DateTime(2026, 10),
                status: MonthlyCloseStatus.open,
                issues: const [],
              ),
            ),
            envelopeAccountMatrixProvider.overrideWith((ref) async => matrix),
            monthlyCloseTargetsProvider.overrideWith(
              (ref) async => [
                MonthlyEnvelopeAccountTarget(
                  id: 't1',
                  envelopeId: 'e',
                  accountId: 'a',
                  amount: Money.fromMinorUnits(4000),
                  createdAt: DateTime(2026),
                ),
                MonthlyEnvelopeAccountTarget(
                  id: 't2',
                  envelopeId: 'e',
                  accountId: 'b',
                  amount: Money.fromMinorUnits(6000),
                  createdAt: DateTime(2026),
                ),
              ],
            ),
            remoteAccountsProvider.overrideWith(
              (ref) async => [
                FinancialAccount(
                  id: 'a',
                  name: 'Compte A',
                  type: FinancialAccountType.bank,
                  openingBalance: const Money.fromMinorUnits(0),
                ),
                FinancialAccount(
                  id: 'b',
                  name: 'Compte B',
                  type: FinancialAccountType.cash,
                  openingBalance: const Money.fromMinorUnits(0),
                ),
              ],
            ),
            remoteEnvelopeBalancesProvider.overrideWith(
              (ref) async => const [
                RemoteEnvelopeBalance(
                  id: 'e',
                  name: 'Courses',
                  inflows: Money.fromMinorUnits(10000),
                  outflows: Money.fromMinorUnits(0),
                  balance: Money.fromMinorUnits(10000),
                  isSystem: false,
                ),
              ],
            ),
            executeMonthlyReallocationProvider.overrideWithValue((
              month,
              current,
              simulation,
              economicDate,
            ) async {
              executed =
                  simulation.physicalTransfers.single.amount.minorUnits ==
                      6000 &&
                  economicDate.year >= 2026;
            }),
          ],
          child: const MaterialApp(home: MonthlyClosePage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('confirm-reallocation')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byKey(const Key('confirm-reallocation')));
      await tester.pumpAndSettle();
      expect(find.textContaining('ACTUEL'), findsWidgets);
      expect(
        find.textContaining('Retrait / alimentation espèces'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('confirm-reallocation')));
      await tester.pumpAndSettle();
      expect(executed, isFalse);
      await tester.tap(find.byKey(const Key('execute-reallocation')));
      await tester.pumpAndSettle();
      expect(executed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'inventaire initial déduit seulement la dernière position mathématiquement unique',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      List<EnvelopeAccountPosition>? saved;
      String? savedNote;
      final account = FinancialAccount(
        id: 'account-1',
        name: 'Banque',
        type: FinancialAccountType.bank,
        openingBalance: Money.fromMinorUnits(0),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            monthlyCloseProvider.overrideWith(
              (ref) async => MonthlyCloseSnapshot(
                month: DateTime(2026, 10),
                status: MonthlyCloseStatus.open,
                issues: const [],
                owner: true,
              ),
            ),
            envelopeAccountMatrixProvider.overrideWith(
              (ref) async => const EnvelopeAccountMatrix(
                positions: [],
                reliable: false,
                accountGap: Money.fromMinorUnits(10000),
                envelopeGap: Money.fromMinorUnits(10000),
                fingerprint: 'empty',
              ),
            ),
            remoteAccountsProvider.overrideWith((ref) async => [account]),
            remoteAccountBalancesProvider.overrideWith(
              (ref) async => const {'account-1': Money.fromMinorUnits(10000)},
            ),
            remoteEnvelopeBalancesProvider.overrideWith(
              (ref) async => const [
                RemoteEnvelopeBalance(
                  id: 'envelope-1',
                  name: 'Épargne',
                  inflows: Money.fromMinorUnits(10000),
                  outflows: Money.fromMinorUnits(0),
                  balance: Money.fromMinorUnits(10000),
                  isSystem: false,
                  recommendedAccountId: 'account-1',
                ),
                RemoteEnvelopeBalance(
                  id: 'system',
                  name: 'À répartir',
                  inflows: Money.fromMinorUnits(0),
                  outflows: Money.fromMinorUnits(0),
                  balance: Money.fromMinorUnits(0),
                  isSystem: true,
                ),
              ],
            ),
            setEnvelopeAccountSnapshotProvider.overrideWithValue((
              rows,
              note,
            ) async {
              saved = rows;
              savedNote = note;
            }),
            initialPositionPreviewProvider.overrideWith(
              (ref) async => const InitialPositionPreview(
                positions: [],
                sourceFingerprint: '',
              ),
            ),
          ],
          child: const MaterialApp(home: MonthlyClosePage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('initialize-matrix')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byKey(const Key('initialize-matrix')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('initialize-matrix')));
      await tester.pumpAndSettle();

      expect(find.text('1 / 1 enveloppes inventoriées'), findsOneWidget);
      expect(
        find.text('Solde nul : aucune saisie nécessaire.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Compte structurel recommandé'),
        findsOneWidget,
      );
      final deducedField = tester.widget<TextField>(
        find.byKey(const Key('matrix-envelope-1-account-1')),
      );
      expect(deducedField.controller!.text, '100.00');
      expect(deducedField.readOnly, isTrue);
      expect(find.text('Déduit par équilibrage'), findsOneWidget);

      await tester.tap(find.byKey(const Key('use-recommended-envelope-1')));
      await tester.pump();
      expect(find.text('1 / 1 enveloppes inventoriées'), findsOneWidget);
      await tester.tap(find.text('Par compte'));
      await tester.pump();
      expect(find.byKey(const Key('matrix-account-account-1')), findsOneWidget);
      expect(find.text('Épargne'), findsWidgets);

      await tester.ensureVisible(
        find.byKey(const Key('matrix-inventory-note')),
      );
      await tester.enterText(
        find.byKey(const Key('matrix-inventory-note')),
        'Inventaire contrôlé',
      );
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('save-matrix-snapshot')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('save-matrix-snapshot')));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      await tester.tap(find.byKey(const Key('confirm-matrix-snapshot')));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(saved, hasLength(1));
      expect(saved!.single.amount, const Money.fromMinorUnits(10000));
      expect(savedNote, 'Inventaire contrôlé');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('le point de départ préremplit uniquement une preuve traçable', (
    tester,
  ) async {
    final account = FinancialAccount(
      id: 'cash',
      name: 'Espèces maison',
      type: FinancialAccountType.cash,
      openingBalance: const Money.fromMinorUnits(0),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          monthlyCloseProvider.overrideWith(
            (ref) async => MonthlyCloseSnapshot(
              month: DateTime(2026, 10),
              status: MonthlyCloseStatus.open,
              issues: const [],
              owner: true,
            ),
          ),
          envelopeAccountMatrixProvider.overrideWith(
            (ref) async => const EnvelopeAccountMatrix(
              positions: [],
              reliable: false,
              accountGap: Money.fromMinorUnits(5000),
              envelopeGap: Money.fromMinorUnits(5000),
              fingerprint: 'empty',
            ),
          ),
          initialPositionPreviewProvider.overrideWith(
            (ref) async => const InitialPositionPreview(
              sourceFingerprint: 'certified',
              positions: [
                EnvelopeAccountPosition(
                  accountId: 'cash',
                  envelopeId: 'food',
                  amount: Money.fromMinorUnits(5000),
                  provenance: PositionProvenance.sourceProof,
                  provenanceReference: 'Enveloppes!D29',
                ),
              ],
            ),
          ),
          remoteAccountsProvider.overrideWith((ref) async => [account]),
          remoteAccountBalancesProvider.overrideWith(
            (ref) async => const {'cash': Money.fromMinorUnits(5000)},
          ),
          remoteEnvelopeBalancesProvider.overrideWith(
            (ref) async => const [
              RemoteEnvelopeBalance(
                id: 'food',
                name: 'Nourriture',
                inflows: Money.fromMinorUnits(5000),
                outflows: Money.fromMinorUnits(0),
                balance: Money.fromMinorUnits(5000),
                isSystem: false,
                recommendedAccountId: 'cash',
              ),
            ],
          ),
        ],
        child: const MaterialApp(home: MonthlyClosePage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('initialize-matrix')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('initialize-matrix')));
    await tester.pumpAndSettle();
    expect(find.text('1 / 1 enveloppes inventoriées'), findsOneWidget);
    expect(find.text('Prouvé par la source'), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byKey(const Key('matrix-food-cash')),
    );
    expect(field.readOnly, isTrue);
    expect(field.controller!.text, '50.00');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'la matrice desktop conserve ses en-têtes et expose la provenance',
    (tester) async {
      tester.view.physicalSize = const Size(1024, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final accounts = <FinancialAccount>[
        for (final entry in const [
          ('awb', 'AWB Ibrahim', FinancialAccountType.bank),
          ('nora', 'Banque Nora', FinancialAccountType.bank),
          ('cih', 'CIH Ibrahim', FinancialAccountType.bank),
          ('cash', 'Espèces maison', FinancialAccountType.cash),
          ('arreda', 'Islamique / Arreda Ibrahim', FinancialAccountType.bank),
        ])
          FinancialAccount(
            id: entry.$1,
            name: entry.$2,
            type: entry.$3,
            openingBalance: const Money.fromMinorUnits(0),
          ),
      ];
      final envelopes = <RemoteEnvelopeBalance>[
        for (var index = 1; index <= 18; index++)
          RemoteEnvelopeBalance(
            id: 'envelope-$index',
            name: index == 18 ? 'Dernière enveloppe' : 'Enveloppe $index',
            inflows: const Money.fromMinorUnits(1000),
            outflows: const Money.fromMinorUnits(0),
            balance: const Money.fromMinorUnits(1000),
            isSystem: false,
          ),
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            monthlyCloseProvider.overrideWith(
              (ref) async => MonthlyCloseSnapshot(
                month: DateTime(2026, 10),
                status: MonthlyCloseStatus.open,
                issues: const [],
                owner: true,
              ),
            ),
            envelopeAccountMatrixProvider.overrideWith(
              (ref) async => const EnvelopeAccountMatrix(
                positions: [],
                reliable: false,
                accountGap: Money.fromMinorUnits(18000),
                envelopeGap: Money.fromMinorUnits(18000),
                fingerprint: 'empty',
              ),
            ),
            initialPositionPreviewProvider.overrideWith(
              (ref) async => const InitialPositionPreview(
                positions: [],
                sourceFingerprint: '',
              ),
            ),
            remoteAccountsProvider.overrideWith((ref) async => accounts),
            remoteAccountBalancesProvider.overrideWith(
              (ref) async => const {
                'awb': Money.fromMinorUnits(3600),
                'nora': Money.fromMinorUnits(3600),
                'cih': Money.fromMinorUnits(3600),
                'cash': Money.fromMinorUnits(3600),
                'arreda': Money.fromMinorUnits(3600),
              },
            ),
            remoteEnvelopeBalancesProvider.overrideWith(
              (ref) async => envelopes,
            ),
          ],
          child: const MaterialApp(home: MonthlyClosePage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('initialize-matrix')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byKey(const Key('initialize-matrix')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('initialize-matrix')));
      await tester.pumpAndSettle();

      final header = find.byKey(const Key('matrix-sticky-header'));
      expect(header, findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(header, findsNothing);
      await tester.ensureVisible(find.byKey(const Key('initialize-matrix')));
      await tester.tap(find.byKey(const Key('initialize-matrix')));
      await tester.pumpAndSettle();
      expect(header, findsOneWidget);
      for (final account in accounts) {
        expect(
          find.descendant(of: header, matching: find.text(account.name)),
          findsOneWidget,
        );
      }
      expect(find.text('Affecté'), findsOneWidget);
      expect(find.text('Solde enveloppe'), findsOneWidget);
      expect(find.text('Écart'), findsOneWidget);
      expect(
        find.byTooltip('Enveloppe 1 • Islamique / Arreda Ibrahim'),
        findsOneWidget,
      );
      await tester.drag(
        find.byKey(const Key('matrix-horizontal-scroll')),
        const Offset(-600, 0),
      );
      await tester.pumpAndSettle();
      final arredaField = tester.widget<TextField>(
        find.byKey(const Key('matrix-envelope-1-arreda')),
      );
      expect(arredaField.decoration?.labelText, 'Islamique / Arreda Ibrahim');
      await tester.drag(
        find.byKey(const Key('matrix-horizontal-scroll')),
        const Offset(600, 0),
      );
      await tester.pumpAndSettle();
      final headerTop = tester.getTopLeft(header).dy;
      final matrixScrollable = find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable &&
            widget.axisDirection == AxisDirection.down &&
            widget.controller != null &&
            widget.physics == null,
      );
      expect(matrixScrollable, findsOneWidget);
      final matrixScrollableState = tester.state<ScrollableState>(
        matrixScrollable,
      );
      matrixScrollableState.position.jumpTo(
        matrixScrollableState.position.maxScrollExtent / 2,
      );
      await tester.pumpAndSettle();
      expect(find.text('Enveloppe 9'), findsOneWidget);
      expect(tester.getTopLeft(header).dy, closeTo(headerTop, 0.1));
      matrixScrollableState.position.jumpTo(
        matrixScrollableState.position.maxScrollExtent,
      );
      await tester.pumpAndSettle();
      expect(find.text('Dernière enveloppe'), findsOneWidget);
      expect(tester.getTopLeft(header).dy, closeTo(headerTop, 0.1));

      matrixScrollableState.position.jumpTo(0);
      await tester.pumpAndSettle();
      final fieldFinder = find.byKey(const Key('matrix-envelope-1-awb'));
      expect(fieldFinder, findsOneWidget);
      final field = tester.widget<TextField>(fieldFinder);
      expect(field.decoration?.labelText, 'AWB Ibrahim');
      await tester.enterText(fieldFinder, '10');
      await tester.pumpAndSettle();
      expect(find.text('Arbitrage d’inventaire'), findsWidgets);
      await tester.tap(find.byKey(const Key('provenance-envelope-1-awb')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmation métier').last);
      await tester.pumpAndSettle();
      expect(find.text('Confirmation métier'), findsWidgets);

      await tester.tap(find.text('Par compte'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('matrix-account-awb')), findsOneWidget);
      final dialogScrollableState = find
          .byType(Scrollable)
          .evaluate()
          .whereType<StatefulElement>()
          .map((element) => element.state)
          .whereType<ScrollableState>()
          .firstWhere(
            (state) =>
                state.position.axisDirection == AxisDirection.down &&
                state.position.maxScrollExtent > 0 &&
                state.position.pixels == 0 &&
                state.position.viewportDimension > 500,
          );
      dialogScrollableState.position.jumpTo(
        dialogScrollableState.position.maxScrollExtent,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('matrix-inventory-note')),
        'Inventaire interactif contrôlé',
      );
      await tester.pump();
      expect(find.byKey(const Key('save-matrix-snapshot')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
