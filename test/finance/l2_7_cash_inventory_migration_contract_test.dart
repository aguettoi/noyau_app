import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    'supabase/migrations/20261025204259_l2_7_cash_denomination_inventory.sql',
  ).readAsStringSync();
  test('étend l’observation canonique sans écriture financière', () {
    expect(sql, contains('alter table public.account_balance_observations'));
    expect(sql, contains('record_cash_inventory_observation'));
    expect(sql, contains('idempotency_key'));
    expect(sql, contains('private.can_read_account_balance'));
    expect(sql, isNot(contains('insert into public.financial_events')));
    expect(sql, isNot(contains('insert into public.financial_transactions')));
    expect(sql, isNot(contains('insert into public.envelope_movements')));
  });
  test('valide côté serveur type cash, total et audience', () {
    expect(sql, contains("v_kind <> 'cash'"));
    expect(sql, contains('Denomination total differs'));
    expect(sql, contains('public.is_household_member'));
    expect(sql, contains('private.can_discover_account'));
    expect(sql, contains('grant execute'));
    expect(sql, contains('public.cash_denominations'));
    expect(sql, contains('Unknown denomination for account currency'));
    expect(
      sql,
      contains(
        'revoke all on table public.cash_denominations from public,anon,authenticated',
      ),
    );
  });
}
