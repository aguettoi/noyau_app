import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    'supabase/migrations/20261007071814_f5a_wealth_investments_financing.sql',
  ).readAsStringSync();
  test('F5A objects are household scoped and RLS protected', () {
    for (final table in [
      'wealth_assets',
      'wealth_asset_valuations',
      'investment_products',
      'investment_operations',
      'financing_profiles',
    ]) {
      expect(sql, contains('create table public.$table'));
      expect(
        sql,
        contains('alter table public.$table enable row level security'),
      );
    }
    expect(sql, contains('references public.obligations(id,household_id)'));
    expect(
      sql,
      contains('references public.financial_events(id,household_id)'),
    );
  });
  test('histories are append-only and views are security invoker', () {
    expect(sql, contains('F5A history is append-only'));
    expect(
      RegExp(r'with \(security_invoker=true\)').allMatches(sql),
      hasLength(3),
    );
    expect(sql, isNot(contains('opening_balance =')));
    expect(sql, isNot(contains('insert into public.financial_events')));
  });
}
