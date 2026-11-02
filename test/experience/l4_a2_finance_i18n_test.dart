import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/localization/app_locale.dart';
import 'package:noyau_app/core/localization/accounts_locale.dart';
import 'package:noyau_app/core/localization/finance_locale.dart';
import 'package:noyau_app/core/localization/finance_residual_locale.dart';
import 'package:noyau_app/core/localization/kpi_reporting_locale.dart';
import 'package:noyau_app/core/localization/member_compensations_locale.dart';
import 'package:noyau_app/core/localization/portability_locale.dart';
import 'package:noyau_app/core/localization/recurring_finance_locale.dart';
import 'package:noyau_app/core/localization/home_auto_locale.dart';
import 'package:noyau_app/core/localization/dashboard_v2_locale.dart';
import 'package:noyau_app/core/localization/cutover_locale.dart';
import 'package:noyau_app/core/localization/savings_goals_locale.dart';
import 'package:noyau_app/core/localization/import_preview_locale.dart';
import 'package:noyau_app/core/localization/historical_analytics_locale.dart';
import 'package:noyau_app/core/localization/imports_locale.dart';
import 'package:noyau_app/core/localization/wealth_locale.dart';
import 'package:noyau_app/core/localization/monthly_close_locale.dart';
import 'package:noyau_app/core/localization/envelopes_locale.dart';
import 'package:noyau_app/core/localization/budget_locale.dart';
import 'package:noyau_app/core/localization/budget_contribution_locale.dart';
import 'package:noyau_app/core/localization/budget_scenarios_locale.dart';
import 'package:noyau_app/core/localization/cashflow_locale.dart';
import 'package:noyau_app/core/localization/budget_runs_locale.dart';
import 'package:noyau_app/core/localization/budget_monthly_locale.dart';
import 'package:noyau_app/core/localization/programmable_budget_locale.dart';
import 'package:noyau_app/core/localization/priorities_locale.dart';
import 'package:noyau_app/core/localization/transactions_locale.dart';

