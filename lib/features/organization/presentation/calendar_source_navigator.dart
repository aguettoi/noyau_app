import 'package:flutter/material.dart';

import '../../budget_intelligence/presentation/budget_page.dart';
import '../../finance/presentation/member_compensations_page.dart';
import '../../finance/presentation/transactions_page.dart';
import '../../savings_goals/presentation/savings_goals_page.dart';
import '../../shopping_list/presentation/shopping_list_page.dart';
import '../../wealth/presentation/wealth_page.dart';
import '../domain/organization_models.dart';

class CalendarSourceNavigator {
  const CalendarSourceNavigator();

  Widget? resolve(CalendarSource source, String? id) {
    if (id == null) return null;
    return switch (source) {
      CalendarSource.budget => const BudgetPage(),
      CalendarSource.obligation => const DebtsPage(),
      CalendarSource.goal ||
      CalendarSource.priority => const SavingsGoalsPage(),
      CalendarSource.shopping => const ShoppingListPage(),
      CalendarSource.homeAuto ||
      CalendarSource.investment => const WealthPage(),
      CalendarSource.compensation => const MemberCompensationsPage(),
      CalendarSource.task || CalendarSource.reconciliation => null,
    };
  }

  Future<void> open(BuildContext context, CalendarSource source, String? id) {
    final page = resolve(source, id);
    if (page == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Cet élément n'est plus disponible.")),
      );
      return Future.value();
    }
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
  }
}
