import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

enum ReminderSnoozeChoice { laterToday, tomorrow, threeDays, notYet }

class ReminderSnoozeDecision {
  const ReminderSnoozeDecision({
    required this.untilUtc,
    this.rolledToTomorrow = false,
  });

  final DateTime untilUtc;
  final bool rolledToTomorrow;
}

class ReminderSnoozePolicy {
  ReminderSnoozePolicy._();

  static bool _initialized = false;

  static void _initialize() {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    _initialized = true;
  }

  static tz.Location _location(String timezone) {
    _initialize();
    return tz.getLocation(timezone);
  }

  static DateTime localNow(String timezone, DateTime nowUtc) =>
      tz.TZDateTime.from(nowUtc.toUtc(), _location(timezone));

  static ReminderSnoozeDecision decide({
    required ReminderSnoozeChoice choice,
    required DateTime nowUtc,
    required String timezone,
  }) {
    final location = _location(timezone);
    final now = tz.TZDateTime.from(nowUtc.toUtc(), location);
    late tz.TZDateTime target;
    var rolledToTomorrow = false;

    switch (choice) {
      case ReminderSnoozeChoice.laterToday:
        target = tz.TZDateTime(location, now.year, now.month, now.day, 23);
        // Less than 30 minutes is not a useful "later today" window.
        if (!target.isAfter(now.add(const Duration(minutes: 30)))) {
          target = tz.TZDateTime(location, now.year, now.month, now.day + 1, 9);
          rolledToTomorrow = true;
        }
        break;
      case ReminderSnoozeChoice.tomorrow:
      case ReminderSnoozeChoice.notYet:
        target = tz.TZDateTime(location, now.year, now.month, now.day + 1, 20);
        break;
      case ReminderSnoozeChoice.threeDays:
        target = tz.TZDateTime(location, now.year, now.month, now.day + 3, 20);
        break;
    }

    final untilUtc = target.toUtc();
    if (!untilUtc.isAfter(nowUtc.toUtc())) {
      throw StateError('La date de rappel doit être future.');
    }
    return ReminderSnoozeDecision(
      untilUtc: untilUtc,
      rolledToTomorrow: rolledToTomorrow,
    );
  }

  static DateTime custom({
    required DateTime localDateAndTime,
    required DateTime nowUtc,
    required String timezone,
  }) {
    final location = _location(timezone);
    final target = tz.TZDateTime(
      location,
      localDateAndTime.year,
      localDateAndTime.month,
      localDateAndTime.day,
      localDateAndTime.hour,
      localDateAndTime.minute,
    ).toUtc();
    if (!target.isAfter(nowUtc.toUtc())) {
      throw StateError('Choisissez une date et une heure futures.');
    }
    return target;
  }
}
