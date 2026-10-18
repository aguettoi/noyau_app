import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String sql;
  setUpAll(() {
    sql = File(
      'supabase/migrations/20261018120000_r3_1_recurring_financial_intentions.sql',
    ).readAsStringSync();
  });

  test('R3.1 separates expectations from canonical financial events', () {
    expect(sql, contains('create table public.recurring_financial_intentions'));
    expect(sql, contains('create table public.expected_financial_occurrences'));
    expect(sql, contains('references public.financial_events'));
    expect(sql, isNot(contains('insert into public.financial_events')));
    expect(sql, isNot(contains('insert into public.financial_transactions')));
    expect(sql, isNot(contains('insert into public.envelope_movements')));
  });

  test(
    'R3.1 is household scoped, RLS protected and cross-household checked',
    () {
      expect(sql, contains('enable row level security'));
      expect(sql, contains('public.is_household_member(household_id)'));
      expect(sql, contains("raise exception 'Invalid source account'"));
      expect(sql, contains("raise exception 'Invalid destination account'"));
      expect(sql, contains("raise exception 'Invalid envelope'"));
      expect(sql, contains("raise exception 'Invalid member'"));
    },
  );

  test('occurrences are windowed, immutable snapshots and idempotent', () {
    expect(sql, contains("limited to 18 months"));
    expect(sql, contains('unique (intention_id,expected_on)'));
    expect(sql, contains('on conflict(intention_id,expected_on) do nothing'));
    expect(sql, contains('for update'));
    expect(sql, contains('pg_advisory_xact_lock'));
  });

  test('confirmed amount and status are derived from append-only links', () {
    expect(sql, contains('expected_financial_occurrence_overview'));
    expect(sql, contains("filter(where m.decision='confirmed')"));
    expect(sql, contains("then 'partially_realized'"));
    expect(sql, contains("then 'overdue'"));
    expect(sql, contains('security_invoker=true'));
  });

  test(
    'actual candidates remain a read-only adapter over canonical events',
    () {
      final adapter = File(
        'supabase/migrations/20261018123000_r3_1_actual_match_candidates.sql',
      ).readAsStringSync();
      expect(adapter, contains('security_invoker=true'));
      expect(adapter, contains('join public.financial_transactions'));
      expect(adapter, contains('t.reversed_by is null'));
      expect(adapter, isNot(contains('insert into public.financial_events')));
    },
  );

  test('rule and match changes keep an append-only actor audit', () {
    final audit = File(
      'supabase/migrations/20261018124500_r3_1_audit_trail.sql',
    ).readAsStringSync();
    expect(audit, contains('recurring_financial_audit_events'));
    expect(audit, contains('after insert or update'));
    expect(audit, contains('to_jsonb(old)'));
    expect(audit, contains('auth.uid()'));
    expect(audit, isNot(contains('delete from')));
  });

  test('an expected occurrence can be ignored without financial writes', () {
    final ignore = File(
      'supabase/migrations/20261018130000_r3_1_occurrence_ignore.sql',
    ).readAsStringSync();
    expect(ignore, contains('ignore_expected_financial_occurrence'));
    expect(ignore, contains("'occurrence'"));
    expect(ignore, contains('Ignore reason required'));
    expect(ignore, isNot(contains('insert into public.financial_events')));
    expect(
      ignore,
      isNot(contains('insert into public.financial_transactions')),
    );
    expect(ignore, isNot(contains('insert into public.envelope_movements')));
  });
}
