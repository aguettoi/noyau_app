import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/theme/noyau_theme.dart';
import '../core/theme/app_design_system.dart';
import '../features/finance/presentation/finance_overview_page.dart';
import '../features/finance/presentation/imports_page.dart';
import '../features/finance/presentation/accounts_page.dart';
import '../features/finance/presentation/supabase_auth_page.dart';
import '../features/finance/presentation/household_onboarding_page.dart';
import '../features/finance/presentation/household_members_dialog.dart';
import '../features/finance/presentation/household_settings_page.dart';
import '../features/finance/application/providers/active_household_provider.dart';
import '../features/finance/application/providers/remote_accounts_provider.dart';
import '../features/finance/application/providers/supabase_client_provider.dart';
import '../features/dashboard/presentation/financial_dashboard_page.dart';
import '../features/envelopes/presentation/envelope_dashboard_page.dart';
import '../features/savings_goals/presentation/savings_goals_page.dart';
import '../features/shopping_list/presentation/shopping_list_page.dart';
import '../features/priorities/presentation/priorities_page.dart';
import 'finance_shell_navigation.dart';
import 'global_refresh_provider.dart';

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
      data: (id) {
        if (id == null) return const SupabaseAuthPage();
        final household = ref.watch(activeHouseholdProvider);
        return household.when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (_, _) => const HouseholdOnboardingPage(),
          data: (state) => switch (state.status) {
            ActiveHouseholdStatus.singleHousehold => FinanceShell(
              key: ValueKey('finance-shell-$id'),
            ),
            ActiveHouseholdStatus.multipleHouseholds =>
              const MultipleHouseholdsPage(),
            _ => const HouseholdOnboardingPage(),
          },
        );
      },
    );
  }
}

class FinanceShell extends ConsumerStatefulWidget {
  const FinanceShell({super.key});

  @override
  ConsumerState<FinanceShell> createState() => _FinanceShellState();
}

class _FinanceShellState extends ConsumerState<FinanceShell>
    with WidgetsBindingObserver {
  static const _compactNavigationBreakpoint = 720.0;

  var _selectedIndex = 0;
  var _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshAll(silentSuccess: true);
    }
  }

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
    final compactNavigation =
        !desktop &&
        MediaQuery.sizeOf(context).width < _compactNavigationBreakpoint;
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Membres du foyer',
                        onPressed: _showHouseholdMembers,
                        icon: const Icon(Icons.group_outlined),
                      ),
                      IconButton(
                        key: const Key('household-settings-button'),
                        tooltip: 'Profil et paramètres',
                        onPressed: _showHouseholdSettings,
                        icon: const Icon(Icons.settings_outlined),
                      ),
                      _RefreshButton(
                        refreshing: _refreshing,
                        onPressed: _refreshing ? null : _refreshAll,
                      ),
                      IconButton(
                        tooltip: 'Se déconnecter',
                        onPressed: _signOut,
                        icon: const Icon(Icons.logout_outlined),
                      ),
                    ],
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Membres du foyer',
                    onPressed: _showHouseholdMembers,
                    icon: const Icon(Icons.group_outlined),
                  ),
                  IconButton(
                    key: const Key('household-settings-button'),
                    tooltip: 'Profil et paramètres',
                    onPressed: _showHouseholdSettings,
                    icon: const Icon(Icons.settings_outlined),
                  ),
                  _RefreshButton(
                    refreshing: _refreshing,
                    onPressed: _refreshing ? null : _refreshAll,
                  ),
                  IconButton(
                    tooltip: 'Se déconnecter',
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout_outlined),
                  ),
                ],
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
            : compactNavigation
            ? CompactFinanceNavigation(
                selectedIndex: _selectedIndex,
                onDestinationSelected: (index) =>
                    setState(() => _selectedIndex = index),
              )
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

  Future<void> _showHouseholdMembers() => showDialog<void>(
    context: context,
    builder: (_) => const HouseholdMembersDialog(),
  );

  Future<void> _showHouseholdSettings() => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const HouseholdSettingsPage()),
  );

  Future<void> _refreshAll({bool silentSuccess = false}) async {
    if (_refreshing || !mounted) return;
    setState(() => _refreshing = true);
    try {
      await ref.read(globalRefreshActionProvider)();
      if (!mounted || silentSuccess) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Données actualisées.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Actualisation impossible. Vérifiez votre connexion puis réessayez.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }
}

class _RefreshButton extends StatelessWidget {
  const _RefreshButton({required this.refreshing, required this.onPressed});

  final bool refreshing;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('global-refresh-button'),
    tooltip: refreshing ? 'Actualisation en cours' : 'Actualiser',
    onPressed: onPressed,
    icon: refreshing
        ? const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.refresh),
  );
}

@visibleForTesting
class CompactFinanceNavigation extends StatelessWidget {
  const CompactFinanceNavigation({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  static const _primaryDestinationIndexes = [0, 1, 3, 4];

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) => NavigationBar(
    key: const Key('compact-mobile-navigation'),
    selectedIndex: _primaryDestinationIndexes.contains(selectedIndex)
        ? _primaryDestinationIndexes.indexOf(selectedIndex)
        : 4,
    onDestinationSelected: (index) {
      if (index == 4) {
        _showMoreDestinations(context);
        return;
      }
      onDestinationSelected(_primaryDestinationIndexes[index]);
    },
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
        icon: Icon(Icons.more_horiz),
        selectedIcon: Icon(Icons.more),
        label: 'Plus',
      ),
    ],
  );

  Future<void> _showMoreDestinations(BuildContext context) async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          key: const Key('mobile-more-list'),
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text(
                  'Plus',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text('Autres espaces de FINANCIEL PILOTE'),
              ),
              _moreDestination(
                context,
                index: 2,
                icon: Icons.dashboard_outlined,
                label: 'Fondation',
              ),
              _moreDestination(
                context,
                index: 5,
                icon: Icons.shopping_cart_outlined,
                label: 'Achats',
              ),
              _moreDestination(
                context,
                index: 6,
                icon: Icons.low_priority_outlined,
                label: 'Priorités',
              ),
              _moreDestination(
                context,
                index: 7,
                icon: Icons.upload_file_outlined,
                label: 'Import',
              ),
            ],
          ),
        ),
      ),
    );
    if (!context.mounted || selected == null) return;
    onDestinationSelected(selected);
  }

  Widget _moreDestination(
    BuildContext context, {
    required int index,
    required IconData icon,
    required String label,
  }) => ListTile(
    key: Key('mobile-more-destination-$index'),
    leading: Icon(icon),
    title: Text(label),
    trailing: selectedIndex == index
        ? const Icon(Icons.check, color: AppColors.secondary)
        : const Icon(Icons.chevron_right),
    selected: selectedIndex == index,
    onTap: () => Navigator.of(context).pop(index),
  );
}
