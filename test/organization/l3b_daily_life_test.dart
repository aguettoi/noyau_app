import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/localization/app_locale.dart';
import 'package:noyau_app/core/localization/household_locale.dart';
import 'package:noyau_app/features/finance/application/providers/remote_household_members_provider.dart';
import 'package:noyau_app/features/organization/application/daily_life_provider.dart';
import 'package:noyau_app/features/organization/domain/reminder_snooze_policy.dart';

void main() {
  test('Pas encore is exactly fifteen minutes from the action', () {
    final now = DateTime.utc(2026, 10, 26, 20, 45, 12);
    final decision = ReminderSnoozePolicy.decide(
      choice: ReminderSnoozeChoice.notYet,
      nowUtc: now,
      timezone: 'Africa/Casablanca',
    );
    expect(decision.untilUtc, now.add(const Duration(minutes: 15)));
  });

  test('home records project into the canonical calendar', () {
    final entries = homeRecordCalendarEntries([
      {
        'id': 'record-1',
        'label': 'Contrat eau',
        'kind': 'contract',
        'due_on': '2026-11-04',
        'responsible_user_id': 'member-1',
      },
    ]);
    expect(entries.single.key, 'home-record:record-1');
    expect(entries.single.assigneeUserId, 'member-1');
  });

  test('migration keeps finance separate and cycle details private', () {
    final sql = File(
      'supabase/migrations/20261026195613_l3b_daily_life_private_cycle.sql',
    ).readAsStringSync();
    expect(sql, contains('household_grocery_items'));
    expect(sql, isNot(contains('references public.shopping_items')));
    expect(sql, contains('member_cycle_events_owner_read'));
    expect(sql, contains('read_shared_cycle_calendar'));
    expect(
      sql,
      contains('select e.id,e.owner_user_id,e.starts_on,e.ends_on,e.phase'),
    );
    expect(sql, isNot(contains('select e.*')));
    expect(sql, contains("p_snoozed_until <= now()"));
    expect(sql, isNot(contains('financial_events')));
    expect(sql, isNot(contains('gl_transactions')));
    expect(sql, isNot(contains('envelope_movements')));
  });

  test('D1.2-E household vocabulary is complete in all four languages', () {
    const keys = [
      'hub.title',
      'hub.today',
      'hub.tasks',
      'hub.calendar',
      'hub.alerts',
      'hub.daily_life',
      'today.title',
      'today.empty',
      'task.new',
      'task.advanced',
      'daily.title',
      'daily.groceries',
      'daily.home',
      'daily.personal',
      'grocery.empty',
      'grocery.expense',
      'home.empty',
      'personal.private',
      'cycle.share_title',
      'cycle.share_allowed',
      'cycle.share_private',
      'cycle.revoke',
    ];
    for (final language in AppLanguage.values) {
      final words = HouseholdWords(language);
      for (final key in keys) {
        expect(words.text(key), isNot(key), reason: '$language: $key');
        expect(words.text(key).trim(), isNotEmpty, reason: '$language: $key');
      }
    }
  });

  test('D1.2-E responsibility remains generic for 1, 2 and 5 members', () {
    for (final count in [1, 2, 5]) {
      final ids = List.generate(count, (index) => 'member-$index');
      final members = householdMembersForDisplay(
        userIds: ids,
        displayNamesByUserId: {
          for (var index = 0; index < count; index++)
            'member-$index': 'Personne ${index + 1}',
        },
      );
      expect(members, hasLength(count));
      expect(members.map((member) => member.id), orderedEquals(ids));
    }
  });
}
