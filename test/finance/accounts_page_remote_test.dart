import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/finance/application/providers/remote_accounts_provider.dart';
import 'package:noyau_app/features/finance/domain/financial_account.dart';
import 'package:noyau_app/features/finance/presentation/accounts_page.dart';

void main() {
  testWidgets('écran Comptes affiche exclusivement les comptes distants', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remoteAccountsProvider.overrideWith(
            (ref) async => [
              FinancialAccount(
                id: 'remote-account',
                name: 'Compte distant',
                type: FinancialAccountType.bank,
                openingBalance: const Money.fromMinorUnits(100000),
              ),
            ],
          ),
        ],
        child: const MaterialApp(home: AccountsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Compte distant'), findsOneWidget);
    expect(
      find.text('La création manuelle distante sera disponible prochainement.'),
      findsOneWidget,
    );
    final add = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton),
    );
    expect(add.onPressed, isNull);
  });
}
