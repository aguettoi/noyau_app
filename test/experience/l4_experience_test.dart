import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:noyau_app/core/localization/app_locale.dart';
import 'package:noyau_app/features/experience/domain/offline_draft.dart';
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

  testWidgets(
    'landing exposes auth, invitation, help and distribution states',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: LandingPage())),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('landing-login')), findsOneWidget);
      expect(find.byKey(const Key('landing-signup')), findsOneWidget);
      expect(find.byKey(const Key('landing-invitation')), findsOneWidget);
      expect(find.textContaining('Windows — bientôt'), findsOneWidget);
      expect(find.textContaining('Android APK — bientôt'), findsOneWidget);
    },
  );

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
