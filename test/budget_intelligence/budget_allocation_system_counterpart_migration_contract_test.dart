import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/'
    '20260912123000_restore_budget_allocation_system_counterpart.sql',
  ).readAsStringSync();

  test('restaure uniquement la contrepartie GL des allocations budgétaires', () {
    expect(
      migration,
      contains(
        'create or replace function public.ensure_financial_event_system_account',
      ),
    );
    expect(
      migration,
      contains("when 'to_allocate' then 'Système — À répartir'"),
    );
    expect(migration, contains("when 'debt_writeoff_gain'"));
    expect(migration, contains("when 'receivable_loss'"));
    expect(migration, isNot(contains('ensure_household_system_envelope')));
    expect(migration, isNot(contains('allocate_budget_event')));
    expect(migration, isNot(contains('envelope_movements')));
  });

  test('conserve la protection du compte système réservé', () {
    expect(
      migration,
      contains('A reserved FinancialEvent account name is already used'),
    );
    expect(
      migration,
      contains("values (p_household_id, v_name, 'ledger', true)"),
    );
  });
}
