import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/budget_intelligence/application/providers/remote_budget_provider.dart';
import 'package:noyau_app/features/budget_intelligence/domain/budget_intelligence.dart';
import 'package:noyau_app/features/budget_intelligence/presentation/budget_runs_page.dart';
import 'package:noyau_app/features/finance/domain/financial_account.dart';

void main() {
  final accounts = [
    FinancialAccount(
      id: 'current',
      name: 'Compte courant',
      type: FinancialAccountType.bank,
      openingBalance: const Money.fromMinorUnits(0),
    ),
    FinancialAccount(
      id: 'savings',
      name: 'Compte épargne',
      type: FinancialAccountType.savings,
      openingBalance: const Money.fromMinorUnits(0),
    ),
  ];
  const lines = [
    RemoteBudgetRunLine(
      id: 'food-line',
      envelopeId: 'food',
      previousBalanceCents: 0,
      rolloverCents: 0,
      plannedCents: 200000,
      resultingCents: 200000,
      priority: 10,
    ),
    RemoteBudgetRunLine(
      id: 'savings-line',
      envelopeId: 'savings',
      previousBalanceCents: 0,
      rolloverCents: 0,
      plannedCents: 800000,
      resultingCents: 800000,
      priority: 20,
    ),
  ];

  testWidgets(
    'funding confirmation stays disabled until every allocation is balanced',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BudgetFundingDistributionDialog(
            lines: lines,
            accounts: accounts,
            balancesCents: {'current': 500000, 'savings': 1000000},
            envelopeNames: {'food': 'Nourriture', 'savings': 'Épargne'},
          ),
        ),
      );

      expect(find.text('Budget : 10 000,00 MAD'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('confirm-funding-distribution')),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const Key('funding-account-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Compte courant').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('funding-account-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Compte épargne').last);
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('confirm-funding-distribution')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.enterText(find.byKey(const Key('funding-amount-1')), '7999');
      await tester.pump();
      expect(find.text('Reste à affecter : 1,00 MAD'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('confirm-funding-distribution')),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'le menu des comptes affiche le type et le solde complet en MAD',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BudgetFundingDistributionDialog(
            lines: lines,
            accounts: [
              FinancialAccount(
                id: 'test-account',
                name: 'Compte TESTOJ',
                type: FinancialAccountType.bank,
                openingBalance: const Money.fromMinorUnits(0),
              ),
            ],
            balancesCents: {'test-account': 999900},
            envelopeNames: {'food': 'Nourriture', 'savings': 'Épargne'},
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('funding-account-0')));
      await tester.pumpAndSettle();

      expect(find.text('Compte TESTOJ'), findsWidgets);
      expect(find.text('Compte courant'), findsOneWidget);
      expect(find.text('Solde disponible : 9 999,00 MAD'), findsOneWidget);
      expect(find.textContaining('...'), findsNothing);
    },
  );

  testWidgets(
    'la confirmation affiche des noms métier sans UUID et conserve les montants',
    (tester) async {
      const accountId = '11111111-1111-1111-1111-111111111111';
      const envelopeId = '22222222-2222-2222-2222-222222222222';
      const runLineId = '33333333-3333-3333-3333-333333333333';
      await tester.pumpWidget(
        MaterialApp(
          home: BudgetFundingConfirmationDialog(
            funding: const [
              BudgetRunFunding(
                runLineId: runLineId,
                sourceAccountId: accountId,
                envelopeId: envelopeId,
                amountCents: 720000,
              ),
              BudgetRunFunding(
                runLineId: runLineId,
                sourceAccountId: accountId,
                envelopeId: envelopeId,
                amountCents: 280000,
              ),
            ],
            accounts: [
              FinancialAccount(
                id: accountId,
                name: 'Compte TEST',
                type: FinancialAccountType.bank,
                openingBalance: const Money.fromMinorUnits(0),
              ),
            ],
            envelopeNames: {envelopeId: 'Reste épargne'},
            totalCents: 1000000,
            onCancel: () {},
            onConfirm: () {},
          ),
        ),
      );

      expect(find.text('Compte TEST'), findsNWidgets(2));
      expect(find.text('→ Reste épargne'), findsNWidgets(2));
      expect(find.text('7 200,00 MAD'), findsOneWidget);
      expect(find.text('2 800,00 MAD'), findsOneWidget);
      expect(find.text('Total à appliquer : 10 000,00 MAD'), findsOneWidget);
      expect(find.text(accountId), findsNothing);
      expect(find.text(envelopeId), findsNothing);
      expect(find.text(runLineId), findsNothing);
    },
  );

  testWidgets(
    'le total demandé par compte bloque une répartition insuffisante',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BudgetFundingDistributionDialog(
            lines: const [
              RemoteBudgetRunLine(
                id: 'food-line',
                envelopeId: 'food',
                previousBalanceCents: 0,
                rolloverCents: 0,
                plannedCents: 100000,
                resultingCents: 100000,
                priority: 10,
              ),
              RemoteBudgetRunLine(
                id: 'transport-line',
                envelopeId: 'transport',
                previousBalanceCents: 0,
                rolloverCents: 0,
                plannedCents: 80000,
                resultingCents: 80000,
                priority: 20,
              ),
            ],
            accounts: [accounts.first],
            balancesCents: const {'current': 150000},
            envelopeNames: const {
              'food': 'Nourriture',
              'transport': 'Transport',
            },
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('funding-account-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Compte courant').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('funding-account-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Compte courant').last);
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          'Le compte Compte courant ne dispose pas d’un solde suffisant.',
        ),
        findsNWidgets(2),
      );
      expect(
        find.textContaining('Disponible : 1 500,00 MAD'),
        findsNWidgets(2),
      );
      expect(
        find.textContaining('Nécessaire : 1 800,00 MAD'),
        findsNWidgets(2),
      );
      expect(find.textContaining('Manque : 300,00 MAD'), findsNWidgets(2));
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('confirm-funding-distribution')),
            )
            .onPressed,
        isNull,
      );
    },
  );
}
