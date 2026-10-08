import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('F6 schema is household scoped, RLS protected and financially read-only', () {
    final sql = File(
      'supabase/migrations/20261008180806_f6_household_tasks_calendar_alerts.sql',
    ).readAsStringSync();
    for (final table in [
      'household_tasks',
      'household_task_occurrences',
      'user_alert_states',
      'notification_preferences',
    ]) {
      expect(
        sql,
        contains('alter table public.$table enable row level security'),
      );
    }
    expect(sql, contains('public.is_household_member'));
    expect(
      sql,
      contains(
        "if auth.uid() is null then raise exception 'Authentication required'",
      ),
    );
    expect(sql, contains('security definer set search_path=public'));
    expect(sql, contains('unique (task_id,idempotency_key)'));
    for (final forbidden in [
      'financial_events',
      'transactions',
      'postings',
      'envelope_movements',
    ]) {
      expect(
        sql.toLowerCase(),
        isNot(contains('insert into public.$forbidden')),
      );
    }

    final hardening = File(
      'supabase/migrations/20261008182901_f6_household_tasks_hardening.sql',
    ).readAsStringSync();
    expect(
      hardening,
      contains(
        'revoke all on function public.complete_household_task(uuid,text,text,uuid)',
      ),
    );
    expect(hardening, contains('from public, anon'));
    expect(hardening, contains('to authenticated'));
  });
}
