import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';

import '../core/localization/app_locale.dart';
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
import '../features/portability/application/household_realtime_provider.dart';
import '../features/portability/presentation/portability_page.dart';
import '../features/experience/application/experience_provider.dart';
import '../features/experience/application/offline_sync.dart';
import '../features/experience/presentation/guided_onboarding_page.dart';
import '../features/experience/presentation/help_center_page.dart';
import '../features/experience/presentation/landing_page.dart';
import '../features/experience/presentation/quick_actions_dialog.dart';
import '../features/budget_intelligence/presentation/budget_page.dart';
import '../features/organization/presentation/organization_page.dart';
import 'finance_shell_navigation.dart';
import 'global_refresh_provider.dart';

class NoyauApp extends ConsumerWidget {
  const NoyauApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(appLocaleProvider);
    return MaterialApp(
      title: 'FINANCIEL PILOTE',
      debugShowCheckedModeBanner: false,
      theme: NoyauTheme.light,
      darkTheme: NoyauTheme.dark,
      themeMode: ThemeMode.system,
      locale: language.locale,
      supportedLocales: const [
        Locale('fr'),
        Locale('ar'),
        Locale('ary'),
        Locale('en'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _AuthenticationGate(),
    );
  }
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
        if (id == null) return const LandingPage();
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
    ref.watch(householdRealtimeProvider);
    final syncState = ref.watch(syncConnectionStateProvider);
    ref.listen(syncConnectionStateProvider, (previous, next) {
      if (next == SyncConnectionState.synchronized && previous != next) {
        ref.read(offlineSyncCoordinatorProvider).synchronize();
      }
    });
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
    final width = MediaQuery.sizeOf(context).width;
    final desktop = AppLayout.isDesktop(width);
    final largeDesktop = AppLayout.isLarge(width);
    final compactNavigation =
        !desktop &&
        MediaQuery.sizeOf(context).width < _compactNavigationBreakpoint;
    final navigation = desktop
        ? Container(
            width: largeDesktop ? 240 : 116,
            color: AppColors.primary,
            child: NavigationRail(
              backgroundColor: Colors.transparent,
              extended: largeDesktop,
              selectedIndex: _selectedIndex,
              labelType: largeDesktop ? null : NavigationRailLabelType.all,
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
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
                    if (largeDesktop) ...[
                      const SizedBox(width: AppSpacing.sm),
                      const Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'FINANCIEL PILOTE',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Pilotez. Planifiez. Épargnez. Prospérez.',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.darkTextSecondary,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ExperienceMenu(
                        key: const Key('experience-menu'),
                        onSettings: _showHouseholdSettings,
                        onQuickActions: _showQuickActions,
                        onOnboarding: _showGuidedOnboarding,
                        onHelp: _showHelp,
                      ),
                      IconButton(
                        key: const Key('portability-button'),
                        tooltip: 'Recherche et portabilité',
                        onPressed: _showPortability,
                        icon: const Icon(Icons.manage_search),
                      ),
                      IconButton(
                        tooltip: 'Membres du foyer',
                        onPressed: _showHouseholdMembers,
                        icon: const Icon(Icons.group_outlined),
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
                  if (syncState != SyncConnectionState.synchronized)
                    Tooltip(
                      message: syncState == SyncConnectionState.offline
                          ? 'Hors ligne — aucune mutation non confirmée ne sera présentée comme réussie.'
                          : 'Reconnexion en cours…',
                      child: const Icon(Icons.cloud_off_outlined),
                    ),
                  _ExperienceMenu(
                    key: const Key('experience-menu-mobile'),
                    onSettings: _showHouseholdSettings,
                    onQuickActions: _showQuickActions,
                    onOnboarding: _showGuidedOnboarding,
                    onHelp: _showHelp,
                  ),
                  IconButton(
                    key: const Key('portability-button-mobile'),
                    tooltip: 'Recherche et portabilité',
                    onPressed: _showPortability,
                    icon: const Icon(Icons.manage_search),
                  ),
                  IconButton(
                    tooltip: 'Membres du foyer',
                    onPressed: _showHouseholdMembers,
                    icon: const Icon(Icons.group_outlined),
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
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _showQuickActions,
      },
      child: Focus(
        autofocus: true,
        child: FinanceShellNavigation(
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
        ),
      ),
    );
  }

  void _showPortability() => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const PortabilityPage()));

