import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../core/localization/app_locale.dart';
import '../core/theme/noyau_theme.dart';
import '../core/theme/app_design_system.dart';
import '../core/theme/fp_foundation_components.dart';
import '../core/platform/native_notification_adapter.dart';
import '../core/platform/native_notification_contract.dart';
import '../core/platform/platform_link_adapter.dart';
import '../core/platform/platform_link_contract.dart';
import '../features/assistant/presentation/assistant_locale.dart';
import '../features/assistant/presentation/assistant_page.dart';
import '../features/finance/presentation/transactions_page.dart';
import '../features/finance/presentation/imports_page.dart';
import '../features/finance/presentation/accounts_page.dart';
import '../features/finance/presentation/supabase_auth_page.dart';
import '../features/finance/presentation/password_recovery_page.dart';
import '../features/finance/presentation/household_onboarding_page.dart';
import '../features/finance/presentation/household_members_dialog.dart';
import '../features/finance/presentation/household_settings_page.dart';
import '../features/finance/application/providers/active_household_provider.dart';
import '../features/finance/application/providers/remote_accounts_provider.dart';
import '../features/finance/application/providers/supabase_client_provider.dart';
import '../features/dashboard/presentation/financial_dashboard_page.dart';
import '../features/dashboard/application/providers/dashboard_home_provider.dart';
import '../features/envelopes/presentation/envelope_dashboard_page.dart';
import '../features/savings_goals/presentation/savings_goals_page.dart';
import '../features/shopping_list/presentation/shopping_list_page.dart';
import '../features/priorities/presentation/priorities_page.dart';
import '../features/portability/application/household_realtime_provider.dart';
import '../features/portability/presentation/portability_page.dart';
import '../features/reporting/presentation/reports_page.dart';
import '../features/experience/application/experience_provider.dart';
import '../features/experience/application/offline_sync.dart';
import '../features/experience/application/offline_connectivity.dart';
import '../features/experience/presentation/guided_onboarding_page.dart';
import '../features/experience/presentation/help_center_page.dart';
import '../features/experience/presentation/landing_page.dart';
import '../features/experience/presentation/quick_actions_dialog.dart';
import '../features/budget_intelligence/presentation/budget_page.dart';
import '../features/organization/presentation/organization_page.dart';
import '../features/organization/application/organization_provider.dart';
import '../features/organization/application/daily_life_provider.dart';
import '../features/organization/domain/reminder_snooze_policy.dart';
import '../features/organization/presentation/daily_life_page.dart';
import '../features/recurring_finance/presentation/recurring_finance_page.dart';
import '../features/wealth/presentation/wealth_page.dart';
import 'finance_shell_navigation.dart';
import 'fp_adaptive_navigation.dart';
import 'fp_universe_hub.dart';
import 'projects_hub_page.dart';
import 'global_refresh_provider.dart';
import 'app_routes.dart';

final _platformDestinationProvider = StateProvider<String?>((ref) => null);

class _AuthRouterRefresh extends ChangeNotifier {
  void refresh() => notifyListeners();
}

class NoyauApp extends ConsumerStatefulWidget {
  const NoyauApp({super.key});

  @override
  ConsumerState<NoyauApp> createState() => _NoyauAppState();
}

