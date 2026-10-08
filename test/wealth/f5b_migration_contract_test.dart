import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    'supabase/migrations/20261008070539_f5b_home_vehicle_specializations.sql',
  ).readAsStringSync();

  test('F5B reste household scoped et protégé par RLS', () {
    for (final table in [
      'home_profiles',
      'home_benefits',
      'asset_expense_links',
      'vehicle_profiles',
      'vehicle_mileage_readings',
      'vehicle_cost_plans',
    ]) {
      expect(sql, contains('create table public.$table'));
      expect(
        sql,
        contains('alter table public.$table enable row level security'),
      );
    }
    expect(sql, contains('references public.wealth_assets(id,household_id)'));
    expect(
      sql,
      contains('references public.financial_events(id,household_id)'),
    );
  });

  test('projections ne créent aucune écriture et historiques append-only', () {
    expect(sql, contains('F5B history is append-only'));
    expect(sql, contains('with (security_invoker=true)'));
    expect(sql, isNot(contains('insert into public.financial_events')));
    expect(sql, isNot(contains('insert into public.financial_transactions')));
    expect(sql, isNot(contains('insert into public.envelope_movements')));
  });
}
