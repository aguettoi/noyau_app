import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/theme/noyau_theme.dart';
import '../features/finance/presentation/finance_overview_page.dart';
import '../features/finance/presentation/imports_page.dart';
import '../features/finance/presentation/accounts_page.dart';
import '../features/finance/presentation/supabase_auth_page.dart';
import '../features/finance/application/providers/active_household_provider.dart';
import '../features/finance/application/providers/remote_accounts_provider.dart';
import '../features/finance/application/providers/supabase_client_provider.dart';
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
    home: const _AuthenticationGate(),
  );
}

class _AuthenticationGate extends ConsumerWidget {
  const _AuthenticationGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(supabaseUserIdProvider);
    return userId.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const SupabaseAuthPage(),
      data: (id) =>
          id == null ? const SupabaseAuthPage() : const FinanceShell(),
    );
  }
}

class FinanceShell extends ConsumerStatefulWidget {
  const FinanceShell({super.key});

  @override
  ConsumerState<FinanceShell> createState() => _FinanceShellState();
}

class _FinanceShellState extends ConsumerState<FinanceShell> {
  var _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    const pages = [
      AccountsPage(),
      FinanceOverviewPage(),
      EnvelopeDashboardPage(),
      ImportsPage(),
    ];
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: _selectedIndex, children: pages),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: IconButton(
                tooltip: 'Se déconnecter',
                onPressed: () async {
                  await ref.read(supabaseAuthGatewayProvider).signOut();
                  ref.invalidate(activeHouseholdProvider);
                  ref.invalidate(remoteAccountsProvider);
                },
                icon: const Icon(Icons.logout_outlined),
              ),
            ),
          ),
        ],
      ),
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
