import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/app/fp_adaptive_navigation.dart';
import 'package:noyau_app/app/fp_universe_hub.dart';
import 'package:noyau_app/core/localization/app_locale.dart';
import 'package:noyau_app/core/localization/foundation_locale.dart';
import 'package:noyau_app/core/theme/fp_foundation_components.dart';
import 'package:noyau_app/core/theme/noyau_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('foundation catalog is complete in all four languages', () {
    final reference = FoundationWords.keysFor(AppLanguage.french);
    expect(reference, isNotEmpty);
    for (final language in AppLanguage.values) {
      expect(
        FoundationWords.keysFor(language),
        reference,
        reason: language.name,
      );
      for (final key in reference) {
        expect(FoundationWords(language).text(key).trim(), isNotEmpty);
        expect(FoundationWords(language).text(key), isNot(key));
      }
    }
  });

  testWidgets('desktop exposes five universes and universal add', (
    tester,
  ) async {
    await _pumpFoundation(tester, const Size(1440, 900));
    for (final label in ['Accueil', 'Argent', 'Foyer', 'Projets', 'Plus']) {
      expect(find.text(label), findsAtLeastNWidgets(1));
    }
    expect(find.text('Ajouter'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('mobile exposes central add and keeps projects behind More', (
    tester,
  ) async {
    await _pumpFoundation(tester, const Size(390, 844));
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('Accueil'), findsAtLeastNWidgets(1));
    expect(find.text('Argent'), findsOneWidget);
    expect(find.text('Foyer'), findsAtLeastNWidgets(1));
    expect(find.text('Plus'), findsOneWidget);
    expect(find.text('Projets'), findsNothing);
  });

  testWidgets('privacy and offline states never expose a hidden value', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const Column(
          children: [
            FpMoneyDisplay(value: '12 345 MAD', hidden: true),
            FpPrivacyCard(),
            FpOfflineBanner(state: FpOfflineVisualState.offline),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('12 345 MAD'), findsNothing);
    expect(find.text('••••'), findsOneWidget);
    expect(find.text('Vous êtes hors ligne'), findsOneWidget);
  });

  for (final visual in <(String, Size, Locale, ThemeMode)>[
    ('desktop', const Size(1440, 900), const Locale('fr'), ThemeMode.light),
    ('mobile', const Size(390, 844), const Locale('fr'), ThemeMode.light),
    ('dark', const Size(1440, 900), const Locale('fr'), ThemeMode.dark),
    ('rtl', const Size(390, 844), const Locale('ar'), ThemeMode.light),
  ]) {
    testWidgets('visual proof ${visual.$1}', (tester) async {
      await _pumpFoundation(
        tester,
        visual.$2,
        locale: visual.$3,
        themeMode: visual.$4,
      );
      await expectLater(
        find.byType(FpAdaptiveNavigation),
        matchesGoldenFile('goldens/d12_foundation_${visual.$1}.png'),
      );
    });
  }
}

Future<void> _pumpFoundation(
  WidgetTester tester,
  Size size, {
  Locale locale = const Locale('fr'),
  ThemeMode themeMode = ThemeMode.light,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    _app(
      FpAdaptiveNavigation(
        selected: FpUniverse.home,
        onSelected: (_) {},
        onAdd: () {},
        offlineBanner: const FpOfflineBanner(
          state: FpOfflineVisualState.online,
        ),
        body: FpUniverseHub(
          titleKey: 'home',
          subtitleKey: 'money.subtitle',
          destinations: [
            FpUniverseDestination(
              labelKey: 'transactions',
              icon: Icons.receipt_long,
              open: () {},
            ),
            FpUniverseDestination(
              labelKey: 'budget',
              icon: Icons.pie_chart,
              open: () {},
            ),
            FpUniverseDestination(
              labelKey: 'household',
              icon: Icons.home_work,
              open: () {},
            ),
            FpUniverseDestination(
              labelKey: 'goals',
              icon: Icons.savings,
              open: () {},
            ),
          ],
        ),
      ),
      locale: locale,
      themeMode: themeMode,
    ),
  );
  await tester.pumpAndSettle();
}

Widget _app(
  Widget child, {
  Locale locale = const Locale('fr'),
  ThemeMode themeMode = ThemeMode.light,
}) => MaterialApp(
  locale: locale,
  supportedLocales: const [
    Locale('fr'),
    Locale('en'),
    Locale('ar'),
    Locale('ar', 'MA'),
  ],
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  theme: NoyauTheme.light,
  darkTheme: NoyauTheme.dark,
  themeMode: themeMode,
  home: child,
);
