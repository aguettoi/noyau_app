import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/envelopes/application/providers/remote_envelopes_provider.dart';
import 'package:noyau_app/features/envelopes/presentation/envelope_dashboard_page.dart';
import 'package:noyau_app/features/envelopes/presentation/envelope_template_catalog_page.dart';
import 'package:noyau_app/features/finance/application/providers/payment_methods_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_account_balances_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_accounts_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_household_members_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_transactions_provider.dart';
import 'package:noyau_app/features/finance/domain/financial_account.dart';
import 'package:noyau_app/features/finance/domain/transaction_draft.dart';
import 'package:noyau_app/features/finance/domain/transaction_history_item.dart';
import 'package:noyau_app/features/finance/presentation/accounts_page.dart';
import 'package:noyau_app/features/finance/presentation/transactions_page.dart';

void main() {
  final accounts = [
    FinancialAccount(
      id: 'cih',
      name: 'CIH',
      type: FinancialAccountType.bank,
      openingBalance: Money.fromMinorUnits(1245000),
    ),
    FinancialAccount(
      id: 'private',
      name: 'Compte personnel',
      type: FinancialAccountType.bank,
      openingBalance: null,
      canReadBalance: false,
      visibility: 'private',
    ),
  ];
  const envelopes = [
    RemoteEnvelopeBalance(
      id: 'food',
      name: 'Courses',
      inflows: Money.fromMinorUnits(200000),
      outflows: Money.fromMinorUnits(76000),
      balance: Money.fromMinorUnits(124000),
      isSystem: false,
    ),
    RemoteEnvelopeBalance(
      id: 'home',
      name: 'Logement',
      inflows: Money.fromMinorUnits(350000),
      outflows: Money.fromMinorUnits(370000),
      balance: Money.fromMinorUnits(-20000),
      isSystem: false,
    ),
  ];
  final transactions = [
    TransactionHistoryItem(
      id: '1',
      type: LedgerTransactionType.expense,
      occurredAt: DateTime(2026, 11, 3),
      description: 'Courses',
      amount: Money.fromMinorUnits(24000),
      createdAt: DateTime(2026, 11, 3),
      sourceAccountName: 'CIH',
      envelopes: const [
        TransactionEnvelopeReference(id: 'food', name: 'Courses'),
      ],
    ),
    TransactionHistoryItem(
      id: '2',
      type: LedgerTransactionType.income,
      occurredAt: DateTime(2026, 11, 2),
      description: 'Salaire',
      amount: Money.fromMinorUnits(1200000),
      createdAt: DateTime(2026, 11, 2),
      destinationAccountName: 'CIH',
    ),
  ];

  Widget app(
    Widget home, {
    Locale locale = const Locale('fr'),
    bool dark = false,
  }) => ProviderScope(
    overrides: [
      remoteAccountsProvider.overrideWith((ref) async => accounts),
      remoteAccountBalancesProvider.overrideWith(
        (ref) async => {'cih': Money.fromMinorUnits(1245000)},
      ),
      remoteHouseholdMembersProvider.overrideWith((ref) async => const []),
      remoteTransactionsProvider.overrideWith((ref) async => transactions),
      remoteEnvelopeBalancesProvider.overrideWith((ref) async => envelopes),
      remoteEnvelopeHistoryProvider.overrideWith((ref) async => envelopes),
      paymentMethodsProvider.overrideWith((ref) async => const []),
    ],
    child: MaterialApp(
      locale: locale,
      supportedLocales: const [
        Locale('fr'),
        Locale('en'),
        Locale('ar'),
        Locale('ar', 'MA'),
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      darkTheme: ThemeData.dark(useMaterial3: true),
      home: home,
    ),
  );

  Future<void> golden(
    WidgetTester tester,
    String name,
    Widget home,
    Size size, {
    Locale locale = const Locale('fr'),
    bool dark = false,
    Future<void> Function()? interact,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(home, locale: locale, dark: dark));
    await tester.pumpAndSettle();
    if (interact != null) {
      await interact();
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  testWidgets(
    'transactions desktop',
    (tester) => golden(
      tester,
      'd12c_transactions_desktop',
      const TransactionsPage(),
      const Size(1180, 780),
    ),
  );
  testWidgets(
    'transactions mobile',
    (tester) => golden(
      tester,
      'd12c_transactions_mobile',
      const TransactionsPage(),
      const Size(390, 844),
    ),
  );
  testWidgets(
    'new expense desktop',
    (tester) => golden(
      tester,
      'd12c_new_expense_desktop',
      const TransactionsPage(),
      const Size(1180, 900),
      interact: () async =>
          tester.tap(find.byKey(const Key('add-transaction-button'))),
    ),
  );
  testWidgets(
    'new expense mobile',
    (tester) => golden(
      tester,
      'd12c_new_expense_mobile',
      const TransactionsPage(),
      const Size(390, 844),
      interact: () async =>
          tester.tap(find.byKey(const Key('add-transaction-button'))),
    ),
  );
  testWidgets(
    'accounts desktop',
    (tester) => golden(
      tester,
      'd12c_accounts_desktop',
      const AccountsPage(),
      const Size(1180, 780),
    ),
  );
  testWidgets(
    'accounts mobile private',
    (tester) => golden(
      tester,
      'd12c_accounts_mobile_private',
      const AccountsPage(),
      const Size(390, 844),
    ),
  );
  testWidgets(
    'account private desktop',
    (tester) => golden(
      tester,
      'd12c_account_private',
      const AccountsPage(),
      const Size(900, 700),
    ),
  );
  testWidgets(
    'envelopes desktop',
    (tester) => golden(
      tester,
      'd12c_envelopes_desktop',
      const EnvelopeDashboardPage(),
      const Size(1180, 780),
    ),
  );
  testWidgets(
    'envelopes mobile exceeded',
    (tester) => golden(
      tester,
      'd12c_envelopes_mobile',
      const EnvelopeDashboardPage(),
      const Size(390, 844),
    ),
  );
  testWidgets(
    'templates desktop',
    (tester) => golden(
      tester,
      'd12c_templates_desktop',
      const EnvelopeTemplateCatalogPage(),
      const Size(1180, 780),
    ),
  );
  testWidgets(
    'templates mobile',
    (tester) => golden(
      tester,
      'd12c_templates_mobile',
      const EnvelopeTemplateCatalogPage(),
      const Size(390, 844),
    ),
  );
  testWidgets(
    'templates tablet',
    (tester) => golden(
      tester,
      'd12c_templates_tablet',
      const EnvelopeTemplateCatalogPage(),
      const Size(820, 900),
    ),
  );
  testWidgets(
    'dark',
    (tester) => golden(
      tester,
      'd12c_dark',
      const EnvelopeDashboardPage(),
      const Size(1180, 780),
      dark: true,
    ),
  );
  testWidgets(
    'rtl',
    (tester) => golden(
      tester,
      'd12c_rtl',
      const EnvelopeTemplateCatalogPage(),
      const Size(390, 844),
      locale: const Locale('ar'),
    ),
  );
  testWidgets('empty', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remoteAccountsProvider.overrideWith((ref) async => const []),
          remoteAccountBalancesProvider.overrideWith((ref) async => const {}),
          remoteHouseholdMembersProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: AccountsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/d12c_empty.png'),
    );
  });
}
