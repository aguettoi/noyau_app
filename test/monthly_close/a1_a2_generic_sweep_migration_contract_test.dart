import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    'supabase/migrations/20261114120000_a1_a2_kpi_responsibility_and_generic_sweep.sql',
  ).readAsStringSync();

  test('responsibility is explicit, multi-member and never inferred', () {
    expect(sql, contains('economic_responsibility_assignments'));
    expect(sql, contains("responsibility_kind in ('household','member')"));
    expect(sql, contains("p_responsibility_kind='unassigned'"));
    expect(sql, contains('foreach v_member in array p_member_user_ids'));
    expect(
      sql,
      contains(
        'Recorder, account holder, payment method and envelope never imply responsibility',
      ),
    );
  });

  test('runtime sweep uses relational ids and accepts any source count', () {
    final runtime = sql.substring(
      sql.indexOf(
        'create or replace function public.monthly_savings_sweep_preview',
      ),
    );
    expect(runtime, contains('monthly_envelope_sweep_rules'));
    expect(runtime, contains('source_envelope_id'));
    expect(runtime, contains('destination_envelope_id'));
    expect(runtime, isNot(contains("name='Epargne'")));
    expect(runtime, isNot(contains('month_end_sweep_destination')));
    expect(runtime, isNot(contains('<>3')));
  });

  test('active destination cannot be archived or deleted', () {
    expect(
      sql,
      contains(
        'Active savings sweep destination must be reassigned or disabled before archival',
      ),
    );
    expect(
      sql,
      contains(
        'Active savings sweep destination must be reassigned or disabled before deletion',
      ),
    );
  });

  test('preview proves analytical and physical separation', () {
    expect(sql, contains("'creates_bank_transfer',false"));
    expect(sql, contains("'creates_gl',false"));
    expect(sql, isNot(contains('create_account_transfer_event(')));
    expect(sql, contains('create_envelope_transfer_event'));
  });

  test('sweep is idempotent per month, source and rule identity', () {
    expect(sql, contains('pg_advisory_xact_lock'));
    expect(
      sql,
      contains(
        "'monthly-savings-sweep|'||p_household_id||'|'||p_month_start||'|'||v_rule.rule_id",
      ),
    );
    expect(
      sql,
      contains(
        'where household_id=p_household_id and month_start=p_month_start and source_envelope_id=v_rule.source_envelope_id',
      ),
    );
  });
}
