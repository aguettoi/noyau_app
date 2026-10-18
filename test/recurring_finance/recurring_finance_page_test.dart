import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/recurring_finance/application/recurring_finance_provider.dart';
import 'package:noyau_app/features/recurring_finance/domain/recurring_finance.dart';
import 'package:noyau_app/features/recurring_finance/presentation/recurring_finance_page.dart';

void main() {
  testWidgets('R3.1 remains usable on a narrow mobile viewport', (
    tester,
  ) async {
    await initializeDateFormatting('fr');
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rule = RecurringFinancialIntention(
      id: 'rule',
      householdId: 'household',
      type: RecurringEconomicType.expense,
      label: 'Internet',
      amount: const Money.fromMinorUnits(65000),
      currency: 'MAD',
      frequency: RecurringFrequency.monthly,
      startsOn: DateTime(2026, 10, 25),
      nextOccurrenceOn: DateTime(2026, 11, 25),
      certainty: RecurringCertainty.certain,
      status: RecurringStatus.active,
    );
    final occurrence = ExpectedFinancialOccurrence(
      id: 'occurrence',
      intentionId: rule.id,
      expectedOn: DateTime(2026, 10, 25),
      type: rule.type,
      label: rule.label,
      expectedAmount: rule.amount,
      confirmedAmount: const Money.fromMinorUnits(20000),
      status: ExpectedOccurrenceStatus.partiallyRealized,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recurringIntentionsProvider.overrideWith((_) async => [rule]),
          expectedOccurrencesProvider.overrideWith((_) async => [occurrence]),
          actualRecurringCandidatesProvider.overrideWith((_) async => const []),
        ],
        child: const MaterialApp(home: RecurringFinancePage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Internet'), findsOneWidget);
    expect(find.textContaining('Engagement certain'), findsOneWidget);
    await tester.tap(find.text('Prochaines occurrences'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Partiellement réalisée'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
