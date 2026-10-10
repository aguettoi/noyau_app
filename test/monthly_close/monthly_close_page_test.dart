import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/monthly_close/application/monthly_close_provider.dart';
import 'package:noyau_app/features/monthly_close/domain/monthly_close.dart';
import 'package:noyau_app/features/monthly_close/presentation/monthly_close_page.dart';
import 'package:noyau_app/features/finance/application/providers/remote_accounts_provider.dart';
import 'package:noyau_app/features/finance/domain/financial_account.dart';
import 'package:noyau_app/features/finance/presentation/accounts_page.dart';
import 'package:noyau_app/features/finance/presentation/member_compensations_page.dart';
import 'package:noyau_app/features/finance/presentation/transactions_page.dart';
import 'package:noyau_app/features/envelopes/application/providers/remote_envelopes_provider.dart';
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
    await tester.tap(find.byKey(const Key('save-monthly-target')));
    await tester.pumpAndSettle();
    expect(saved, isTrue);
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
        ),
        CloseIssue(
          code: 'receipts',
          label: 'Justificatifs',
          count: 1,
          severity: CloseIssueSeverity.warning,
          destination: 'Transactions',
        ),
        CloseIssue(
          code: 'compensations',
          label: 'Compensations',
          count: 1,
          severity: CloseIssueSeverity.warning,
          destination: 'Compensations',
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
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });
}
