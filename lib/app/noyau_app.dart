import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';

import '../core/localization/app_locale.dart';
import '../core/theme/noyau_theme.dart';
import '../core/theme/app_design_system.dart';
import '../core/theme/fp_foundation_components.dart';
import '../features/assistant/presentation/assistant_locale.dart';
import '../features/assistant/presentation/assistant_page.dart';
import '../features/finance/presentation/transactions_page.dart';
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
import '../features/organization/presentation/daily_life_page.dart';
import '../features/recurring_finance/presentation/recurring_finance_page.dart';
import '../features/wealth/presentation/wealth_page.dart';
import 'finance_shell_navigation.dart';
import 'fp_adaptive_navigation.dart';
import 'fp_universe_hub.dart';
import 'projects_hub_page.dart';
import 'global_refresh_provider.dart';

class NoyauApp extends ConsumerWidget {
  const NoyauApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(appLocaleProvider);
    final words = AppWords(language);
    return MaterialApp(
      title: words.text('title'),
      debugShowCheckedModeBanner: false,
      theme: NoyauTheme.light,
      darkTheme: NoyauTheme.dark,
      themeMode: ThemeMode.system,
      locale: language.locale,
      supportedLocales: const [
        Locale('fr'),
        Locale('ar'),
        Locale('ar', 'MA'),
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
    final words = AppWords(ref.watch(appLocaleProvider));
    ref.watch(householdRealtimeProvider);
    final syncState = ref.watch(syncConnectionStateProvider);
    ref.listen(syncConnectionStateProvider, (previous, next) {
      if (next == SyncConnectionState.synchronized && previous != next) {
        ref
            .read(offlineSyncCoordinatorProvider)
            .synchronize()
            .whenComplete(() => ref.invalidate(offlineDraftsProvider));
      }
    });
    final pages = <Widget>[
      const FinancialDashboardPage(),
      const AccountsPage(),
      _moneyHub(),
      const EnvelopeDashboardPage(),
      const SavingsGoalsPage(),
      const ShoppingListPage(),
      const PrioritiesPage(),
      const ImportsPage(),
      _householdHub(),
      _projectsHub(),
      _moreHub(),
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
                      message: words.text('title'),
                      child: ClipRRect(
                        borderRadius: AppRadius.button,
                        child: Image.asset(
                          AppAssets.financialPiloteLogo,
                          width: 58,
                          height: 58,
                          fit: BoxFit.cover,
                          semanticLabel: words.text('title'),
                        ),
                      ),
                    ),
                    if (largeDesktop) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              words.text('title'),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              words.text('tagline'),
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
                        tooltip: words.text('nav.search'),
                        onPressed: _showPortability,
                        icon: const Icon(Icons.manage_search),
                      ),
                      IconButton(
                        tooltip: words.text('nav.members'),
                        onPressed: _showHouseholdMembers,
                        icon: const Icon(Icons.group_outlined),
                      ),
                      _RefreshButton(
                        refreshing: _refreshing,
                        onPressed: _refreshing ? null : _refreshAll,
                      ),
                      IconButton(
                        tooltip: words.text('nav.logout'),
                        onPressed: _signOut,
                        icon: const Icon(Icons.logout_outlined),
                      ),
                    ],
                  ),
                ),
              ),
              destinations: [
                NavigationRailDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard),
                  label: Text(words.text('nav.dashboard')),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.account_balance_outlined),
                  selectedIcon: Icon(Icons.account_balance),
                  label: Text(words.text('nav.accounts')),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard),
                  label: Text(words.text('nav.foundation')),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.account_balance_wallet_outlined),
                  selectedIcon: Icon(Icons.account_balance_wallet),
                  label: Text(words.text('nav.envelopes')),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.savings_outlined),
                  selectedIcon: Icon(Icons.savings),
                  label: Text(words.text('nav.goals')),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.shopping_cart_outlined),
                  selectedIcon: Icon(Icons.shopping_cart),
                  label: Text(words.text('nav.shopping')),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.low_priority_outlined),
                  selectedIcon: Icon(Icons.low_priority),
                  label: Text(words.text('nav.priorities')),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.upload_file_outlined),
                  selectedIcon: Icon(Icons.upload_file),
                  label: Text(words.text('nav.import')),
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
                          ? words.text('shell.offline')
                          : words.text('shell.reconnecting'),
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
                    tooltip: words.text('nav.search'),
                    onPressed: _showPortability,
                    icon: const Icon(Icons.manage_search),
                  ),
                  IconButton(
                    tooltip: words.text('nav.members'),
                    onPressed: _showHouseholdMembers,
                    icon: const Icon(Icons.group_outlined),
                  ),
                  _RefreshButton(
                    refreshing: _refreshing,
                    onPressed: _refreshing ? null : _refreshAll,
                  ),
                  IconButton(
                    tooltip: words.text('nav.logout'),
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout_outlined),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
    // Keep the legacy navigation construction exercised until every feature
    // adopts the universe contract. Historical destinations remain in the
    // IndexedStack and are still reachable through the new hubs.
    assert(navigation == null || desktop);
    assert(!compactNavigation || !desktop);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _showQuickActions,
      },
      child: FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        child: Focus(
          autofocus: true,
          child: FinanceShellNavigation(
            selectDestination: (index) =>
                setState(() => _selectedIndex = index),
            child: FpAdaptiveNavigation(
              selected: _universeForIndex(_selectedIndex),
              onSelected: _selectUniverse,
              onAdd: _showUniversalAdd,
              offlineBanner: FpOfflineBanner(
                state: switch (syncState) {
                  SyncConnectionState.offline => FpOfflineVisualState.offline,
                  SyncConnectionState.reconnecting =>
                    FpOfflineVisualState.reconnecting,
                  SyncConnectionState.connecting =>
                    FpOfflineVisualState.reconnecting,
                  SyncConnectionState.synchronized =>
                    FpOfflineVisualState.online,
                },
              ),
              body: content,
            ),
          ),
        ),
      ),
    );
  }

  FpUniverse _universeForIndex(int index) => switch (index) {
    0 => FpUniverse.home,
    8 => FpUniverse.household,
    9 => FpUniverse.projects,
    10 => FpUniverse.more,
    _ => FpUniverse.money,
  };

  void _selectUniverse(FpUniverse universe) => setState(() {
    _selectedIndex = switch (universe) {
      FpUniverse.home => 0,
      FpUniverse.money => 2,
      FpUniverse.household => 8,
      FpUniverse.projects => 9,
      FpUniverse.more => 10,
    };
  });

  Widget _householdHub() => FpUniverseHub(
    titleKey: 'household',
    subtitleKey: 'household.subtitle',
    destinations: [
      FpUniverseDestination(
        labelKey: 'tasks',
        icon: Icons.task_alt,
        open: () => _push(const OrganizationPage()),
      ),
      FpUniverseDestination(
        labelKey: 'daily',
        icon: Icons.home_work_outlined,
        open: () => _push(const DailyLifePage()),
      ),
      FpUniverseDestination(
        labelKey: 'recurring',
        icon: Icons.repeat,
        open: () => _push(const RecurringFinancePage()),
      ),
      FpUniverseDestination(
        labelKey: 'members',
        icon: Icons.group_outlined,
        open: _showHouseholdMembers,
      ),
    ],
  );

  Widget _moneyHub() => FpUniverseHub(
    titleKey: 'money',
    subtitleKey: 'money.subtitle',
    destinations: [
      FpUniverseDestination(
        labelKey: 'transactions',
        icon: Icons.receipt_long_outlined,
        open: () => _push(const TransactionsPage()),
      ),
      FpUniverseDestination(
        labelKey: 'budget',
        icon: Icons.pie_chart_outline,
        open: () => _push(const BudgetPage()),
      ),
      FpUniverseDestination(
        labelKey: 'envelopes',
        icon: Icons.account_balance_wallet_outlined,
        open: () => setState(() => _selectedIndex = 3),
      ),
      FpUniverseDestination(
        labelKey: 'accounts',
        icon: Icons.account_balance_outlined,
        open: () => setState(() => _selectedIndex = 1),
      ),
      FpUniverseDestination(
        labelKey: 'debts',
        icon: Icons.swap_vert,
        open: () => _push(const DebtsPage()),
      ),
      FpUniverseDestination(
        labelKey: 'forecast',
        icon: Icons.timeline,
        open: () => _push(const OrganizationPage()),
      ),
      FpUniverseDestination(
        labelKey: 'wealth',
        icon: Icons.assured_workload_outlined,
        open: () => _push(const WealthPage()),
      ),
    ],
  );

  Widget _projectsHub() => ProjectsHubPage(
    onOpenGoals: () => setState(() => _selectedIndex = 4),
    onOpenPriorities: () => setState(() => _selectedIndex = 6),
    onOpenSimulations: () => _push(const WealthPage(initialTab: 2)),
    onOpenFinancings: () => _push(const WealthPage(initialTab: 2)),
    onOpenWealth: () => _push(const WealthPage()),
  );

  Widget _moreHub() => FpUniverseHub(
    titleKey: 'more',
    subtitleKey: 'more.subtitle',
    destinations: [
      FpUniverseDestination(
        labelKey: 'assistant',
        icon: Icons.auto_awesome_outlined,
        open: () => _push(
          AssistantPage(
            onOpenBudget: () => _push(const BudgetPage()),
            onOpenPriorities: () => _push(const PrioritiesPage()),
          ),
        ),
      ),
      FpUniverseDestination(
        labelKey: 'reports',
        icon: Icons.manage_search,
        open: _showPortability,
      ),
      FpUniverseDestination(
        labelKey: 'imports',
        icon: Icons.upload_file_outlined,
        open: () => setState(() => _selectedIndex = 7),
      ),
      FpUniverseDestination(
        labelKey: 'settings',
        icon: Icons.settings_outlined,
        open: _showHouseholdSettings,
      ),
      FpUniverseDestination(
        labelKey: 'onboarding',
        icon: Icons.route_outlined,
        open: _showGuidedOnboarding,
      ),
      FpUniverseDestination(
        labelKey: 'help',
        icon: Icons.help_outline,
        open: _showHelp,
      ),
    ],
  );

  Future<void> _showUniversalAdd() async {
    final actions = switch (_universeForIndex(_selectedIndex)) {
      FpUniverse.home => [
        FpAddAction(
          'expense',
          Icons.remove_circle_outline,
          () => _push(const TransactionsPage()),
        ),
        FpAddAction(
          'income',
          Icons.add_circle_outline,
          () => _push(const TransactionsPage()),
        ),
        FpAddAction(
          'transfer',
          Icons.swap_horiz,
          () => _push(const TransactionsPage()),
        ),
        FpAddAction('debt', Icons.south_east, () => _push(const DebtsPage())),
        FpAddAction(
          'receivable',
          Icons.north_east,
          () => _push(const ReceivablesPage()),
        ),
        FpAddAction(
          'task',
          Icons.task_alt,
          () => _push(const OrganizationPage()),
        ),
        FpAddAction(
          'grocery',
          Icons.shopping_cart_outlined,
          () => _push(const DailyLifePage()),
        ),
        FpAddAction(
          'event',
          Icons.event_outlined,
          () => _push(const OrganizationPage()),
        ),
        FpAddAction(
          'goal',
          Icons.savings_outlined,
          () => setState(() => _selectedIndex = 4),
        ),
        FpAddAction(
          'priority',
          Icons.low_priority,
          () => setState(() => _selectedIndex = 6),
        ),
      ],
      FpUniverse.household => [
        FpAddAction(
          'task',
          Icons.task_alt,
          () => _push(const OrganizationPage()),
        ),
        FpAddAction(
          'grocery',
          Icons.shopping_cart_outlined,
          () => _push(const DailyLifePage()),
        ),
        FpAddAction(
          'event',
          Icons.event_outlined,
          () => _push(const OrganizationPage()),
        ),
      ],
      FpUniverse.projects => [
        FpAddAction(
          'goal',
          Icons.savings_outlined,
          () => setState(() => _selectedIndex = 4),
        ),
        FpAddAction(
          'priority',
          Icons.low_priority,
          () => setState(() => _selectedIndex = 6),
        ),
      ],
      _ => [
        FpAddAction(
          'expense',
          Icons.remove_circle_outline,
          () => _push(const TransactionsPage()),
        ),
        FpAddAction(
          'income',
          Icons.add_circle_outline,
          () => _push(const TransactionsPage()),
        ),
        FpAddAction(
          'transfer',
          Icons.swap_horiz,
          () => _push(const TransactionsPage()),
        ),
        FpAddAction('debt', Icons.south_east, () => _push(const DebtsPage())),
        FpAddAction(
          'receivable',
          Icons.north_east,
          () => _push(const ReceivablesPage()),
        ),
      ],
    };
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => FpUniversalAddSheet(
        universe: _universeForIndex(_selectedIndex),
        actions: actions,
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
      label: AppWords(
        ref.read(appLocaleProvider),
      ).text('shell.onboarding.household_settings'),
      icon: Icons.home_outlined,
      open: () => _push(const HouseholdSettingsPage()),
      isConfigured: () async =>
          (await ref.read(activeHouseholdProvider.future)).householdId != null,
    ),
    OnboardingModuleLink(
      id: 'members',
      label: AppWords(ref.read(appLocaleProvider)).text('nav.members'),
      icon: Icons.group_outlined,
      open: _showHouseholdMembers,
      isConfigured: () =>
          _hasRows('household_members', selectColumn: 'user_id'),
    ),
    OnboardingModuleLink(
      id: 'accounts',
      label: AppWords(
        ref.read(appLocaleProvider),
      ).text('shell.onboarding.accounts_positions'),
      icon: Icons.account_balance_outlined,
      open: () => _push(const AccountsPage()),
      isConfigured: () => _hasRows('accounts'),
    ),
    OnboardingModuleLink(
      id: 'envelopes',
      label: AppWords(
        ref.read(appLocaleProvider),
      ).text('shell.onboarding.envelopes_budget'),
      icon: Icons.account_balance_wallet_outlined,
      open: () => _push(const BudgetPage()),
      isConfigured: () => _hasRows('envelopes'),
    ),
    OnboardingModuleLink(
      id: 'organization',
      label: AppWords(
        ref.read(appLocaleProvider),
      ).text('onboarding.module.organization'),
      icon: Icons.event_note_outlined,
      open: () => _push(const OrganizationPage()),
      isConfigured: () async =>
          await _hasRows('household_tasks') ||
          await _hasRows('household_grocery_items'),
    ),
    OnboardingModuleLink(
      id: 'objectives',
      label: AppWords(
        ref.read(appLocaleProvider),
      ).text('shell.onboarding.goals_priorities'),
      icon: Icons.flag_outlined,
      open: () => _push(const SavingsGoalsPage()),
      isConfigured: () async =>
          await _hasRows('savings_goals') || await _hasRows('priority_plans'),
    ),
    OnboardingModuleLink(
      id: 'reminders',
      label: AppWords(
        ref.read(appLocaleProvider),
      ).text('onboarding.module.reminders'),
      icon: Icons.notifications_outlined,
      open: () => _push(const OrganizationPage()),
      isConfigured: () => _hasRows('reminder_rules'),
    ),
    OnboardingModuleLink(
      id: 'privacy',
      label: AppWords(
        ref.read(appLocaleProvider),
      ).text('onboarding.module.privacy'),
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
          label: AssistantWords(
            ref.read(appLocaleProvider),
          ).text('assistant.title'),
          icon: Icons.auto_awesome_outlined,
          run: () => _push(
            AssistantPage(
              onOpenBudget: () => _push(const BudgetPage()),
              onOpenPriorities: () => _push(const PrioritiesPage()),
            ),
          ),
        ),
        QuickActionItem(
          label: AppWords(ref.read(appLocaleProvider)).text('nav.dashboard'),
          icon: Icons.dashboard_outlined,
          run: () => setState(() => _selectedIndex = 0),
        ),
        QuickActionItem(
          label: AppWords(ref.read(appLocaleProvider)).text('nav.accounts'),
          icon: Icons.account_balance_outlined,
          run: () => setState(() => _selectedIndex = 1),
        ),
        QuickActionItem(
          label: AppWords(ref.read(appLocaleProvider)).text('nav.envelopes'),
          icon: Icons.account_balance_wallet_outlined,
          run: () => setState(() => _selectedIndex = 3),
        ),
        QuickActionItem(
          label: AppWords(ref.read(appLocaleProvider)).text('nav.goals'),
          icon: Icons.savings_outlined,
          run: () => setState(() => _selectedIndex = 4),
        ),
        QuickActionItem(
          label: AppWords(ref.read(appLocaleProvider)).text('help'),
          icon: Icons.help_outline,
          run: _showHelp,
        ),
        QuickActionItem(
          label: AppWords(ref.read(appLocaleProvider)).text('onboarding.title'),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppWords(ref.read(appLocaleProvider)).text('shell.refresh.success'),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppWords(ref.read(appLocaleProvider)).text('shell.refresh.error'),
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
    tooltip: AppWords.of(
      context,
    ).text(refreshing ? 'shell.refresh.in_progress' : 'shell.refresh.action'),
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
    tooltip: AppWords.of(context).text('shell.help_configuration'),
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
    itemBuilder: (context) => [
      PopupMenuItem(
        value: 'settings',
        child: Text(AppWords.of(context).text('shell.profile_settings')),
      ),
      PopupMenuItem(
        value: 'quick',
        child: Text(AppWords.of(context).text('shell.quick.ctrl_k')),
      ),
      PopupMenuItem(
        value: 'onboarding',
        child: Text(AppWords.of(context).text('onboarding.title')),
      ),
      PopupMenuItem(
        value: 'help',
        child: Text(AppWords.of(context).text('help')),
      ),
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
    destinations: [
      NavigationDestination(
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard),
        label: AppWords.of(context).text('nav.dashboard'),
      ),
      NavigationDestination(
        icon: Icon(Icons.account_balance_outlined),
        selectedIcon: Icon(Icons.account_balance),
        label: AppWords.of(context).text('nav.accounts'),
      ),
      NavigationDestination(
        icon: Icon(Icons.account_balance_wallet_outlined),
        selectedIcon: Icon(Icons.account_balance_wallet),
        label: AppWords.of(context).text('nav.envelopes'),
      ),
      NavigationDestination(
        icon: Icon(Icons.savings_outlined),
        selectedIcon: Icon(Icons.savings),
        label: AppWords.of(context).text('nav.goals'),
      ),
      NavigationDestination(
        icon: Icon(Icons.more_horiz),
        selectedIcon: Icon(Icons.more),
        label: AppWords.of(context).text('nav.more'),
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
              ListTile(
                title: Text(
                  AppWords.of(context).text('nav.more'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(AppWords.of(context).text('nav.more_spaces')),
              ),
              _moreDestination(
                context,
                index: 2,
                icon: Icons.dashboard_outlined,
                label: AppWords.of(context).text('nav.foundation'),
              ),
              _moreDestination(
                context,
                index: 5,
                icon: Icons.shopping_cart_outlined,
                label: AppWords.of(context).text('nav.shopping'),
              ),
              _moreDestination(
                context,
                index: 6,
                icon: Icons.low_priority_outlined,
                label: AppWords.of(context).text('nav.priorities'),
              ),
              _moreDestination(
                context,
                index: 7,
                icon: Icons.upload_file_outlined,
                label: AppWords.of(context).text('nav.import'),
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
