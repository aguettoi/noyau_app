import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/theme/app_design_system.dart';
import 'package:noyau_app/core/theme/noyau_theme.dart';

void main() {
  test('V1 palette keeps brand and financial semantics independent', () {
    expect(AppColors.brandNavy, isNot(AppColors.information));
    expect(AppColors.brandSage, isNot(AppColors.financialPositive));
    expect(AppColors.brandGold, isNot(AppColors.warning));
    expect(AppColors.primary, AppColors.brandNavy);
    expect(AppColors.success, AppColors.financialPositive);
  });

  test(
    'Design Freeze functional palette matches the human-approved contract',
    () {
      expect(AppColors.revenue, const Color(0xFF2563EB));
      expect(AppColors.spending, const Color(0xFFE54864));
      expect(AppColors.savingsFunctional, const Color(0xFF16A34A));
      expect(AppColors.investments, const Color(0xFF7C3AED));
      expect(AppColors.creditsAndDebts, const Color(0xFFDC3545));
      expect(AppColors.accountsAndLiquidity, const Color(0xFF175C9E));
      expect(AppColors.cycleObserved, const Color(0xFFD9467D));
      expect(AppColors.cycleEstimated, const Color(0xFF8B5CF6));
      expect(AppColors.privacyVisible, AppColors.savingsFunctional);
      expect(AppColors.privacyBalanceHidden, const Color(0xFFC2410C));
      expect(AppColors.privacyPrivate, AppColors.creditsAndDebts);
      expect(AppColors.income, AppColors.revenue);
      expect(AppColors.expense, AppColors.spending);
      expect(AppColors.savings, AppColors.savingsFunctional);
      expect(AppColors.investment, AppColors.investments);
      expect(AppColors.debt, AppColors.creditsAndDebts);
    },
  );

  test(
    'functional colors remain distinguishable and usable in light and dark',
    () {
      final light = <Color>[
        AppColors.revenue,
        AppColors.spending,
        AppColors.savingsFunctional,
        AppColors.investments,
        AppColors.creditsAndDebts,
        AppColors.accountsAndLiquidity,
        AppColors.cycleObserved,
        AppColors.cycleEstimated,
        AppColors.privacyBalanceHidden,
      ];
      final dark = <Color>[
        AppColors.darkRevenue,
        AppColors.darkSpending,
        AppColors.darkSavingsFunctional,
        AppColors.darkInvestments,
        AppColors.darkCreditsAndDebts,
        AppColors.darkAccountsAndLiquidity,
        AppColors.darkCycleObserved,
        AppColors.darkCycleEstimated,
        AppColors.darkPrivacyBalanceHidden,
      ];
      expect(light.toSet(), hasLength(light.length));
      for (final color in light) {
        expect(
          _contrastRatio(color, AppColors.background),
          greaterThanOrEqualTo(3),
        );
      }
      for (final color in dark) {
        expect(
          _contrastRatio(color, AppColors.darkBackground),
          greaterThanOrEqualTo(3),
        );
      }
    },
  );

  test('critical light and dark color pairs meet WCAG AA', () {
    final pairs = <(String, Color, Color)>[
      ('light primary text', AppColors.textPrimary, AppColors.background),
      ('light secondary text', AppColors.textSecondary, AppColors.background),
      ('light primary CTA', Colors.white, AppColors.brandNavy),
      ('light positive', AppColors.financialPositive, AppColors.background),
      ('light negative', AppColors.financialNegative, AppColors.background),
      ('light information', AppColors.information, AppColors.background),
      ('light warning', AppColors.warning, AppColors.background),
      (
        'dark primary text',
        AppColors.darkTextPrimary,
        AppColors.darkBackground,
      ),
      (
        'dark secondary text',
        AppColors.darkTextSecondary,
        AppColors.darkBackground,
      ),
      (
        'dark positive',
        AppColors.darkFinancialPositive,
        AppColors.darkBackground,
      ),
      (
        'dark negative',
        AppColors.darkFinancialNegative,
        AppColors.darkBackground,
      ),
      ('dark information', AppColors.darkInformation, AppColors.darkBackground),
      ('dark warning', AppColors.darkWarning, AppColors.darkBackground),
    ];
    for (final pair in pairs) {
      expect(
        _contrastRatio(pair.$2, pair.$3),
        greaterThanOrEqualTo(4.5),
        reason: pair.$1,
      );
    }
  });

  test('theme CTA and error pairs meet WCAG AA in both modes', () {
    for (final theme in [NoyauTheme.light, NoyauTheme.dark]) {
      final scheme = theme.colorScheme;
      expect(
        _contrastRatio(scheme.onPrimary, scheme.primary),
        greaterThanOrEqualTo(4.5),
        reason: '${scheme.brightness.name} primary CTA',
      );
      expect(
        _contrastRatio(scheme.onError, scheme.error),
        greaterThanOrEqualTo(4.5),
        reason: '${scheme.brightness.name} error',
      );
    }
  });

  test('financial typography uses tabular figures at every level', () {
    final scheme = NoyauTheme.light.colorScheme;
    for (final style in [
      AppTypography.displayFinancial(scheme),
      AppTypography.financialAmountLarge(scheme),
      AppTypography.financialAmountMedium(scheme),
      AppTypography.financialAmountSmall(scheme),
    ]) {
      expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
    }
  });

  test('breakpoints are width-driven and platform-independent', () {
    expect(AppLayout.windowClass(390), AppWindowClass.compact);
    expect(AppLayout.windowClass(700), AppWindowClass.medium);
    expect(AppLayout.windowClass(1200), AppWindowClass.expanded);
    expect(AppLayout.windowClass(1600), AppWindowClass.large);
  });

  testWidgets('shared KPI remains readable on compact and expanded widths', (
    tester,
  ) async {
    for (final size in const [Size(320, 640), Size(1440, 900)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: NoyauTheme.light,
          home: const Scaffold(
            body: FpKpiCard(
              title: 'Valeur nette',
              value: '1 234 567,89 MAD',
              detail: 'Actifs moins passifs',
              icon: Icons.account_balance_wallet_outlined,
            ),
          ),
        ),
      );
      expect(find.text('Valeur nette'), findsOneWidget);
      expect(find.text('1 234 567,89 MAD'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets('common loading empty and error states are accessible', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NoyauTheme.light,
        home: const Scaffold(
          body: Column(
            children: [
              FpLoadingState(label: 'Chargement du foyer…'),
              FpEmptyState(
                title: 'Aucune donnée',
                message: 'Ajoutez un élément.',
              ),
              FpErrorState(message: 'Réessayez plus tard.'),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Chargement du foyer…'), findsOneWidget);
    expect(find.text('Aucune donnée'), findsOneWidget);
    expect(find.text('Réessayez plus tard.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('page header stacks actions on compact widths', (tester) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: NoyauTheme.light,
        home: Scaffold(
          body: FpPageHeader(
            title: 'Comptes',
            subtitle: 'Positions réelles',
            actions: [
              FilledButton(onPressed: () {}, child: const Text('Ajouter')),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Comptes'), findsOneWidget);
    expect(find.text('Ajouter'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('theme preserves text scaling and resolves reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NoyauTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(
            textScaler: TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  Text(
                    '1 234 567,89 MAD',
                    style: AppTypography.financialAmountLarge(
                      Theme.of(context).colorScheme,
                    ),
                  ),
                  Text(
                    AppAnimations.resolve(
                      context,
                      AppAnimations.slow,
                    ).inMilliseconds.toString(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('1 234 567,89 MAD'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('foundation primitives inherit RTL without physical padding', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NoyauTheme.light,
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: FpPageHeader(title: 'الحسابات', subtitle: 'ملخص'),
          ),
        ),
      ),
    );
    expect(
      Directionality.of(tester.element(find.text('الحسابات'))),
      TextDirection.rtl,
    );
    expect(tester.takeException(), isNull);
  });
}

double _contrastRatio(Color foreground, Color background) {
  final lighter = foreground.computeLuminance() > background.computeLuminance()
      ? foreground
      : background;
  final darker = identical(lighter, foreground) ? background : foreground;
  return (lighter.computeLuminance() + 0.05) /
      (darker.computeLuminance() + 0.05);
}
