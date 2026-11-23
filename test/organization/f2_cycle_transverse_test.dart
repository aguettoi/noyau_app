import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/localization/app_locale.dart';
import 'package:noyau_app/core/localization/household_locale.dart';
import 'package:noyau_app/features/organization/domain/cycle_tracking.dart';
import 'package:noyau_app/features/organization/domain/organization_models.dart';

void main() {
  const migration =
      'supabase/migrations/20261121221356_f2_cycle_forecast_consent.sql';
  const engineMigration =
      'supabase/migrations/20261121224551_f2_cycle_engine_v2.sql';
  const measurementMigration =
      'supabase/migrations/20261121224750_f2_cycle_measurement_constraints.sql';

  test('dates and forecast consents are independent and owner managed', () {
    final sql = File(migration).readAsStringSync();
    expect(sql, contains('member_cycle_forecast_shares'));
    expect(sql, contains('member_cycle_calendar_shares'));
    expect(sql, contains('member_cycle_forecast_shares_owner_create'));
    expect(sql, contains('member_cycle_forecast_shares_owner_delete'));
    expect(sql, contains('owner_user_id = (select auth.uid())'));
    expect(sql, isNot(contains('admin')));
    expect(sql, contains('revoke all on public.member_cycle_forecast_shares'));
    expect(sql, contains('from public, anon'));
  });

  test('canonical projection contains no intimate Cycle columns', () {
    final sql = File(engineMigration).readAsStringSync();
    final projection = sql.substring(
      sql.indexOf('create function public.read_authorized_cycle_timeline_v2'),
    );
    for (final forbidden in [
      'symptoms',
      'notes',
      'flow',
      'contraception',
      'intimacy',
      'libido',
      'temperature',
      'weight',
      'member_cycle_private_entries',
    ]) {
      expect(projection, isNot(contains(forbidden)));
    }
    expect(projection, contains("'observation'::text"));
    expect(projection, contains("'forecast'"));
    expect(projection, contains('authorized_observation_owners'));
    expect(projection, contains('authorized_forecast_owners'));
    expect(projection, contains("'fertile_window', 'forecast'"));
    expect(projection, contains("'cycle-sql-v2.0.0'"));
    expect(projection, contains('sample_size >= 2'));
    expect(projection, contains('variability_days <= 14'));
  });

  test('forecast remains an estimate with explicit uncertainty', () {
    final forecast = CycleForecastEngine.estimate([
      CyclePeriod(startsOn: DateTime.utc(2026, 1, 1)),
      CyclePeriod(startsOn: DateTime.utc(2026, 1, 23)),
      CyclePeriod(startsOn: DateTime.utc(2026, 3, 1)),
      CyclePeriod(startsOn: DateTime.utc(2026, 3, 22)),
    ]);
    expect(forecast.hasEstimate, isTrue);
    expect(forecast.variabilityDays, greaterThan(0));
    expect(
      forecast.nextPeriodTo!.difference(forecast.nextPeriodFrom!).inDays,
      greaterThan(4),
    );
  });

  test('projection model cannot carry private observations', () {
    final projection = AuthorizedCycleProjection(
      key: 'forecast:owner:period',
      ownerUserId: 'owner',
      startsOn: DateTime.utc(2026, 12, 1),
      endsOn: DateTime.utc(2026, 12, 5),
      phase: 'period',
      kind: CycleProjectionKind.forecast,
      confidence: CycleConfidence.medium,
    );
    expect(projection.isEstimate, isTrue);
    expect(
      CalendarEntry(
        key: projection.key,
        title: 'Estimation',
        date: projection.startsOn,
        source: CalendarSource.cycle,
        kind: CalendarEntryKind.estimate,
      ).kind,
      CalendarEntryKind.estimate,
    );
  });

  test('new Cycle consent copy is complete in four languages', () {
    const keys = {
      'cycle.forecast_share_title',
      'cycle.forecast_share_allowed',
      'cycle.forecast_share_success',
      'cycle.forecast_revoke_success',
      'cycle.estimate',
      'cycle.observation',
      'cycle.fertile_window',
      'cycle.abstention',
      'cycle.category.lh_test',
      'cycle.category.basal_temperature',
      'cycle.measurement_warning',
    };
    for (final language in AppLanguage.values) {
      for (final key in keys) {
        expect(HouseholdWords.hasOwnTranslation(language, key), isTrue);
      }
    }
  });

  test(
    'Realtime invalidates Cycle projection, calendar and owner consents',
    () {
      final source = File(
        'lib/features/portability/application/household_realtime_provider.dart',
      ).readAsStringSync();
      expect(source, contains("case 'member_cycle_forecast_shares':"));
      expect(source, contains('authorizedCycleTimelineProvider'));
      expect(source, contains('organizationCalendarProvider'));
      expect(source, contains('ownCycleForecastSharesProvider'));
    },
  );

  test('forecast projection is not persisted in the offline read cache', () {
    final source = File(
      'lib/features/organization/application/daily_life_provider.dart',
    ).readAsStringSync();
    final projection = source.substring(
      source.indexOf('final authorizedCycleTimelineProvider'),
      source.indexOf('AuthorizedCycleProjection _cycleProjection'),
    );
    expect(projection, isNot(contains('saveReadSnapshot')));
    expect(projection, isNot(contains('loadReadSnapshot')));
  });

  test('forecast consent is visibly separate from dates and phases', () {
    final source = File(
      'lib/features/organization/presentation/daily_life_page.dart',
    ).readAsStringSync();
    expect(source, contains("Key('cycle-dates-share-\${member.id}')"));
    expect(source, contains("Key('cycle-forecast-share-\${member.id}')"));
    expect(source, contains('cycle.forecast_share_title'));
    expect(source, contains('setCycleForecastShare'));
  });

  test('exports and search do not consume Cycle projections', () {
    final source = File(
      'lib/features/portability/application/portability_provider.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('member_cycle_private_entries')));
    expect(source, isNot(contains('read_authorized_cycle_timeline')));
    expect(source, isNot(contains('member_cycle_forecast_shares')));
  });

  test('LH and BBT are structured, owner-only and never projected', () {
    final engineSql = File(engineMigration).readAsStringSync();
    final sql =
        '$engineSql\n'
        '${File(measurementMigration).readAsStringSync()}';
    expect(sql, contains("category = 'lh_test'"));
    expect(sql, contains("test_result in ('negative','positive')"));
    expect(sql, contains("category = 'basal_temperature'"));
    expect(sql, contains("measurement_unit in ('celsius','fahrenheit')"));
    final projection = engineSql.substring(
      engineSql.indexOf(
        'create function public.read_authorized_cycle_timeline_v2',
      ),
    );
    expect(projection, isNot(contains('measurement_value')));
    expect(projection, isNot(contains('test_result')));
    expect(projection, isNot(contains('member_cycle_private_entries')));
    expect(strictlyPrivateCycleCategories, contains('lh_test'));
    expect(strictlyPrivateCycleCategories, contains('basal_temperature'));
  });
}
