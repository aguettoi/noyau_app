import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/budget_intelligence/application/providers/remote_budget_provider.dart';

void main() {
  test('a legacy rule without active opens with the active default', () {
    expect(budgetRuleActiveFromData(null), isTrue);
    expect(budgetRuleActiveFromData(false), isFalse);
    expect(budgetRuleActiveFromData(true), isTrue);
  });
}
