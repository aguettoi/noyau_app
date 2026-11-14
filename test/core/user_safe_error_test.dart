import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/network/network_failure.dart';
import 'package:noyau_app/core/presentation/user_safe_error.dart';

void main() {
  const forbiddenDiagnostics = <String>[
    'ClientException',
    'PostgrestException',
    'supabase.co',
    '/rest/v1/',
    'list_household_envelopes_safe',
    'household_grocery_items',
  ];

  testWidgets('network diagnostics never reach the user in any locale', (
    tester,
  ) async {
    for (final locale in const <Locale>[
      Locale('fr'),
      Locale('en'),
      Locale('ar'),
      Locale('ar', 'MA'),
    ]) {
      var retried = false;
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: const [
            Locale('fr'),
            Locale('en'),
            Locale('ar'),
            Locale('ar', 'MA'),
          ],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: UserSafeErrorState(
              error: Exception(
                'ClientException: Failed to fetch, '
                'uri=https://project.supabase.co/rest/v1/rpc/'
                'list_household_envelopes_safe',
              ),
              onRetry: () => retried = true,
            ),
          ),
        ),
      );
      await tester.pump();

      final visibleText = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data ?? '')
          .join(' ');
      for (final forbidden in forbiddenDiagnostics) {
        expect(visibleText, isNot(contains(forbidden)));
      }
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      await tester.tap(find.byIcon(Icons.refresh));
      expect(retried, isTrue);
    }
  });

  test('network failures are recognized without exposing their payload', () {
    expect(
      isNetworkFailure(Exception('ClientException: Failed to fetch')),
      isTrue,
    );
    expect(isNetworkFailure(Exception('SocketException: unreachable')), isTrue);
    expect(
      isNetworkFailure(Exception('PostgrestException: invalid query')),
      isFalse,
    );
  });

  test('protected presentation surfaces do not interpolate raw errors', () {
    const protectedFiles = <String>[
      'lib/features/envelopes/presentation/envelope_dashboard_page.dart',
      'lib/features/shopping_list/presentation/shopping_list_page.dart',
      'lib/features/organization/presentation/daily_life_page.dart',
      'lib/features/organization/presentation/organization_page.dart',
      'lib/features/finance/presentation/accounts_page.dart',
      'lib/features/finance/presentation/transactions_page.dart',
      'lib/features/savings_goals/presentation/savings_goals_page.dart',
      'lib/features/finance/presentation/import_preview_page.dart',
      'lib/features/budget_intelligence/presentation/'
          'programmable_budget_program_page.dart',
    ];
    final rawCatalogArgument = RegExp(r"\{'error':\s*(?:error|e)\}");
    final rawTextConversion = RegExp(
      r'Text\([^\n]*(?:error|e)(?:\.message)?\.toString\(\)',
    );

    for (final path in protectedFiles) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(matches(rawCatalogArgument)), reason: path);
      expect(source, isNot(matches(rawTextConversion)), reason: path);
    }
  });
}
