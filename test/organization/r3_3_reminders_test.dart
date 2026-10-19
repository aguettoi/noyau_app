import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/organization/domain/organization_models.dart';
import 'package:noyau_app/features/organization/domain/reminder_snooze_policy.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  group('report personnel commun aux phases de l’occurrence', () {
    final now = DateTime.utc(2026, 10, 19, 19);
    AppAlert phase(String name) => AppAlert(
      key: 'r3.1:occurrence:$name',
      title: name,
      detail: '',
      category: 'reminders',
      source: CalendarSource.recurringFinance,
      sourceId: 'occurrence',
    );
    for (final action in ['snoozed', 'not_yet']) {
      test('$action bloque DAY et AFTER puis expire après relecture', () {
        final states = {
          'reminder-source:r3_1_occurrence:occurrence': UserAlertState(
            key: 'reminder-source:r3_1_occurrence:occurrence',
            snoozedUntil: now.add(const Duration(hours: 3)),
            lastAction: action,
          ),
        };
        for (final name in ['day', 'after']) {
          expect(alertVisibleAt(phase(name), states, now), isFalse);
          expect(alertVisibleAt(phase(name), Map.of(states), now), isFalse);
        }
        expect(
          alertVisibleAt(
            phase('after'),
            states,
            now.add(const Duration(hours: 3)),
          ),
          isTrue,
        );
        // Another user's independently fetched state is unaffected.
        expect(alertVisibleAt(phase('after'), {}, now), isTrue);
      });
    }
    test('lu/masqué restent limités à la phase', () {
      final states = {
        phase('day').key: UserAlertState(
          key: phase('day').key,
          dismissedAt: now,
          readAt: now,
        ),
      };
      expect(alertVisibleAt(phase('day'), states, now), isFalse);
      expect(alertVisibleAt(phase('after'), states, now), isTrue);
    });
    test('un autre type de source conserve sa sémantique', () {
      const alert = AppAlert(
        key: 'risk',
        title: '',
        detail: '',
        category: 'reminders',
      );
      expect(
        alertVisibleAt(alert, {
          'risk': UserAlertState(
            key: 'risk',
            snoozedUntil: now.add(const Duration(hours: 1)),
          ),
        }, now),
        isFalse,
      );
    });
  });
  test('snooze et Pas encore masquent temporairement sans résoudre', () {
    final now = DateTime.utc(2026, 10, 18, 12);
    final state = UserAlertState(
      key: 'r3.1:occurrence:day',
      snoozedUntil: now.add(const Duration(hours: 4)),
      lastAction: 'not_yet',
    );
    expect(state.visibleAt(now), isFalse);
    expect(state.visibleAt(now.add(const Duration(hours: 5))), isTrue);
    expect(state.dismissedAt, isNull);
  });

  test('un rappel masqué ne redevient pas actif', () {
    final now = DateTime.utc(2026, 10, 18);
    expect(
      UserAlertState(
        key: 'risk',
        dismissedAt: now,
      ).visibleAt(now.add(const Duration(days: 2))),
      isFalse,
    );
  });

  test('une règle conserve priorité, destinataire et paramètres', () {
    const rule = ReminderRule(
      type: 'expected_occurrence',
      enabled: true,
      priority: HouseholdTaskPriority.high,
      parameters: {'before_days': 2, 'after_days': 1, 'hour': 20},
      recipientUserId: 'member-a',
    );
    expect(rule.parameters['before_days'], 2);
    expect(rule.recipientUserId, 'member-a');
  });

  group('politique de snooze dans le fuseau canonique', () {
    ReminderSnoozeDecision laterAt(int utcHour, [int minute = 0]) =>
        ReminderSnoozePolicy.decide(
          choice: ReminderSnoozeChoice.laterToday,
          nowUtc: DateTime.utc(2026, 10, 18, utcHour, minute),
          timezone: 'Africa/Casablanca',
        );

    test('matin et après-midi restent à 23 h locales', () {
      expect(laterAt(7).untilUtc, DateTime.utc(2026, 10, 18, 22));
      expect(laterAt(15).untilUtc, DateTime.utc(2026, 10, 18, 22));
    });

    test('avant la limite conserve la journée locale', () {
      final decision = laterAt(21, 20); // 22:20 à Casablanca.
      expect(decision.untilUtc, DateTime.utc(2026, 10, 18, 22));
      expect(decision.rolledToTomorrow, isFalse);
    });

    test('après la limite et juste avant minuit bascule au lendemain', () {
      expect(laterAt(21, 31).rolledToTomorrow, isTrue);
      final nearMidnight = laterAt(22, 59); // 23:59 à Casablanca.
      expect(nearMidnight.rolledToTomorrow, isTrue);
      expect(nearMidnight.untilUtc, DateTime.utc(2026, 10, 19, 8));
    });

    test('juste après minuit utilise bien le nouveau jour local', () {
      final decision = laterAt(23, 1); // 00:01 le 19 à Casablanca.
      expect(decision.rolledToTomorrow, isFalse);
      expect(decision.untilUtc, DateTime.utc(2026, 10, 19, 22));
    });

    test('la date locale Casablanca ne suit pas naïvement la date UTC', () {
      final nowUtc = DateTime.utc(2026, 10, 18, 23, 30);
      final local = ReminderSnoozePolicy.localNow('Africa/Casablanca', nowUtc);
      expect(local.day, 19);
      expect(
        ReminderSnoozePolicy.decide(
          choice: ReminderSnoozeChoice.laterToday,
          nowUtc: nowUtc,
          timezone: 'Africa/Casablanca',
        ).untilUtc,
        DateTime.utc(2026, 10, 19, 22),
      );
    });

    test('toutes les échéances sont strictement futures', () {
      final instants = [
        DateTime.utc(2026, 10, 18, 7),
        DateTime.utc(2026, 10, 18, 15),
        DateTime.utc(2026, 10, 18, 21, 20),
        DateTime.utc(2026, 10, 18, 21, 31),
        DateTime.utc(2026, 10, 18, 22, 59),
        DateTime.utc(2026, 10, 18, 23, 1),
      ];
      for (final now in instants) {
        for (final choice in ReminderSnoozeChoice.values) {
          expect(
            ReminderSnoozePolicy.decide(
              choice: choice,
              nowUtc: now,
              timezone: 'Africa/Casablanca',
            ).untilUtc.isAfter(now),
            isTrue,
          );
        }
      }
    });

    test('un changement DST conserve 20 h dans le fuseau demandé', () {
      final now = DateTime.utc(2026, 10, 24, 21);
      final result = ReminderSnoozePolicy.decide(
        choice: ReminderSnoozeChoice.tomorrow,
        nowUtc: now,
        timezone: 'Europe/Paris',
      );
      expect(
        tz.TZDateTime.from(
          result.untilUtc,
          tz.getLocation('Europe/Paris'),
        ).hour,
        20,
      );
      expect(result.untilUtc.isAfter(now), isTrue);
    });

    test('une date choisie passée est refusée', () {
      expect(
        () => ReminderSnoozePolicy.custom(
          localDateAndTime: DateTime(2026, 10, 18, 8),
          nowUtc: DateTime.utc(2026, 10, 18, 12),
          timezone: 'Africa/Casablanca',
        ),
        throwsStateError,
      );
    });
  });
}