class _NoyauAppState extends ConsumerState<NoyauApp> {
  late final _AuthRouterRefresh _authRefresh;
  late final ProviderSubscription<AsyncValue<String?>> _authSubscription;
  late final GoRouter _router;
  StreamSubscription<PlatformLinkIntent>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    // Shell destinations are real, deep-linkable pages. User-initiated
    // navigation uses push so browser Back/Forward can replay each visit; this
    // opt-in keeps the Web URL aligned with the top imperative route. Technical
    // redirects (Auth, canonicalization and incoming platform links) keep using
    // go/replace semantics below.
    GoRouter.optionURLReflectsImperativeAPIs = true;
    _authRefresh = _AuthRouterRefresh();
    _authSubscription = ref.listenManual(
      supabaseUserIdProvider,
      (_, _) => _authRefresh.refresh(),
    );
    _router = GoRouter(
      refreshListenable: _authRefresh,
      redirect: (context, state) => AppRoutes.authRedirect(
        location: state.uri,
        signedIn: ref.read(supabaseUserIdProvider).valueOrNull != null,
      ),
      routes: [
        for (final path in {
          ...AppRoutes.protectedPaths,
          ...AppRoutes.publicPaths,
        })
          GoRoute(
            path: path,
            builder: (context, state) => _AuthenticationGate(
              location: state.uri.path,
              returnTo: state.uri.queryParameters['returnTo'],
            ),
          ),
      ],
      errorBuilder: (context, state) =>
          const _AuthenticationGate(location: AppRoutes.home),
    );
    _linkSubscription = PlatformLinkAdapter.instance.intents.listen(
      _handlePlatformLink,
    );
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _authSubscription.close();
    _router.dispose();
    _authRefresh.dispose();
    super.dispose();
  }

  void _handlePlatformLink(PlatformLinkIntent intent) {
    switch (intent.kind) {
      case PlatformLinkKind.authCallback:
        return;
      case PlatformLinkKind.passwordReset:
        _router.go(AppRoutes.resetPassword);
      case PlatformLinkKind.invitation:
        _router.go(AppRoutes.invitation);
      case PlatformLinkKind.destination:
        final signedIn =
            ref.read(supabaseAuthGatewayProvider).currentUserId != null;
        if (signedIn) {
          _router.go(switch (intent.value) {
            'money' => AppRoutes.money,
            'household' => AppRoutes.household,
            'projects' => AppRoutes.projects,
            'more' => AppRoutes.more,
            'imports' => AppRoutes.imports,
            _ => AppRoutes.home,
          });
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(appLocaleProvider);
    final words = AppWords(language);
    return MaterialApp.router(
      routerConfig: _router,
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
    );
  }
}

class _AuthenticationGate extends ConsumerWidget {
  const _AuthenticationGate({required this.location, this.returnTo});

  final String location;
  final String? returnTo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(supabaseUserIdProvider);
    return userId.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const SupabaseAuthPage(),
      data: (id) {
        if (location == AppRoutes.resetPassword) {
          return const PasswordRecoveryPage();
        }
        if (id == null) {
          return switch (location) {
            AppRoutes.login ||
            AppRoutes.forgotPassword => const SupabaseAuthPage(),
            AppRoutes.signup => const SupabaseAuthPage(createAccount: true),
            AppRoutes.invitation => const SupabaseAuthPage(
              invitationIntent: true,
            ),
            _ => const LandingPage(),
          };
        }
        final household = ref.watch(activeHouseholdProvider);
        return household.when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (_, _) => const HouseholdOnboardingPage(),
          data: (state) => switch (state.status) {
            ActiveHouseholdStatus.singleHousehold => FinanceShell(
              key: ValueKey('finance-shell-$id'),
              destinationPath: location,
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
  const FinanceShell({super.key, this.destinationPath = AppRoutes.home});

  final String destinationPath;

  @override
  ConsumerState<FinanceShell> createState() => _FinanceShellState();
}

class _FinanceShellState extends ConsumerState<FinanceShell>
    with WidgetsBindingObserver {
  static const _compactNavigationBreakpoint = 720.0;

  var _selectedIndex = 0;
  var _refreshing = false;
  StreamSubscription<NativeNotificationEvent>? _notificationSubscription;

  @override
  void initState() {
    super.initState();
    _selectedIndex = _indexForPath(widget.destinationPath);
    WidgetsBinding.instance.addObserver(this);
    _notificationSubscription = NativeNotificationAdapter.instance.responses
        .listen(_handleNativeNotification);
  }

  @override
  void didUpdateWidget(covariant FinanceShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.destinationPath != widget.destinationPath) {
      _selectedIndex = _indexForPath(widget.destinationPath);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _handleNativeNotification(NativeNotificationEvent event) async {
    if (!mounted) return;
    final actionId = event.actionId;
    final timezone = await ref.read(userTimezoneProvider.future);
    final localNow = ReminderSnoozePolicy.localNow(
      timezone,
      DateTime.now().toUtc(),
    );
    final reminderKey = event.payload.reminderKey == 'daily-entry:native'
        ? 'daily-entry:${localNow.year.toString().padLeft(4, '0')}-'
              '${localNow.month.toString().padLeft(2, '0')}-'
              '${localNow.day.toString().padLeft(2, '0')}'
        : event.payload.reminderKey;
    if (actionId == 'done') {
      await ref
          .read(organizationActionsProvider)
          .finishDailyReminder(reminderKey);
    } else if (actionId == 'not_yet') {
      final now = DateTime.now().toUtc();
      final dueAt = NativeReminderPolicy.notYet(
        nowUtc: now,
        timezone: timezone,
      );
      await ref
          .read(organizationActionsProvider)
          .snooze(reminderKey, dueAt, notYet: true);
      await NativeNotificationAdapter.instance.scheduleOnce(
        id: 2015,
        atUtc: dueAt,
        payload: event.payload,
      );
    }
    if (!mounted) return;
    // A notification response is a technical deep link, not an in-app visit
    // that should be appended to browser history.
    context.go(AppRoutes.household);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Browser focus/visibility changes are frequent (opening DevTools, changing
    // tabs, resizing). Realtime invalidations and the reconnect monitor already
    // refresh Web data; a full refresh here would refetch every finance model.
    if (!kIsWeb && state == AppLifecycleState.resumed) {
      _refreshAll(silentSuccess: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final words = AppWords(ref.watch(appLocaleProvider));
    ref.watch(householdRealtimeProvider);
    ref.listen<String?>(_platformDestinationProvider, (previous, destination) {
      if (destination == null || destination == previous) return;
      setState(() {
        _selectedIndex = switch (destination) {
          'home' => 0,
          'money' => 2,
          'household' => 8,
          'projects' => 9,
          'more' || 'imports' => 10,
          _ => _selectedIndex,
        };
      });
      ref.read(_platformDestinationProvider.notifier).state = null;
      if (destination == 'imports') _push(const ImportsPage());
    });
    final syncState = ref.watch(syncConnectionStateProvider);
    ref.watch(offlineReconnectMonitorProvider);
    ref.listen<AsyncValue<ActiveHouseholdState>>(activeHouseholdProvider, (
      previous,
      next,
    ) {
      final previousId = previous?.valueOrNull?.householdId;
      final nextId = next.valueOrNull?.householdId;
      if (previousId != null && previousId != nextId) {
        unawaited(ref.read(experienceStoreProvider).purgeReadSnapshots());
        ref.read(offlineSnapshotStatusProvider.notifier).state = const {};
      }
    });
    ref.listen(syncConnectionStateProvider, (previous, next) {
      if (next == SyncConnectionState.synchronized && previous != next) {
        unawaited(() async {
          try {
            // A reconnect must not reuse a household membership cached before
            // the outage. Refresh it before replaying any persisted intent;
            // the adapters then verify both user and household again and RLS
            // remains the final authorization boundary.
            ref.invalidate(activeHouseholdProvider);
            await ref.read(activeHouseholdProvider.future);
            final report = await ref
                .read(offlineSyncCoordinatorProvider)
                .synchronize();
            ref.invalidate(offlineDraftsProvider);
            if (report.syncedKinds.contains('grocery_item')) {
              ref.invalidate(groceryItemsProvider);
            }
            if (report.syncedKinds.contains('task')) {
              ref.invalidate(householdTasksProvider);
              ref.invalidate(organizationCalendarProvider);
              ref.invalidate(organizationAlertsProvider);
            }
            if (report.synced > 0) {
              ref.invalidate(dashboardHomeProvider);
            }
          } catch (_) {
            ref.read(syncConnectionStateProvider.notifier).state =
                SyncConnectionState.reconnecting;
          }
        }());
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
              // This legacy rail still mirrors only the eight historical
              // business pages. Universe hubs (household/projects/more) have
              // no destination in it and therefore must not reuse their
              // IndexedStack index as a rail index.
              selectedIndex: _legacyRailIndexForPage(_selectedIndex),
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
              onDestinationSelected: _selectDestination,
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
    final routedPage = _pageForPath(widget.destinationPath);
    final pageContent =
        routedPage ?? IndexedStack(index: _selectedIndex, children: pages);
    final mobileActions = Row(
      key: const Key('shell-mobile-actions'),
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
    );
    final content = desktop
        ? pageContent
        : Column(
            children: [
              SafeArea(
                bottom: false,
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: mobileActions,
                ),
              ),
              Expanded(child: pageContent),
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
            selectDestination: _selectDestination,
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
    1 || 2 || 3 || 5 => FpUniverse.money,
    4 || 6 || 9 => FpUniverse.projects,
    7 || 10 => FpUniverse.more,
    8 => FpUniverse.household,
    _ => throw StateError('Unknown business page index: $index'),
  };

  int? _legacyRailIndexForPage(int pageIndex) => switch (pageIndex) {
    >= 0 && < 8 => pageIndex,
    _ => null,
  };

  int _indexForPath(String path) => switch (path) {
    AppRoutes.accounts => 1,
    AppRoutes.money ||
    AppRoutes.transactions ||
    AppRoutes.budget ||
    AppRoutes.debts ||
    AppRoutes.forecasts ||
    AppRoutes.wealth => 2,
    AppRoutes.envelopes => 3,
    AppRoutes.goals => 4,
    AppRoutes.priorities => 6,
    AppRoutes.imports => 7,
    AppRoutes.household ||
    AppRoutes.calendar ||
    AppRoutes.tasks ||
    AppRoutes.groceries => 8,
    AppRoutes.projects || AppRoutes.simulations => 9,
    AppRoutes.more ||
    AppRoutes.reports ||
    AppRoutes.settings ||
    AppRoutes.help => 10,
    _ => 0,
  };

  Widget? _pageForPath(String path) => switch (path) {
    AppRoutes.home => const FinancialDashboardPage(),
    AppRoutes.accounts => const AccountsPage(),
    AppRoutes.money => _moneyHub(),
    AppRoutes.envelopes => const EnvelopeDashboardPage(),
    AppRoutes.goals => const SavingsGoalsPage(),
    AppRoutes.priorities => const PrioritiesPage(),
    AppRoutes.imports => const ImportsPage(),
    AppRoutes.household => _householdHub(),
    AppRoutes.projects => _projectsHub(),
    AppRoutes.more => _moreHub(),
    AppRoutes.transactions => const TransactionsPage(),
    AppRoutes.budget => const BudgetPage(),
    AppRoutes.debts => const DebtsPage(),
    AppRoutes.forecasts ||
    AppRoutes.calendar ||
    AppRoutes.tasks => const OrganizationPage(),
    AppRoutes.groceries => const DailyLifePage(),
    AppRoutes.wealth => const WealthPage(),
    AppRoutes.simulations => const WealthPage(initialTab: 2),
    AppRoutes.reports => const ReportsPage(),
    AppRoutes.settings => const HouseholdSettingsPage(),
    AppRoutes.help => const HelpCenterPage(),
    _ => null,
  };

  void _openCanonicalRoute(String route) {
    final current = GoRouterState.of(context).uri.path;
    if (current != route) context.push(route);
  }

  void _selectDestination(int index) => _openCanonicalRoute(switch (index) {
    0 => AppRoutes.home,
    1 => AppRoutes.accounts,
    2 => AppRoutes.money,
    3 => AppRoutes.envelopes,
    4 => AppRoutes.goals,
    6 => AppRoutes.priorities,
    7 => AppRoutes.imports,
    8 => AppRoutes.household,
    9 => AppRoutes.projects,
    10 => AppRoutes.more,
    _ => AppRoutes.home,
  });

  void _selectUniverse(FpUniverse universe) =>
      _openCanonicalRoute(switch (universe) {
        FpUniverse.home => AppRoutes.home,
        FpUniverse.money => AppRoutes.money,
        FpUniverse.household => AppRoutes.household,
        FpUniverse.projects => AppRoutes.projects,
        FpUniverse.more => AppRoutes.more,
      });

  Widget _householdHub() => FpUniverseHub(
    titleKey: 'household',
    subtitleKey: 'household.subtitle',
    destinations: [
      FpUniverseDestination(
        labelKey: 'tasks',
        icon: Icons.task_alt,
        open: () => _openCanonicalRoute(AppRoutes.tasks),
      ),
      FpUniverseDestination(
        labelKey: 'daily',
        icon: Icons.home_work_outlined,
        open: () => _openCanonicalRoute(AppRoutes.groceries),
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
        open: () => _openCanonicalRoute(AppRoutes.transactions),
      ),
      FpUniverseDestination(
        labelKey: 'budget',
        icon: Icons.pie_chart_outline,
        open: () => _openCanonicalRoute(AppRoutes.budget),
      ),
      FpUniverseDestination(
        labelKey: 'envelopes',
        icon: Icons.account_balance_wallet_outlined,
        open: () => _openCanonicalRoute(AppRoutes.envelopes),
      ),
      FpUniverseDestination(
        labelKey: 'accounts',
        icon: Icons.account_balance_outlined,
        open: () => _openCanonicalRoute(AppRoutes.accounts),
      ),
      FpUniverseDestination(
        labelKey: 'debts',
        icon: Icons.swap_vert,
        open: () => _openCanonicalRoute(AppRoutes.debts),
      ),
      FpUniverseDestination(
        labelKey: 'forecast',
        icon: Icons.timeline,
        open: () => _openCanonicalRoute(AppRoutes.forecasts),
      ),
      FpUniverseDestination(
        labelKey: 'wealth',
        icon: Icons.assured_workload_outlined,
        open: () => _openCanonicalRoute(AppRoutes.wealth),
      ),
    ],
  );

  Widget _projectsHub() => ProjectsHubPage(
    onOpenGoals: () => _openCanonicalRoute(AppRoutes.goals),
    onOpenPriorities: () => _openCanonicalRoute(AppRoutes.priorities),
    onOpenSimulations: () => _openCanonicalRoute(AppRoutes.simulations),
    onOpenFinancings: () => _openCanonicalRoute(AppRoutes.simulations),
    onOpenWealth: () => _openCanonicalRoute(AppRoutes.wealth),
  );

  Widget _moreHub() => FpUniverseHub(
    titleKey: 'more',
    subtitleKey: 'more.subtitle',
    destinations: [
      FpUniverseDestination(
        labelKey: 'assistant',
        sectionKey: 'more.tools',
        icon: Icons.auto_awesome_outlined,
        open: () => _push(
          AssistantPage(
            onOpenBudget: () => _openCanonicalRoute(AppRoutes.budget),
            onOpenPriorities: () => _openCanonicalRoute(AppRoutes.priorities),
          ),
        ),
      ),
      FpUniverseDestination(
        labelKey: 'reports',
        icon: Icons.manage_search,
        sectionKey: 'more.tools',
        open: () => _openCanonicalRoute(AppRoutes.reports),
      ),
      FpUniverseDestination(
        labelKey: 'imports',
        icon: Icons.upload_file_outlined,
        sectionKey: 'more.tools',
        open: () => _openCanonicalRoute(AppRoutes.imports),
      ),
      FpUniverseDestination(
        labelKey: 'portability',
        icon: Icons.inventory_2_outlined,
        sectionKey: 'more.tools',
        open: _showPortability,
      ),
      FpUniverseDestination(
        labelKey: 'members',
        icon: Icons.group_outlined,
        sectionKey: 'more.householdAccess',
        open: _showHouseholdMembers,
      ),
      FpUniverseDestination(
        labelKey: 'settings',
        icon: Icons.settings_outlined,
        sectionKey: 'more.application',
        open: () => _openCanonicalRoute(AppRoutes.settings),
      ),
      FpUniverseDestination(
        labelKey: 'onboarding',
        icon: Icons.route_outlined,
        sectionKey: 'more.application',
        open: _showGuidedOnboarding,
      ),
      FpUniverseDestination(
        labelKey: 'help',
        icon: Icons.help_outline,
        sectionKey: 'more.application',
        open: () => _openCanonicalRoute(AppRoutes.help),
      ),
      FpUniverseDestination(
        labelKey: 'logout',
        icon: Icons.logout_outlined,
        sectionKey: 'more.application',
        open: _signOut,
      ),
    ],
  );

  Future<void> _showUniversalAdd() async {
    final actions = switch (_universeForIndex(_selectedIndex)) {
      FpUniverse.home => [
        FpAddAction(
          'expense',
          Icons.remove_circle_outline,
          () => _openCanonicalRoute(AppRoutes.transactions),
        ),
        FpAddAction(
          'income',
          Icons.add_circle_outline,
          () => _openCanonicalRoute(AppRoutes.transactions),
        ),
        FpAddAction(
          'transfer',
          Icons.swap_horiz,
          () => _openCanonicalRoute(AppRoutes.transactions),
        ),
        FpAddAction(
          'debt',
          Icons.south_east,
          () => _openCanonicalRoute(AppRoutes.debts),
        ),
        FpAddAction(
          'receivable',
          Icons.north_east,
          () => _push(const ReceivablesPage()),
        ),
        FpAddAction(
          'task',
          Icons.task_alt,
          () => _openCanonicalRoute(AppRoutes.tasks),
        ),
        FpAddAction('grocery', Icons.shopping_cart_outlined, _openGroceryEntry),
        FpAddAction(
          'event',
          Icons.event_outlined,
          () => _openCanonicalRoute(AppRoutes.calendar),
        ),
        FpAddAction(
          'goal',
          Icons.savings_outlined,
          () => _openCanonicalRoute(AppRoutes.goals),
        ),
        FpAddAction(
          'priority',
          Icons.low_priority,
          () => _openCanonicalRoute(AppRoutes.priorities),
        ),
      ],
      FpUniverse.household => [
        FpAddAction(
          'task',
          Icons.task_alt,
          () => _openCanonicalRoute(AppRoutes.tasks),
        ),
        FpAddAction('grocery', Icons.shopping_cart_outlined, _openGroceryEntry),
        FpAddAction(
          'event',
          Icons.event_outlined,
          () => _openCanonicalRoute(AppRoutes.calendar),
        ),
      ],
      FpUniverse.projects => [
        FpAddAction(
          'goal',
          Icons.savings_outlined,
          () => _openCanonicalRoute(AppRoutes.goals),
        ),
        FpAddAction(
          'priority',
          Icons.low_priority,
          () => _openCanonicalRoute(AppRoutes.priorities),
        ),
      ],
      _ => [
        FpAddAction(
          'expense',
          Icons.remove_circle_outline,
          () => _openCanonicalRoute(AppRoutes.transactions),
        ),
        FpAddAction(
          'income',
          Icons.add_circle_outline,
          () => _openCanonicalRoute(AppRoutes.transactions),
        ),
        FpAddAction(
          'transfer',
          Icons.swap_horiz,
          () => _openCanonicalRoute(AppRoutes.transactions),
        ),
        FpAddAction(
          'debt',
          Icons.south_east,
          () => _openCanonicalRoute(AppRoutes.debts),
        ),
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

  void _openGroceryEntry() {
    _openCanonicalRoute(AppRoutes.groceries);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(showGroceryEntryDialog(context, ref));
    });
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
              onOpenBudget: () => _openCanonicalRoute(AppRoutes.budget),
              onOpenPriorities: () => _openCanonicalRoute(AppRoutes.priorities),
            ),
          ),
        ),
        QuickActionItem(
          label: AppWords(ref.read(appLocaleProvider)).text('nav.dashboard'),
          icon: Icons.dashboard_outlined,
          run: () => _openCanonicalRoute(AppRoutes.home),
        ),
        QuickActionItem(
          label: AppWords(ref.read(appLocaleProvider)).text('nav.accounts'),
          icon: Icons.account_balance_outlined,
          run: () => _openCanonicalRoute(AppRoutes.accounts),
        ),
        QuickActionItem(
          label: AppWords(ref.read(appLocaleProvider)).text('nav.envelopes'),
          icon: Icons.account_balance_wallet_outlined,
          run: () => _openCanonicalRoute(AppRoutes.envelopes),
        ),
        QuickActionItem(
          label: AppWords(ref.read(appLocaleProvider)).text('nav.goals'),
          icon: Icons.savings_outlined,
          run: () => _openCanonicalRoute(AppRoutes.goals),
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
    if (mounted) context.go(AppRoutes.login);
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
