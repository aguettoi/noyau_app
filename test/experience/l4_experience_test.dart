import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:noyau_app/app/noyau_app.dart';
import 'package:noyau_app/core/localization/app_locale.dart';
import 'package:noyau_app/features/experience/domain/offline_draft.dart';
import 'package:noyau_app/features/experience/application/experience_provider.dart';
import 'package:noyau_app/features/experience/application/offline_sync.dart';
import 'package:noyau_app/features/experience/presentation/help_center_page.dart';
import 'package:noyau_app/features/experience/presentation/landing_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('offline contract keeps financial mutations server-required', () {
    expect(
      classifyOfflineAction('financial_event'),
      OfflineCapability.serverRequired,
    );
    expect(classifyOfflineAction('task'), OfflineCapability.localDraft);
    expect(classifyOfflineAction('calendar'), OfflineCapability.cachedRead);

    final draft = OfflineDraft(
      idempotencyKey: 'stable-key',
      actionKind: 'task',
      updatedAt: DateTime.utc(2026, 10, 26),
      state: OfflineDraftState.pending,
      householdId: 'household',
      memberId: 'member',
    );
    expect(draft.mayCreateFinancialData, isFalse);
    expect(OfflineDraft.fromJson(draft.toJson()).idempotencyKey, 'stable-key');
  });

  test('guided onboarding catalog is complete in all four languages', () {
    const keys = [
      'onboarding.welcome.title',
      'onboarding.welcome.description',
      'onboarding.household.title',
      'onboarding.household.description',
      'onboarding.members.title',
      'onboarding.members.description',
      'onboarding.finance.title',
      'onboarding.finance.description',
      'onboarding.organization.title',
      'onboarding.organization.description',
      'onboarding.privacy.title',
      'onboarding.privacy.description',
      'onboarding.done.title',
      'onboarding.done.description',
      'onboarding.module.organization',
      'onboarding.module.reminders',
      'onboarding.module.privacy',
      'onboarding.module.other',
    ];
    for (final language in AppLanguage.values) {
      final words = AppWords(language);
      for (final key in keys) {
        expect(words.text(key), isNot(key), reason: '${language.name}: $key');
        expect(words.text(key).trim(), isNotEmpty);
      }
    }
  });

  test('Auth catalog has the same non-empty keys in all four languages', () {
    final reference = AppWords.keysFor(
      AppLanguage.french,
    ).where((key) => key.startsWith('auth.')).toSet();
    expect(reference, isNotEmpty);
    for (final language in AppLanguage.values) {
      final keys = AppWords.keysFor(
        language,
      ).where((key) => key.startsWith('auth.')).toSet();
      expect(keys, reference, reason: language.name);
      for (final key in reference) {
        expect(
          AppWords.hasOwnTranslation(language, key),
          isTrue,
          reason: '${language.name}: $key',
        );
      }
    }
  });

  test('Landing catalog has the same non-empty keys in all four languages', () {
    final reference = AppWords.keysFor(
      AppLanguage.french,
    ).where((key) => key.startsWith('landing.')).toSet();
    expect(reference, isNotEmpty);
    for (final language in AppLanguage.values) {
      final keys = AppWords.keysFor(
        language,
      ).where((key) => key.startsWith('landing.')).toSet();
      expect(keys, reference, reason: language.name);
      for (final key in reference) {
        expect(
          AppWords.hasOwnTranslation(language, key),
          isTrue,
          reason: '${language.name}: $key',
        );
      }
    }
  });

  test('Shell catalog has the same non-empty keys in all four languages', () {
    final reference = AppWords.keysFor(AppLanguage.french)
        .where((key) => key.startsWith('nav.') || key.startsWith('shell.'))
        .toSet();
    expect(reference, isNotEmpty);
    for (final language in AppLanguage.values) {
      final keys = AppWords.keysFor(language)
          .where((key) => key.startsWith('nav.') || key.startsWith('shell.'))
          .toSet();
      expect(keys, reference, reason: language.name);
      for (final key in reference) {
        expect(
          AppWords.hasOwnTranslation(language, key),
          isTrue,
          reason: '${language.name}: $key',
        );
      }
    }
  });

  test(
    'Darija keeps ary storage code and uses ar-MA for Material rendering',
    () {
      expect(AppLanguage.darija.storageCode, 'ary');
      expect(AppLanguage.darija.locale, const Locale('ar', 'MA'));
      expect(AppLanguageX.fromCode('ary'), AppLanguage.darija);
    },
  );

  test(
    'automatic language follows environment locales with FR fallback',
    () async {
      for (final scenario in <(Locale, AppLanguage)>[
        (const Locale('fr', 'MA'), AppLanguage.french),
        (const Locale('en', 'US'), AppLanguage.english),
        (const Locale('ar', 'EG'), AppLanguage.arabic),
        (const Locale('de', 'DE'), AppLanguage.french),
      ]) {
        SharedPreferences.setMockInitialValues({});
        final controller = AppLocaleController(
          environmentLocales: () => [scenario.$1],
        );
        await _settleLocaleRestore();
        expect(controller.mode, AppLocaleMode.automatic);
        expect(controller.state, scenario.$2);
        controller.dispose();
      }
    },
  );

  test('manual language overrides environment and survives restart', () async {
    SharedPreferences.setMockInitialValues({});
    final first = AppLocaleController(
      environmentLocales: () => const [Locale('fr')],
    );
    await _settleLocaleRestore();
    await first.select(AppLanguage.english);
    expect(first.mode, AppLocaleMode.manual);
    expect(first.state, AppLanguage.english);
    first.didChangeLocales(const [Locale('ar')]);
    expect(first.state, AppLanguage.english);
    first.dispose();

    final restarted = AppLocaleController(
      environmentLocales: () => const [Locale('fr')],
    );
    await _settleLocaleRestore();
    expect(restarted.mode, AppLocaleMode.manual);
    expect(restarted.state, AppLanguage.english);
    restarted.dispose();
  });

  test(
    'automatic mode resumes environment without persisting detection',
    () async {
      SharedPreferences.setMockInitialValues({});
      var locales = const [Locale('fr')];
      final controller = AppLocaleController(environmentLocales: () => locales);
      await _settleLocaleRestore();
      await controller.select(AppLanguage.darija);
      expect(controller.state.storageCode, 'ary');
      expect(controller.state.locale, const Locale('ar', 'MA'));

      locales = const [Locale('en', 'GB')];
      await controller.useAutomatic();
      expect(controller.mode, AppLocaleMode.automatic);
      expect(controller.state, AppLanguage.english);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString(AppLocaleController.modeKey), 'automatic');
      expect(preferences.containsKey(AppLocaleController.languageKey), isFalse);

      controller.didChangeLocales(const [Locale('ar', 'SA')]);
      expect(controller.state, AppLanguage.arabic);
      controller.dispose();
    },
  );

  test('automatic selects Darija only for an actual ary locale', () async {
    SharedPreferences.setMockInitialValues({});
    final arabic = AppLocaleController(
      environmentLocales: () => const [Locale('ar', 'MA')],
    );
    await _settleLocaleRestore();
    expect(arabic.state, AppLanguage.arabic);
    arabic.dispose();

    final darija = AppLocaleController(
      environmentLocales: () => const [Locale('ary', 'MA')],
    );
    await _settleLocaleRestore();
    expect(darija.state, AppLanguage.darija);
    darija.dispose();
  });

  test(
    'offline synchronization retries with one stable idempotency key',
    () async {
      final store = ExperienceStore();
      final draft = OfflineDraft(
        idempotencyKey: '00000000-0000-4000-8000-000000000001',
        actionKind: 'task',
        updatedAt: DateTime.utc(2026, 10, 26),
        state: OfflineDraftState.pending,
        householdId: 'household',
        memberId: 'member',
        payload: const {'title': 'Test'},
      );
      await store.saveDrafts([draft]);
      final adapter = _LostResponseAdapter();
      final coordinator = OfflineSyncCoordinator(store, {'task': adapter});

      final first = await coordinator.synchronize();
      expect(first.remaining.single.state, OfflineDraftState.actionRequired);
      final second = await coordinator.synchronize();
      expect(second.synced, 1);
      expect(await store.loadDrafts(), isEmpty);
      expect(adapter.canonicalKeys, {'00000000-0000-4000-8000-000000000001'});
    },
  );

  test('parallel reconnect signals share one synchronization cycle', () async {
    final store = ExperienceStore();
    final draft = OfflineDraft(
      idempotencyKey: '00000000-0000-4000-8000-000000000002',
      actionKind: 'task',
      updatedAt: DateTime.utc(2026, 10, 27),
      state: OfflineDraftState.pending,
      householdId: 'household',
      memberId: 'member',
      payload: const {'title': 'Concurrent'},
    );
    await store.saveDrafts([draft]);
    final adapter = _DelayedAdapter();
    final coordinator = OfflineSyncCoordinator(store, {'task': adapter});

    final first = coordinator.synchronize();
    final second = coordinator.synchronize();
    expect(identical(first, second), isTrue);
    await Future.wait([first, second]);

    expect(adapter.calls, 1);
    expect(await store.loadDrafts(), isEmpty);
  });

  testWidgets(
    'landing exposes auth, invitation, help and distribution states',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appLocaleProvider.overrideWith(
              (ref) => AppLocaleController(
                environmentLocales: () => const [Locale('fr')],
              ),
            ),
          ],
          child: const MaterialApp(home: LandingPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('landing-login')), findsOneWidget);
      expect(find.byKey(const Key('landing-signup')), findsOneWidget);
      expect(find.byKey(const Key('landing-invitation')), findsOneWidget);
      expect(find.textContaining('Windows — bientôt'), findsOneWidget);
      expect(find.textContaining('Android APK — bientôt'), findsOneWidget);
    },
  );

  testWidgets('landing renders its catalog in every supported language', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appLocaleProvider.overrideWith((ref) => AppLocaleController()),
        ],
        child: const _LandingHarness(),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(_LandingHarness)),
    );
    for (final language in AppLanguage.values) {
      await container.read(appLocaleProvider.notifier).select(language);
      await tester.pumpAndSettle();
      final words = AppWords(language);
      final title = find.text(words.text('landing.module.finance.title'));
      expect(title, findsOneWidget, reason: language.name);
      expect(
        Directionality.of(tester.element(title)),
        language == AppLanguage.arabic || language == AppLanguage.darija
            ? TextDirection.rtl
            : TextDirection.ltr,
        reason: language.name,
      );
      expect(
        find.text(
          words.format('landing.coming_soon', {
            'platform': words.text('landing.platform.windows'),
          }),
        ),
        findsOneWidget,
        reason: language.name,
      );
    }
  });

  testWidgets('shell navigation follows LTR and RTL in all four languages', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appLocaleProvider.overrideWith((ref) => AppLocaleController()),
        ],
        child: const _ShellNavigationHarness(),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(_ShellNavigationHarness)),
    );
    for (final language in AppLanguage.values) {
      await container.read(appLocaleProvider.notifier).select(language);
      await tester.pumpAndSettle();
      final label = find.text(AppWords(language).text('nav.dashboard'));
      expect(label, findsOneWidget, reason: language.name);
      expect(
        Directionality.of(tester.element(label)),
        language == AppLanguage.arabic || language == AppLanguage.darija
            ? TextDirection.rtl
            : TextDirection.ltr,
        reason: language.name,
      );
    }
  });

  testWidgets('help center filters static guides without network', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HelpCenterPage()));
    await tester.enterText(find.byKey(const Key('help-search')), 'enveloppe');
    await tester.pump();
    expect(find.text('Compte et enveloppe'), findsOneWidget);
    expect(find.text('Créer ou rejoindre un foyer'), findsNothing);
  });

  testWidgets('Arabic locale makes the application direction RTL', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appLocaleProvider.overrideWith((ref) => AppLocaleController()),
        ],
        child: const _LocalizedHarness(),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(_LocalizedHarness)),
    );
    await container.read(appLocaleProvider.notifier).select(AppLanguage.arabic);
    await tester.pumpAndSettle();
    expect(
      Directionality.of(tester.element(find.text('العربية'))),
      TextDirection.rtl,
    );
  });
}

