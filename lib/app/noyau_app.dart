import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/theme/noyau_theme.dart';
import '../core/theme/app_design_system.dart';
import '../features/finance/presentation/finance_overview_page.dart';
import '../features/finance/presentation/imports_page.dart';
import '../features/finance/presentation/accounts_page.dart';
import '../features/finance/presentation/supabase_auth_page.dart';
import '../features/finance/application/providers/active_household_provider.dart';
import '../features/finance/application/providers/remote_accounts_provider.dart';
import '../features/finance/application/providers/supabase_client_provider.dart';
import '../features/dashboard/presentation/financial_dashboard_page.dart';
import '../features/envelopes/presentation/envelope_dashboard_page.dart';
import '../features/savings_goals/presentation/savings_goals_page.dart';
import '../features/shopping_list/presentation/shopping_list_page.dart';
import '../features/priorities/presentation/priorities_page.dart';
import 'finance_shell_navigation.dart';

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
      FinancialDashboardPage(),
      AccountsPage(),
      FinanceOverviewPage(),
      EnvelopeDashboardPage(),
      SavingsGoalsPage(),
      ShoppingListPage(),
      PrioritiesPage(),
      ImportsPage(),
    ];
    final desktop = AppLayout.isDesktop(MediaQuery.sizeOf(context).width);
    final navigation = desktop
        ? Container(
            width: 116,
            color: AppColors.primary,
            child: NavigationRail(
              backgroundColor: Colors.transparent,
              selectedIndex: _selectedIndex,
              labelType: NavigationRailLabelType.all,
              indicatorColor: AppColors.secondary,
              selectedIconTheme: const IconThemeData(color: Colors.white),
              unselectedIconTheme: const IconThemeData(
                color: AppColors.darkTextSecondary,
              ),
              selectedLabelTextStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
              unselectedLabelTextStyle: const TextStyle(
                color: AppColors.darkTextSecondary,
                fontSize: 12,
              ),
              onDestinationSelected: (index) =>
                  setState(() => _selectedIndex = index),
              leading: Padding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.md,
                  bottom: AppSpacing.lg,
                ),
                child: Tooltip(
                  message: 'FINANCIEL PILOTE',
                  child: ClipRRect(
                    borderRadius: AppRadius.button,
                    child: Image.asset(
                      AppAssets.financialPiloteLogo,
                      width: 58,
                      height: 58,
                      fit: BoxFit.cover,
                      semanticLabel: 'FINANCIEL PILOTE',
                    ),
                  ),
                ),
              ),
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: IconButton(
                    tooltip: 'Se déconnecter',
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout_outlined),
                  ),
                ),
              ),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard),
                  label: Text('Pilotage'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.account_balance_outlined),
                  selectedIcon: Icon(Icons.account_balance),
                  label: Text('Comptes'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard),
                  label: Text('Fondation'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.account_balance_wallet_outlined),
                  selectedIcon: Icon(Icons.account_balance_wallet),
                  label: Text('Enveloppes'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.savings_outlined),
                  selectedIcon: Icon(Icons.savings),
                  label: Text('Objectifs'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.shopping_cart_outlined),
                  selectedIcon: Icon(Icons.shopping_cart),
                  label: Text('Achats'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.low_priority_outlined),
                  selectedIcon: Icon(Icons.low_priority),
                  label: Text('Priorités'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.upload_file_outlined),
                  selectedIcon: Icon(Icons.upload_file),
                  label: Text('Import'),
                ),
              ],
            ),
          )
        : null;
    final content = Stack(
      children: [
        IndexedStack(index: _selectedIndex, children: pages),
        if (!desktop)
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: IconButton(
                tooltip: 'Se déconnecter',
                onPressed: _signOut,
                icon: const Icon(Icons.logout_outlined),
              ),
            ),
          ),
      ],
    );
    return FinanceShellNavigation(
      selectDestination: (index) => setState(() => _selectedIndex = index),
      child: Scaffold(
        body: desktop
            ? Row(
                children: [
                  navigation!,
                  const VerticalDivider(width: 1),
                  Expanded(child: content),
                ],
              )
            : content,
        bottomNavigationBar: desktop
            ? null
            : NavigationBar(
                selectedIndex: _selectedIndex,
                onDestinationSelected: (index) =>
                    setState(() => _selectedIndex = index),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.dashboard_outlined),
                    selectedIcon: Icon(Icons.dashboard),
                    label: 'Pilotage',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.account_balance_outlined),
                    selectedIcon: Icon(Icons.account_balance),
                    label: 'Comptes',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.dashboard_outlined),
                    selectedIcon: Icon(Icons.dashboard),
                    label: 'Fondation',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.account_balance_wallet_outlined),
                    selectedIcon: Icon(Icons.account_balance_wallet),
                    label: 'Enveloppes',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.savings_outlined),
                    selectedIcon: Icon(Icons.savings),
                    label: 'Objectifs',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.shopping_cart_outlined),
                    selectedIcon: Icon(Icons.shopping_cart),
                    label: 'Achats',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.low_priority_outlined),
                    selectedIcon: Icon(Icons.low_priority),
                    label: 'Priorités',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.upload_file_outlined),
                    selectedIcon: Icon(Icons.upload_file),
                    label: 'Import',
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _signOut() async {
    await ref.read(supabaseAuthGatewayProvider).signOut();
    ref.invalidate(activeHouseholdProvider);
    ref.invalidate(remoteAccountsProvider);
  }
}
