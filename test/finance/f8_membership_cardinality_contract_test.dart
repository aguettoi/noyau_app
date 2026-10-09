import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('F8 preserves historical memberships and filters active operations', () {
    final sql = File(
      'supabase/migrations/20261009181611_f8_active_membership_cardinality.sql',
    ).readAsStringSync();
    expect(sql, contains('add column if not exists inactive_at'));
    expect(sql, contains('set inactive_at = now()'));
    expect(sql, isNot(contains('delete from public.household_members')));
    expect(sql, contains('and inactive_at is null'));
    expect(sql, contains('member_compensations_active_parties'));
    expect(sql, contains('household_tasks_active_assignee'));
    expect(sql, contains('budget_member_incomes_active_member'));
  });

  test('Flutter only loads active memberships for new operations', () {
    final membersProvider = File(
      'lib/features/finance/application/providers/remote_household_members_provider.dart',
    ).readAsStringSync();
    final activeHousehold = File(
      'lib/features/finance/application/providers/active_household_provider.dart',
    ).readAsStringSync();
    expect(membersProvider, contains("isFilter('inactive_at', null)"));
    expect(activeHousehold, contains("isFilter('inactive_at', null)"));
  });
}