class _LostResponseAdapter implements OfflineDraftAdapter {
  var calls = 0;
  final canonicalKeys = <String>{};
  @override
  String get actionKind => 'task';
  @override
  Future<void> submit(OfflineDraft draft) async {
    calls++;
    canonicalKeys.add(draft.idempotencyKey);
    if (calls == 1) throw Exception('response lost after server success');
  }
}

class _DelayedAdapter implements OfflineDraftAdapter {
  var calls = 0;
  @override
  String get actionKind => 'task';
  @override
  Future<void> submit(OfflineDraft draft) async {
    calls++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _LocalizedHarness extends ConsumerWidget {
  const _LocalizedHarness();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(appLocaleProvider);
    return MaterialApp(
      locale: language.locale,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('fr'),
        Locale('ar'),
        Locale('ary'),
        Locale('en'),
      ],
      home: Scaffold(body: Text(language.label)),
    );
  }
}

class _LandingHarness extends ConsumerWidget {
  const _LandingHarness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(appLocaleProvider);
    return MaterialApp(
      locale: language.locale,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('fr'),
        Locale('ar'),
        Locale('ary'),
        Locale('en'),
      ],
      home: const LandingPage(),
    );
  }
}

class _ShellNavigationHarness extends ConsumerWidget {
  const _ShellNavigationHarness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(appLocaleProvider);
    return MaterialApp(
      locale: language.locale,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('fr'),
        Locale('ar'),
        Locale('ar', 'MA'),
        Locale('en'),
      ],
      home: Scaffold(
        body: const SizedBox.shrink(),
        bottomNavigationBar: CompactFinanceNavigation(
          selectedIndex: 0,
          onDestinationSelected: (_) {},
        ),
      ),
    );
  }
}

Future<void> _settleLocaleRestore() =>
    Future<void>.delayed(const Duration(milliseconds: 20));
