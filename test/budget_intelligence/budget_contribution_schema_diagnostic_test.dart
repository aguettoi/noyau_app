import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/budget_intelligence/application/providers/remote_budget_provider.dart';

void main() {
  test('schema prerequisite has a safe production fallback', () {
    const fallback = 'Revenus indisponibles.';
    final message = budgetContributionLoadMessage(
      const BudgetContributionSchemaUnavailableException(),
      productionFallback: fallback,
    );
    expect(message, isNotEmpty);
  });

  test('unrelated errors keep the production-safe message', () {
    expect(
      budgetContributionLoadMessage(
        StateError('network'),
        productionFallback: 'Impossible de charger les règles.',
      ),
      'Impossible de charger les règles.',
    );
  });
}
