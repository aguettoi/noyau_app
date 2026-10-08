import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/budget_intelligence/presentation/budget_page.dart';
import 'package:noyau_app/features/finance/presentation/member_compensations_page.dart';
import 'package:noyau_app/features/finance/presentation/transactions_page.dart';
import 'package:noyau_app/features/organization/domain/organization_models.dart';
import 'package:noyau_app/features/organization/presentation/calendar_source_navigator.dart';
import 'package:noyau_app/features/savings_goals/presentation/savings_goals_page.dart';
import 'package:noyau_app/features/shopping_list/presentation/shopping_list_page.dart';
import 'package:noyau_app/features/wealth/presentation/wealth_page.dart';

void main() {
  test('calendar sources resolve to the existing canonical modules', () {
    const navigator = CalendarSourceNavigator();
    expect(navigator.resolve(CalendarSource.budget, 'id'), isA<BudgetPage>());
    expect(
      navigator.resolve(CalendarSource.obligation, 'id'),
      isA<DebtsPage>(),
    );
    expect(
      navigator.resolve(CalendarSource.goal, 'id'),
      isA<SavingsGoalsPage>(),
    );
    expect(
      navigator.resolve(CalendarSource.shopping, 'id'),
      isA<ShoppingListPage>(),
    );
    expect(navigator.resolve(CalendarSource.homeAuto, 'id'), isA<WealthPage>());
    expect(
      navigator.resolve(CalendarSource.compensation, 'id'),
      isA<MemberCompensationsPage>(),
    );
    expect(navigator.resolve(CalendarSource.budget, null), isNull);
  });
}
