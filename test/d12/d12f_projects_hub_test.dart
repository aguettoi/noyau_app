import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/app/projects_hub_page.dart';
import 'package:noyau_app/core/localization/app_locale.dart';
import 'package:noyau_app/core/localization/foundation_locale.dart';

void main() {
  test('D1.2-F vocabulary is complete in all four languages', () {
    for (final language in AppLanguage.values) {
      final words = FoundationWords(language);
      for (final key in [
        'projects',
        'projects.subtitle',
        'goals',
        'priorities',
        'simulations',
        'financings',
        'wealth',
      ]) {
        expect(words.text(key), isNot(key), reason: '$language: $key');
        expect(words.text(key).trim(), isNotEmpty, reason: '$language: $key');
      }
    }
  });

  testWidgets('hub delegates every decision to its canonical destination', (
    tester,
  ) async {
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr'), Locale('en'), Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: ProjectsHubPage(
            onOpenGoals: () => opened.add('goals'),
            onOpenPriorities: () => opened.add('priorities'),
            onOpenSimulations: () => opened.add('simulations'),
            onOpenFinancings: () => opened.add('financings'),
            onOpenWealth: () => opened.add('wealth'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final label in [
      'Objectifs',
      'PRIOS',
      'Simulations',
      'Financements',
      'Patrimoine',
    ]) {
      await tester.tap(find.text(label));
    }
    expect(opened, [
      'goals',
      'priorities',
      'simulations',
      'financings',
      'wealth',
    ]);
  });

  test('hub contains no direct Supabase access or household-name hardcode', () {
    final source = File('lib/app/projects_hub_page.dart').readAsStringSync();
    expect(source, isNot(contains('supabase')));
    expect(source, isNot(contains('Ibrahim')));
    expect(source, isNot(contains('Nora')));
    expect(source, isNot(contains('FinancialEvent')));
  });
}