  void _showGuidedOnboarding() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => GuidedOnboardingPage(modules: _onboardingModules()),
    ),
  );

  List<OnboardingModuleLink> _onboardingModules() => [
    OnboardingModuleLink(
      id: 'household',
      label: 'Paramètres du foyer',
      icon: Icons.home_outlined,
      open: () => _push(const HouseholdSettingsPage()),
      isConfigured: () async =>
          (await ref.read(activeHouseholdProvider.future)).householdId != null,
    ),
    OnboardingModuleLink(
      id: 'members',
      label: 'Membres',
      icon: Icons.group_outlined,
      open: _showHouseholdMembers,
      isConfigured: () =>
          _hasRows('household_members', selectColumn: 'user_id'),
    ),
    OnboardingModuleLink(
      id: 'accounts',
      label: 'Comptes et positions',
      icon: Icons.account_balance_outlined,
      open: () => _push(const AccountsPage()),
      isConfigured: () => _hasRows('accounts'),
    ),
    OnboardingModuleLink(
      id: 'envelopes',
      label: 'Enveloppes et budget',
      icon: Icons.account_balance_wallet_outlined,
      open: () => _push(const BudgetPage()),
      isConfigured: () => _hasRows('envelopes'),
    ),
    OnboardingModuleLink(
      id: 'organization',
      label: 'Organisation domestique',
      icon: Icons.event_note_outlined,
      open: () => _push(const OrganizationPage()),
      isConfigured: () async =>
          await _hasRows('household_tasks') ||
          await _hasRows('household_grocery_items'),
    ),
    OnboardingModuleLink(
      id: 'objectives',
      label: 'Objectifs et priorités',
      icon: Icons.flag_outlined,
      open: () => _push(const SavingsGoalsPage()),
      isConfigured: () async =>
          await _hasRows('savings_goals') || await _hasRows('priority_plans'),
    ),
    OnboardingModuleLink(
      id: 'reminders',
      label: 'Rappels et calendrier',
      icon: Icons.notifications_outlined,
      open: () => _push(const OrganizationPage()),
      isConfigured: () => _hasRows('reminder_rules'),
    ),
    OnboardingModuleLink(
      id: 'privacy',
      label: 'Confidentialité et partage',
      icon: Icons.shield_outlined,
      open: () => _push(const AccountsPage()),
      isConfigured: _hasPrivacyConfiguration,
    ),
  ];

  Future<void> _push(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  Future<bool> _hasRows(String table, {String selectColumn = 'id'}) async {
    final household = await ref.read(activeHouseholdProvider.future);
    if (household.householdId == null) return false;
    try {
      final rows = await ref
          .read(supabaseClientProvider)
          .from(table)
          .select(selectColumn)
          .eq('household_id', household.householdId!)
          .limit(1);
      return (rows as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _hasPrivacyConfiguration() async {
    final household = await ref.read(activeHouseholdProvider.future);
    if (household.householdId == null) return false;
    try {
      final rows = await ref
          .read(supabaseClientProvider)
          .rpc(
            'list_account_privacy_summaries_v2',
            params: {'p_household_id': household.householdId},
          );
      return (rows as List).any(
        (row) => (row as Map)['visibility'] != 'visible',
      );
    } catch (_) {
      return false;
    }
  }

  void _showHelp() => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const HelpCenterPage()));

  Future<void> _showQuickActions() => showDialog<void>(
    context: context,
    builder: (_) => QuickActionsDialog(
      actions: [
        QuickActionItem(
          label: 'Pilotage',
          icon: Icons.dashboard_outlined,
          run: () => setState(() => _selectedIndex = 0),
        ),
        QuickActionItem(
          label: 'Comptes',
          icon: Icons.account_balance_outlined,
          run: () => setState(() => _selectedIndex = 1),
        ),
        QuickActionItem(
          label: 'Enveloppes',
          icon: Icons.account_balance_wallet_outlined,
          run: () => setState(() => _selectedIndex = 3),
        ),
        QuickActionItem(
          label: 'Objectifs',
          icon: Icons.savings_outlined,
          run: () => setState(() => _selectedIndex = 4),
        ),
        QuickActionItem(
          label: 'Aide et mode d’emploi',
          icon: Icons.help_outline,
          run: _showHelp,
        ),
        QuickActionItem(
          label: 'Configuration guidée',
          icon: Icons.assistant_outlined,
          run: _showGuidedOnboarding,
        ),
      ],
    ),
  );

  Future<void> _signOut() async {
    await ref.read(experienceStoreProvider).purgePrivateState();
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

class _ExperienceMenu extends StatelessWidget {
  const _ExperienceMenu({
    super.key,
    required this.onSettings,
    required this.onQuickActions,
    required this.onOnboarding,
    required this.onHelp,
  });

  final VoidCallback onSettings;
  final VoidCallback onQuickActions;
  final VoidCallback onOnboarding;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Aide et configuration',
    icon: const Icon(Icons.help_outline),
    onSelected: (value) {
      if (value == 'settings') {
        onSettings();
      } else if (value == 'quick') {
        onQuickActions();
      } else if (value == 'onboarding') {
        onOnboarding();
      } else {
        onHelp();
      }
    },
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'settings', child: Text('Profil et paramètres')),
      PopupMenuItem(value: 'quick', child: Text('Actions rapides (Ctrl+K)')),
      PopupMenuItem(value: 'onboarding', child: Text('Configuration guidée')),
      PopupMenuItem(value: 'help', child: Text('Aide et mode d’emploi')),
    ],
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
