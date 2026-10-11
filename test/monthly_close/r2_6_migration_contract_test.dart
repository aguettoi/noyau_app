import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('R2.6 reorders personal charges without changing financial values', () {
    final sql = File(
      'supabase/migrations/20261011215956_r2_6_budget_personal_before_common_order.sql',
    ).readAsStringSync();

    expect(sql, contains("st.contribution_key = 'single_member'"));
    expect(
      sql,
      contains("st.group_name not like 'Charges communes — Habits%'"),
    );
    expect(sql, contains('st.step_order + 10000'));
    expect(sql, contains('new_step_order'));
    expect(sql, contains('a personal charge remains after common allocations'));
    expect(sql, isNot(contains('set amount =')));
    expect(sql, isNot(contains('set key_definition =')));
    expect(sql, isNot(contains('financial_events')));
    expect(sql, isNot(contains('financial_transactions')));
    expect(sql, isNot(contains('envelope_movements')));
    expect(sql, isNot(contains('budget_allocation_runs')));
    expect(sql, isNot(contains('budget_periods')));
  });
}
