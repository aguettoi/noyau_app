import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20261104120000_d12g_quick_bulk_import.sql',
  ).readAsStringSync();

  test('bulk import is household-scoped, bounded and client-authorized', () {
    expect(migration, contains('public.is_household_member(p_household_id)'));
    expect(migration, contains('jsonb_array_length(p_rows) > 500'));
    expect(
      migration,
      contains('private.can_discover_account(a.id, auth.uid())'),
    );
    expect(
      migration,
      contains(
        'grant execute on function public.quick_bulk_import_financial_events',
      ),
    );
    expect(migration, contains('to authenticated'));
    expect(migration, contains('from public, anon'));
  });

  test('all rows are validated before canonical financial writes', () {
    final validation = migration.indexOf('-- Validate the complete payload');
    final secondLoop = migration.indexOf('v_index := 0;', validation);
    final expense = migration.indexOf(
      'create_cash_expense_with_payment_context',
      secondLoop,
    );
    final income = migration.indexOf('create_cash_income_event', secondLoop);
    expect(validation, greaterThan(-1));
    expect(secondLoop, greaterThan(validation));
    expect(expense, greaterThan(secondLoop));
    expect(income, greaterThan(secondLoop));
    expect(
      migration,
      isNot(contains('insert into public.financial_transactions')),
    );
    expect(
      migration,
      isNot(contains('insert into public.financial_transaction_lines')),
    );
    expect(migration, isNot(contains('insert into public.envelope_movements')));
  });

  test('idempotence is stable per file row and search_path is explicit', () {
    expect(
      migration,
      contains("md5(p_idempotency_key || ':' || v_index::text)::uuid"),
    );
    expect(migration, contains('security definer'));
    expect(migration, contains('set search_path = public, private, auth'));
  });
}