void main() {
  test('A2 monthly close catalog is complete', () {
    final reference = MonthlyCloseWords.keysFor(AppLanguage.french);
    for (final language in AppLanguage.values) {
      expect(MonthlyCloseWords.keysFor(language), reference);
      for (final key in reference) {
        expect(MonthlyCloseWords.hasOwnTranslation(language, key), isTrue);
      }
    }
  });
  test('A2 wealth catalog is complete', () {
    final reference = WealthWords.keysFor(AppLanguage.french);
    for (final language in AppLanguage.values) {
      expect(WealthWords.keysFor(language), reference);
      for (final key in reference) {
        expect(WealthWords.hasOwnTranslation(language, key), isTrue);
      }
    }
  });
  test('A2 imports catalog is complete', () {
    final reference = ImportsWords.keysFor(AppLanguage.french);
    for (final language in AppLanguage.values) {
      expect(ImportsWords.keysFor(language), reference);
      for (final key in reference) {
        expect(ImportsWords.hasOwnTranslation(language, key), isTrue);
      }
    }
  });
  test('A2 historical analytics catalog is complete', () {
    final reference = HistoricalAnalyticsWords.keysFor(AppLanguage.french);
    for (final language in AppLanguage.values) {
      expect(HistoricalAnalyticsWords.keysFor(language), reference);
      for (final key in reference) {
        expect(
          HistoricalAnalyticsWords.hasOwnTranslation(language, key),
          isTrue,
        );
      }
    }
  });
  test('A2 import preview catalog is complete', () {
    final reference = ImportPreviewWords.keysFor(AppLanguage.french);
    for (final language in AppLanguage.values) {
      expect(ImportPreviewWords.keysFor(language), reference);
      for (final key in reference) {
        expect(ImportPreviewWords.hasOwnTranslation(language, key), isTrue);
      }
    }
  });
  test('A2 savings goals catalog is complete', () {
    final reference = SavingsGoalsWords.keysFor(AppLanguage.french);
    for (final language in AppLanguage.values) {
      expect(SavingsGoalsWords.keysFor(language), reference);
      for (final key in reference) {
        expect(SavingsGoalsWords.hasOwnTranslation(language, key), isTrue);
      }
    }
  });
  test('A2 cutover catalog is complete', () {
    final reference = CutoverWords.keysFor(AppLanguage.french);
    for (final language in AppLanguage.values) {
      expect(CutoverWords.keysFor(language), reference);
      for (final key in reference) {
        expect(CutoverWords.hasOwnTranslation(language, key), isTrue);
      }
    }
  });

  test('A2 dashboard V2 catalog is complete', () {
    final reference = DashboardV2Words.keysFor(AppLanguage.french);
    for (final language in AppLanguage.values) {
      expect(DashboardV2Words.keysFor(language), reference);
      for (final key in reference) {
        expect(DashboardV2Words.hasOwnTranslation(language, key), isTrue);
      }
    }
  });

  test('A2 home and vehicle catalog is complete', () {
    final reference = HomeAutoWords.keysFor(AppLanguage.french);
    for (final language in AppLanguage.values) {
      expect(HomeAutoWords.keysFor(language), reference);
      for (final key in reference) {
        expect(HomeAutoWords.hasOwnTranslation(language, key), isTrue);
      }
    }
  });

  test('A2 recurring finance catalog is complete', () {
    final reference = RecurringFinanceWords.keysFor(AppLanguage.french);
    for (final language in AppLanguage.values) {
      expect(RecurringFinanceWords.keysFor(language), reference);
      for (final key in reference) {
        expect(RecurringFinanceWords.hasOwnTranslation(language, key), isTrue);
      }
    }
  });

  test('A2 portability catalog is complete', () {
    final reference = PortabilityWords.keysFor(AppLanguage.french);
    for (final language in AppLanguage.values) {
      expect(PortabilityWords.keysFor(language), reference);
      for (final key in reference) {
        expect(PortabilityWords.hasOwnTranslation(language, key), isTrue);
      }
    }
  });

  test('A2 member compensations catalog is complete', () {
    final reference = MemberCompensationWords.keysFor(AppLanguage.french);
    for (final language in AppLanguage.values) {
      expect(MemberCompensationWords.keysFor(language), reference);
      for (final key in reference) {
        expect(
          MemberCompensationWords.hasOwnTranslation(language, key),
          isTrue,
          reason: '$language must translate $key without fallback',
        );
      }
    }
  });

  test('A2 residual finance catalog is complete', () {
    final reference = FinanceResidualWords.keysFor(AppLanguage.french);
    for (final language in AppLanguage.values) {
      expect(FinanceResidualWords.keysFor(language), reference);
      for (final key in reference) {
        expect(
          FinanceResidualWords.hasOwnTranslation(language, key),
          isTrue,
          reason: '$language must translate $key without fallback',
        );
      }
    }
  });

  test('A2 cashflow catalog is complete and unique', () {
    final reference = CashflowWords.keysFor(AppLanguage.french);
    for (final language in AppLanguage.values) {
      expect(CashflowWords.keysFor(language), reference);
      for (final key in reference) {
        expect(
          CashflowWords.hasOwnTranslation(language, key),
          isTrue,
          reason: '$language must translate $key without fallback',
        );
      }
    }
  });

  test('A2 cashflow interpolations preserve business values', () {
    for (final language in AppLanguage.values) {
      final words = CashflowWords(language);
      final result = words.format('cashflow.period', const {
        'start': 'START',
        'end': 'END',
      });
      expect(result, contains('START'));
      expect(result, contains('END'));
      expect(words.format('cashflow.risks', const {'count': 3}), contains('3'));
    }
  });

  for (final entry in <(AppLanguage, String, TextDirection)>[
    (AppLanguage.french, 'Prévisions de trésorerie', TextDirection.ltr),
    (AppLanguage.english, 'Cash flow forecast', TextDirection.ltr),
    (AppLanguage.arabic, 'توقعات التدفق النقدي', TextDirection.rtl),
    (AppLanguage.darija, 'توقعات الكاش', TextDirection.rtl),
  ]) {
    testWidgets('Cashflow locale ${entry.$1.storageCode}', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: entry.$1.locale,
          supportedLocales: AppLanguage.values
              .map((language) => language.locale)
              .toList(growable: false),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Builder(
            builder: (context) => Scaffold(
              body: Text(CashflowWords.of(context).text('cashflow.title')),
            ),
          ),
        ),
      );
      expect(find.text(entry.$2), findsOneWidget);
      expect(Directionality.of(tester.element(find.text(entry.$2))), entry.$3);
    });
  }

  test('A2 priorities catalog is complete and unique', () {
    final reference = PrioritiesWords.keysFor(AppLanguage.french);
    for (final language in AppLanguage.values) {
      expect(PrioritiesWords.keysFor(language), reference);
      for (final key in reference) {
        expect(
          PrioritiesWords.hasOwnTranslation(language, key),
          isTrue,
          reason: '$language must translate $key without fallback',
        );
      }
    }
  });

  test('A2 priorities interpolation and plural forms preserve values', () {
    for (final language in AppLanguage.values) {
      final words = PrioritiesWords(language);
      expect(
        words.format('priorities.activate_replace', const {'plan': 'PLAN X'}),
        contains('PLAN X'),
      );
      expect(
        words.format('priorities.funding_month.many', const {'count': 3}),
        contains('3'),
      );
    }
  });

  for (final entry in <(AppLanguage, String, TextDirection)>[
    (AppLanguage.french, 'Priorités', TextDirection.ltr),
    (AppLanguage.english, 'Priorities', TextDirection.ltr),
    (AppLanguage.arabic, 'الأولويات', TextDirection.rtl),
    (AppLanguage.darija, 'الأولويات', TextDirection.rtl),
  ]) {
    testWidgets('Priorities locale ${entry.$1.storageCode}', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: entry.$1.locale,
          supportedLocales: AppLanguage.values
              .map((language) => language.locale)
              .toList(growable: false),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Builder(
            builder: (context) => Scaffold(
              body: Text(PrioritiesWords.of(context).text('priorities.title')),
            ),
          ),
        ),
      );
      expect(find.text(entry.$2), findsOneWidget);
      expect(Directionality.of(tester.element(find.text(entry.$2))), entry.$3);
    });
  }

  test('A2 KPI and reporting catalog is complete and unique', () {
    final reference = KpiReportingWords.keysFor(AppLanguage.french);
    expect(reference.length, 68);
    for (final language in AppLanguage.values) {
      final keys = KpiReportingWords.keysFor(language);
      expect(keys, reference);
      for (final key in reference) {
        expect(
          KpiReportingWords.hasOwnTranslation(language, key),
          isTrue,
          reason: '$language must translate $key without fallback',
        );
      }
    }
  });

  test('A2 KPI and reporting interpolations preserve dynamic values', () {
    for (final language in AppLanguage.values) {
      final words = KpiReportingWords(language);
      final result = words.format('report.fact_detail', const {
        'date': '20/10/2026',
        'status': 'STATUS',
        'source': 'SOURCE',
        'reason': 'REASON',
      });
      expect(result, contains('20/10/2026'));
      expect(result, contains('STATUS'));
      expect(result, contains('SOURCE'));
      expect(result, contains('REASON'));
      expect(result, isNot(contains('{')));
    }
  });

  for (final entry in <(AppLanguage, String, TextDirection)>[
    (AppLanguage.french, 'Qualité et fiabilité', TextDirection.ltr),
    (AppLanguage.english, 'Quality and reliability', TextDirection.ltr),
    (AppLanguage.arabic, 'الجودة والموثوقية', TextDirection.rtl),
    (AppLanguage.darija, 'الجودة والثقة', TextDirection.rtl),
  ]) {
    testWidgets('KPI locale ${entry.$1.storageCode}', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: entry.$1.locale,
          supportedLocales: AppLanguage.values
              .map((language) => language.locale)
              .toList(growable: false),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Builder(
            builder: (context) => Scaffold(
              body: Text(KpiReportingWords.of(context).text('kpi.title')),
            ),
          ),
        ),
      );
      expect(find.text(entry.$2), findsOneWidget);
      expect(Directionality.of(tester.element(find.text(entry.$2))), entry.$3);
    });
  }

  test('A2 budget catalogs are complete in all four languages', () {
    for (final catalog in <Set<String> Function(AppLanguage)>[
      BudgetWords.keysFor,
      BudgetContributionWords.keysFor,
      BudgetRunWords.keysFor,
      BudgetMonthlyWords.keysFor,
      ProgrammableBudgetWords.keysFor,
    ]) {
      final reference = catalog(AppLanguage.french);
      for (final language in AppLanguage.values) {
        expect(catalog(language), reference);
      }
    }
    final programmable = ProgrammableBudgetWords.keysFor(AppLanguage.french);
    for (final language in AppLanguage.values) {
      for (final key in programmable) {
        expect(
          ProgrammableBudgetWords.hasOwnTranslation(language, key),
          isTrue,
          reason: '$language must translate $key without fallback',
        );
      }
    }
  });

  test('A2 scenario A B C catalog is complete in all four languages', () {
    final reference = BudgetScenarioWords.keysFor(AppLanguage.french);
    for (final language in AppLanguage.values) {
      expect(BudgetScenarioWords.keysFor(language), reference);
      for (final key in reference) {
        expect(BudgetScenarioWords.hasOwnTranslation(language, key), isTrue);
      }
    }
  });

  test('scenario list create and edit reject migrated French literals', () {
    final source = File(
      'lib/features/budget_intelligence/presentation/budget_scenarios_page.dart',
    ).readAsStringSync();
    const migrated = [
      'Scénarios budgétaires',
      'Créer',
      'Impossible de charger les scénarios.',
      'Vos programmes de budget réutilisables.',
      'Aucun scénario',
      'Scénario indisponible.',
      'Scénario introuvable.',
      'Programme programmable',
      'Sources de revenus',
      'Programme d’allocation',
      'Configurer sources et programme',
      'Nouveau scénario',
      'Modifier le scénario',
      'Nom *',
      'Description',
      'Déclenchement',
      'Sélection manuelle',
      'À partir d’une date',
      'Date d’effet',
      'À définir',
    ];
    expect(migrated.where(source.contains), isEmpty);
  });

  for (final entry in <(AppLanguage, TextDirection)>[
    (AppLanguage.french, TextDirection.ltr),
    (AppLanguage.english, TextDirection.ltr),
    (AppLanguage.arabic, TextDirection.rtl),
    (AppLanguage.darija, TextDirection.rtl),
  ]) {
    testWidgets('Contribution wizard locale ${entry.$1.storageCode}', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: entry.$1.locale,
          supportedLocales: AppLanguage.values.map((e) => e.locale),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Builder(
            builder: (context) => Text(
              BudgetContributionWords.of(context).text('contribution.title'),
            ),
          ),
        ),
      );
      expect(Directionality.of(tester.element(find.byType(Text))), entry.$2);
    });
  }
  test('A2 envelopes catalog is complete in all four languages', () {
    final reference = EnvelopesWords.keysFor(AppLanguage.french);
    for (final language in AppLanguage.values) {
      expect(EnvelopesWords.keysFor(language), reference);
      for (final key in reference) {
        expect(
          EnvelopesWords.hasOwnTranslation(language, key),
          isTrue,
          reason:
              'Missing Envelopes translation: ${language.storageCode} / $key',
        );
      }
    }
  });

  for (final entry in <(AppLanguage, String, TextDirection)>[
    (AppLanguage.french, 'Paramétrage des enveloppes', TextDirection.ltr),
    (AppLanguage.english, 'Envelope settings', TextDirection.ltr),
    (AppLanguage.arabic, 'إعدادات المغلفات', TextDirection.rtl),
    (AppLanguage.darija, 'ضبط الظروف', TextDirection.rtl),
  ]) {
    testWidgets('Envelopes renders ${entry.$1.storageCode}', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: entry.$1.locale,
          supportedLocales: AppLanguage.values.map((e) => e.locale),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Builder(
            builder: (context) => Text(
              EnvelopesWords.of(context).text('envelopes.settings_title'),
            ),
          ),
        ),
      );
      expect(find.text(entry.$2), findsOneWidget);
      expect(Directionality.of(tester.element(find.text(entry.$2))), entry.$3);
    });
  }

  test('A2 finance catalog is complete in all four languages', () {
    final reference = FinanceWords.keysFor(AppLanguage.french);
    for (final language in AppLanguage.values) {
      expect(FinanceWords.keysFor(language), reference);
      for (final key in reference) {
        expect(
          FinanceWords.hasOwnTranslation(language, key),
          isTrue,
          reason: 'Missing A2 translation: ${language.storageCode} / $key',
        );
      }
    }
  });

  test('A2 accounts catalog is complete in all four languages', () {
    final reference = AccountsWords.keysFor(AppLanguage.french);
    for (final language in AppLanguage.values) {
      expect(AccountsWords.keysFor(language), reference);
      for (final key in reference) {
        expect(
          AccountsWords.hasOwnTranslation(language, key),
          isTrue,
          reason:
              'Missing Accounts translation: ${language.storageCode} / $key',
        );
      }
    }
  });

  test(
    'A2 transactions consultation catalog is complete in all four languages',
    () {
      final reference = TransactionsWords.keysFor(AppLanguage.french);
      for (final language in AppLanguage.values) {
        expect(TransactionsWords.keysFor(language), reference);
        for (final key in reference) {
          expect(
            TransactionsWords.hasOwnTranslation(language, key),
            isTrue,
            reason:
                'Missing Transactions translation: ${language.storageCode} / $key',
          );
        }
      }
    },
  );

  test('Transactions consultation exposes FR EN AR and Darija', () {
    expect(
      TransactionsWords(AppLanguage.french).text('transactions.ledger'),
      'Grand Livre',
    );
    expect(
      TransactionsWords(AppLanguage.english).text('transactions.ledger'),
      'General Ledger',
    );
    expect(
      TransactionsWords(AppLanguage.arabic).text('transactions.ledger'),
      'دفتر الأستاذ العام',
    );
    expect(
      TransactionsWords(AppLanguage.darija).text('transactions.search'),
      'قلب',
    );
  });

  for (final entry in <(AppLanguage, String, TextDirection)>[
    (AppLanguage.french, 'Transactions', TextDirection.ltr),
    (AppLanguage.english, 'Transactions', TextDirection.ltr),
    (AppLanguage.arabic, 'المعاملات', TextDirection.rtl),
    (AppLanguage.darija, 'المعاملات', TextDirection.rtl),
  ]) {
    testWidgets('Transactions consultation renders ${entry.$1.storageCode}', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: entry.$1.locale,
          supportedLocales: AppLanguage.values.map((e) => e.locale),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Builder(
            builder: (context) =>
                Text(TransactionsWords.of(context).text('transactions.title')),
          ),
        ),
      );
      expect(find.text(entry.$2), findsOneWidget);
      expect(Directionality.of(tester.element(find.text(entry.$2))), entry.$3);
    });
  }

  test('transactions complete file rejects visible hardcoded strings', () {
    final source = File(
      'lib/features/finance/presentation/transactions_page.dart',
    ).readAsStringSync();
    final patterns = <RegExp>[
      RegExp(r'''\bText\s*\(\s*['"]''', multiLine: true),
      RegExp(
        r'''\b(?:label|tooltip|hintText|helperText|semanticLabel|message)\s*:\s*['"]''',
        multiLine: true,
      ),
    ];
    final violations = patterns
        .expand((pattern) => pattern.allMatches(source))
        .where((match) {
          final line = '\n'.allMatches(source.substring(0, match.start)).length;
          return !source.split('\n')[line].contains('i18n-dynamic-only');
        })
        .map((match) => match.group(0))
        .toList(growable: false);
    expect(violations, isEmpty, reason: 'Transactions hardcodes: $violations');
  });

  test('Accounts exposes real FR EN AR and Darija labels', () {
    expect(AccountsWords(AppLanguage.french).text('accounts.title'), 'Comptes');
    expect(
      AccountsWords(AppLanguage.english).text('accounts.title'),
      'Accounts',
    );
    expect(
      AccountsWords(AppLanguage.arabic).text('accounts.title'),
      'الحسابات',
    );
    expect(
      AccountsWords(AppLanguage.darija).text('accounts.add_title'),
      'زيد حساب',
    );
    expect(AppLanguage.arabic.locale.languageCode, 'ar');
    expect(AppLanguage.darija.storageCode, 'ary');
    expect(AppLanguage.darija.locale, const Locale('ar', 'MA'));
  });

  for (final entry in <(AppLanguage, String, TextDirection)>[
    (AppLanguage.french, 'Comptes', TextDirection.ltr),
    (AppLanguage.english, 'Accounts', TextDirection.ltr),
    (AppLanguage.arabic, 'الحسابات', TextDirection.rtl),
    (AppLanguage.darija, 'الحسابات', TextDirection.rtl),
  ]) {
    testWidgets(
      'Accounts renders ${entry.$1.storageCode} with the expected direction',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: entry.$1.locale,
            supportedLocales: AppLanguage.values
                .map((language) => language.locale)
                .toList(growable: false),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Builder(
              builder: (context) => Scaffold(
                body: Text(AccountsWords.of(context).text('accounts.title')),
              ),
            ),
          ),
        );
        expect(find.text(entry.$2), findsOneWidget);
        expect(
          Directionality.of(tester.element(find.text(entry.$2))),
          entry.$3,
        );
      },
    );
  }

  test('migrated A2 surfaces reject visible hardcoded strings', () {
    const files = [
      'lib/features/dashboard/presentation/financial_dashboard_page.dart',
      'lib/features/finance/presentation/payment_methods_page.dart',
      'lib/features/finance/presentation/accounts_page.dart',
      'lib/features/finance/presentation/transactions_page.dart',
      'lib/features/envelopes/presentation/envelope_dashboard_page.dart',
      'lib/features/envelopes/presentation/envelope_recommendations_page.dart',
      'lib/features/finance/presentation/widgets/envelope_allocation_dialog.dart',
      'lib/features/budget_intelligence/presentation/budget_page.dart',
      'lib/features/budget_intelligence/presentation/budget_contribution_wizard_page.dart',
      'lib/features/budget_intelligence/presentation/budget_scenarios_page.dart',
      'lib/features/budget_intelligence/presentation/budget_runs_page.dart',
      'lib/features/budget_intelligence/presentation/budget_monthly_preparation_page.dart',
      'lib/features/budget_intelligence/presentation/programmable_budget_program_page.dart',
      'lib/features/operational_kpis/presentation/operational_kpi_panel.dart',
      'lib/features/reporting/presentation/business_reporting_panel.dart',
      'lib/features/priorities/presentation/priorities_page.dart',
      'lib/features/cashflow_projection/presentation/cashflow_projection_page.dart',
      'lib/features/finance/presentation/household_members_dialog.dart',
      'lib/features/finance/presentation/finance_overview_page.dart',
      'lib/features/finance/presentation/import_wizard_components.dart',
      'lib/features/dashboard/presentation/dashboard_charts.dart',
      'lib/features/finance/presentation/household_settings_page.dart',
      'lib/features/wealth/presentation/financing_comparison_dialog.dart',
      'lib/features/finance/presentation/member_compensations_page.dart',
      'lib/features/portability/presentation/portability_page.dart',
      'lib/features/recurring_finance/presentation/recurring_finance_page.dart',
      'lib/features/wealth/presentation/home_auto_panels.dart',
      'lib/features/dashboard/presentation/dashboard_v2_panels.dart',
      'lib/features/finance/presentation/cutover_preparation_card.dart',
      'lib/features/savings_goals/presentation/savings_goals_page.dart',
      'lib/features/finance/presentation/import_preview_page.dart',
      'lib/features/finance/presentation/historical_analytics_preview_card.dart',
      'lib/features/finance/presentation/imports_page.dart',
      'lib/features/wealth/presentation/wealth_page.dart',
      'lib/features/monthly_close/presentation/monthly_close_page.dart',
    ];
    final patterns = <RegExp>[
      RegExp(r'''\bText\s*\(\s*['"]''', multiLine: true),
      RegExp(
        r'''\b(?:label|tooltip|hintText|helperText|semanticLabel|message)\s*:\s*['"]''',
        multiLine: true,
      ),
    ];
    final violations = <String>[];
    for (final path in files) {
      final source = File(path).readAsStringSync();
      for (final pattern in patterns) {
        for (final match in pattern.allMatches(source)) {
          final line =
              '\n'.allMatches(source.substring(0, match.start)).length + 1;
          final sourceLine = source.split('\n')[line - 1];
          if (sourceLine.contains('i18n-dynamic-only')) continue;
          violations.add('$path:$line ${match.group(0)}');
        }
      }
    }
    expect(
      violations,
      isEmpty,
      reason: 'Use FinanceWords for visible strings:\n${violations.join('\n')}',
    );
  });

  test('Transactions obligations reject visible hardcoded strings', () {
    final source = File(
      'lib/features/finance/presentation/transactions_page.dart',
    ).readAsStringSync();
    const migratedObligationLiterals = <String>[
      'Créancier non renseigné',
      'Contrepartie non renseignée',
      'Aucune dette ouverte',
      'Aucune créance',
      'Créer une créance',
      'Revenu à encaisser',
      'Dépense à rembourser *',
      'Impossible de charger les dépenses éligibles.',
      'Aucun règlement, encaissement ou abandon enregistré.',
      'Montant abandonné (MAD) *',
      'Restant à encaisser :',
      'Montant encaissé (MAD) *',
      'Compte à créditer *',
      'Répartition de l’encaissement',
      'Le total affecté ne peut pas dépasser l’encaissement.',
      'Montant à régler (MAD) *',
      'Compte de paiement *',
      'Le règlement doit être positif et ne pas dépasser le restant.',
    ];
    final violations = migratedObligationLiterals
        .where(source.contains)
        .toList(growable: false);
    expect(violations, isEmpty, reason: 'Obligation hardcodes: $violations');
  });
}
