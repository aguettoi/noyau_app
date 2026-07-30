import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/theme/noyau_theme.dart';
import '../features/finance/presentation/finance_overview_page.dart';
import '../features/finance/presentation/imports_page.dart';
import '../features/finance/presentation/accounts_page.dart';
import '../features/envelopes/presentation/envelope_dashboard_page.dart';

class NoyauApp extends StatelessWidget {
  const NoyauApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Noyau',
    debugShowCheckedModeBanner: false,
    theme: NoyauTheme.light,
    darkTheme: NoyauTheme.dark,
    themeMode: ThemeMode.system,
    supportedLocales: const [Locale('fr')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: const FinanceShell(),
  );
}

class FinanceShell extends StatefulWidget {
  const FinanceShell({super.key});

  @override
  State<FinanceShell> createState() => _FinanceShellState();
}

class _FinanceShellState extends State<FinanceShell> {
  var _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    const pages = [
      FinanceOverviewPage(),
      AccountsPage(),
      EnvelopeDashboardPage(),
      ImportsPage(),
    ];
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.account_balance_outlined),
            selectedIcon: Icon(Icons.account_balance),
            label: 'Comptes',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_outlined),
            selectedIcon: Icon(Icons.account_balance),
            label: 'Fondation',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Enveloppes',
          ),
          NavigationDestination(
            icon: Icon(Icons.upload_file_outlined),
            selectedIcon: Icon(Icons.upload_file),
            label: 'Import',
          ),
        ],
      ),
    );
  }
}
