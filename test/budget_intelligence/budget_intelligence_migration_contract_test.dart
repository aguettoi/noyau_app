import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/202608100002_budget_intelligence_foundation.sql',
  ).readAsStringSync();

  test('réutilise le modèle historique starts_on/ends_on sans year/month', () {
    expect(
      migration,
      contains('on public.budget_periods(household_id, starts_on)'),
    );
    expect(migration, contains('add column if not exists scenario_id'));
    expect(migration, contains('budget_periods_id_household_unique'));
    expect(migration, contains('unique (id, household_id)'));
    expect(migration, isNot(contains('household_id, year, month')));
    expect(migration, isNot(contains('year integer')));
  });

  test('le reporting est compatible avec envelope_movements', () {
    expect(
      migration,
      contains('from public.envelopes e left join public.envelope_movements m'),
    );
    expect(migration, contains('m.occurred_at'));
    expect(migration, contains('m.movement_type'));
  });

  test(
    'la migration étend les périodes préexistantes et renouvelle la policy',
    () {
      expect(migration, contains('alter table public.budget_periods'));
      expect(
        migration,
        contains('drop policy if exists "members manage budget periods"'),
      );
      expect(migration, contains('begin;'));
      expect(migration, contains('commit;'));
    },
  );
}
