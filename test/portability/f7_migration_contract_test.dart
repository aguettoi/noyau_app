import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    'supabase/migrations/20261008205340_f7_global_search_realtime.sql',
  ).readAsStringSync().toLowerCase();
  test('global search is bounded, household scoped and read-only', () {
    expect(sql, contains('search_household_global'));
    expect(sql, contains('is_household_member(p_household_id)'));
    expect(sql, contains('limit least(greatest(p_limit,1),100)'));
    expect(sql, contains('security invoker'));
    expect(sql, isNot(contains('insert into public.financial_events')));
    expect(sql, isNot(contains('update public.')));
    for (final type in const [
      'financial_event',
      'account',
      'envelope',
      'obligation',
      'receivable',
      'compensation',
      'goal',
      'shopping',
      'priority',
      'task',
      'asset',
    ]) {
      expect(sql, contains("'$type'"), reason: 'missing $type search');
    }
  });
  test('realtime publication is explicit and limited', () {
    expect(sql, contains("pubname='supabase_realtime'"));
    expect(sql, contains("'household_tasks'"));
    expect(sql, contains("'member_compensations'"));
  });
}
