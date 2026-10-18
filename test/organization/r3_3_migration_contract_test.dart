import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    'supabase/migrations/20261018140000_r3_3_temporal_reminders_and_rules.sql',
  ).readAsStringSync();

  test('étend F6 avec règles, snooze audité et scheduler idempotent', () {
    expect(sql, contains('alter table public.user_alert_states'));
    expect(sql, contains('snoozed_until'));
    expect(sql, contains('create table public.reminder_rules'));
    expect(sql, contains('create table public.financial_reminders'));
    expect(sql, contains('create table public.reminder_action_audit'));
    expect(sql, contains('unique (household_id,dedupe_key)'));
    expect(sql, contains('on conflict(household_id,dedupe_key) do nothing'));
    expect(
      sql,
      contains("cron.schedule('r3_3_materialize_financial_reminders'"),
    );
  });

  test('RLS, destinataire et fuseau du foyer sont imposés', () {
    expect(sql, contains('enable row level security'));
    expect(sql, contains('public.is_household_member(household_id)'));
    expect(sql, contains('recipient_user_id=(select auth.uid())'));
    expect(sql, contains('at time zone h.timezone'));
    expect(sql, contains('Reminder recipient mismatch'));
  });

  test('aucune primitive financière ne peut être créée par le scheduler', () {
    for (final forbidden in [
      'insert into public.financial_events',
      'insert into public.gl_transactions',
      'insert into public.gl_postings',
      'insert into public.envelope_movements',
      'create_account_transfer_event',
    ]) {
      expect(sql.toLowerCase(), isNot(contains(forbidden)));
    }
  });
}
