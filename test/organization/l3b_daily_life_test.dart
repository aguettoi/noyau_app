import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/localization/app_locale.dart';
import 'package:noyau_app/core/localization/household_locale.dart';
import 'package:noyau_app/features/finance/application/providers/remote_household_members_provider.dart';
import 'package:noyau_app/features/organization/application/daily_life_provider.dart';
import 'package:noyau_app/features/organization/domain/reminder_snooze_policy.dart';
import 'package:noyau_app/features/organization/domain/cycle_tracking.dart';

void main() {
  test('Automatic resolves ar-MA to canonical ary/Darija', () {
    expect(
      AppLanguageX.fromEnvironmentLocales(const [Locale('ar', 'MA')]),
      AppLanguage.darija,
    );
    expect(AppLanguage.darija.storageCode, 'ary');
    expect(AppLanguage.darija.locale, const Locale('ar', 'MA'));
  });

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
      'cycle.forecast',
      'cycle.insufficient',
      'cycle.next_period',
      'cycle.ovulation',
      'cycle.uncertainty',
      'cycle.fertility_warning',
      'cycle.private_journal',
      'cycle.add_private',
      'cycle.private_empty',
      'cycle.private_category',
      'cycle.private_value',
      'cycle.private_notes',
      'cycle.save',
      'cycle.cancel',
      'cycle.archive',
      'cycle.shared_calendar',
      'cycle.shared_empty',
      'cycle.share_success',
      'cycle.revoke_success',
      'cycle.event_title',
      'cycle.phase',
      'cycle.phase.period',
      'cycle.phase.follicular',
      'cycle.phase.ovulation',
      'cycle.phase.luteal',
      'cycle.phase.other',
      'cycle.end_date',
      'cycle.flow_private',
      'cycle.flow.unspecified',
      'cycle.flow.light',
      'cycle.flow.medium',
      'cycle.flow.heavy',
      'cycle.symptoms_private',
      'cycle.notes_recorded',
      'cycle.category.symptom',
      'cycle.category.spotting',
      'cycle.category.contraception',
      'cycle.category.intimacy',
      'cycle.category.temperature',
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

  test('cycle forecast learns from history and widens irregular ranges', () {
    final regular = CycleForecastEngine.estimate([
      CyclePeriod(startsOn: DateTime.utc(2026, 1, 1)),
      CyclePeriod(startsOn: DateTime.utc(2026, 1, 29)),
      CyclePeriod(startsOn: DateTime.utc(2026, 2, 26)),
      CyclePeriod(startsOn: DateTime.utc(2026, 3, 26)),
      CyclePeriod(startsOn: DateTime.utc(2026, 4, 23)),
      CyclePeriod(startsOn: DateTime.utc(2026, 5, 21)),
    ]);
    final irregular = CycleForecastEngine.estimate([
      CyclePeriod(startsOn: DateTime.utc(2026, 1, 1)),
      CyclePeriod(startsOn: DateTime.utc(2026, 1, 23)),
      CyclePeriod(startsOn: DateTime.utc(2026, 3, 1)),
      CyclePeriod(startsOn: DateTime.utc(2026, 3, 22)),
    ]);
    expect(regular.averageCycleDays, 28);
    expect(regular.confidence, CycleConfidence.high);
    expect(
      irregular.nextPeriodTo!.difference(irregular.nextPeriodFrom!).inDays,
      greaterThan(
        regular.nextPeriodTo!.difference(regular.nextPeriodFrom!).inDays,
      ),
    );
  });

  test('insufficient history never invents a fertility prediction', () {
    final result = CycleForecastEngine.estimate([
      CyclePeriod(startsOn: DateTime.utc(2026, 1, 1)),
    ]);
    expect(result.confidence, CycleConfidence.insufficient);
    expect(result.hasEstimate, isFalse);
    expect(result.estimatedOvulationFrom, isNull);
  });

  test('cycle enrichment remains owner-only and outside shared projection', () {
    final sql = File(
      'supabase/migrations/20261115105102_cycle_personal_tracking_enrichment.sql',
    ).readAsStringSync();
    expect(sql, contains('member_cycle_private_entries_owner_read'));
    expect(sql, contains('owner_user_id = (select auth.uid())'));
    expect(sql, contains('revoke all'));
    expect(sql, isNot(contains('read_shared_cycle_calendar')));
    expect(sql, isNot(contains('realtime')));
    expect(strictlyPrivateCycleCategories, contains('intimacy'));
    expect(strictlyPrivateCycleCategories, contains('contraception'));
    expect(strictlyPrivateCycleCategories, contains('libido'));
  });

  test('strictly private cycle journal is absent from household consumers', () {
    const forbiddenConsumers = [
      'lib/features/dashboard',
      'lib/features/assistant',
      'lib/features/finance',
      'lib/features/search',
    ];
    for (final root in forbiddenConsumers) {
      final directory = Directory(root);
      if (!directory.existsSync()) continue;
      for (final file
          in directory.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        expect(
          file.readAsStringSync(),
          isNot(contains('member_cycle_private_entries')),
          reason: file.path,
        );
      }
    }
  });

  test('cycle sharing mutation refreshes both owner and recipient views', () {
    final source = File(
      'lib/features/organization/application/daily_life_provider.dart',
    ).readAsStringSync();
    final method = source.substring(
      source.indexOf('Future<void> setCycleShare'),
      source.indexOf('Future<void> addCyclePrivateEntry'),
    );
    expect(method, contains('ref.invalidate(ownCycleSharesProvider)'));
    expect(method, contains('ref.invalidate(cycleEventsProvider)'));
    final realtime = File(
      'lib/features/portability/application/household_realtime_provider.dart',
    ).readAsStringSync();
    expect(realtime, contains("case 'member_cycle_calendar_shares':"));
    expect(realtime, contains('ref.invalidate(cycleEventsProvider)'));
  });

  test('cycle sharing UI awaits mutation and exposes success or failure', () {
    final source = File(
      'lib/features/organization/presentation/daily_life_page.dart',
    ).readAsStringSync();
    final cycleTab = source.substring(
      source.indexOf('class _CycleTabState'),
      source.indexOf('class _CycleForecastCard'),
    );
    expect(cycleTab, contains('await ref'));
    expect(cycleTab, contains('cycle.share_success'));
    expect(cycleTab, contains('cycle.revoke_success'));
    expect(cycleTab, contains('userSafeErrorMessage(context, error)'));
    expect(cycleTab, contains('_pendingRecipients.contains(member.id)'));
  });

  test('rendered Cycle dialogs contain no residual French literals', () {
    final source = File(
      'lib/features/organization/presentation/daily_life_page.dart',
    ).readAsStringSync();
    final dialog = source.substring(
      source.indexOf('Future<void> _cycleDialog'),
      source.indexOf('Future<void> _cyclePrivateEntryDialog'),
    );
    for (final literal in const [
      'Événement personnel',
      'Ajouter une date de fin',
      'Flux (privé)',
      'Non précisé',
      'Symptômes privés',
      'Notes privées',
      "Text('Annuler')",
      "Text('Enregistrer')",
    ]) {
      expect(dialog, isNot(contains(literal)), reason: literal);
    }
  });
}
