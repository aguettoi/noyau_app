import '../../features/organization/domain/reminder_snooze_policy.dart';

enum NativeReminderAction { open, done, notYet }

class NativeReminderPayload {
  const NativeReminderPayload({required this.reminderKey, required this.route});

  final String reminderKey;
  final String route;

  String encode() => 'v1|$reminderKey|$route';

  static NativeReminderPayload? decode(String? value) {
    final parts = value?.split('|');
    if (parts == null || parts.length != 3 || parts.first != 'v1') return null;
    if (!_safeToken(parts[1]) || !_safeRoute(parts[2])) return null;
    return NativeReminderPayload(reminderKey: parts[1], route: parts[2]);
  }

  static bool _safeToken(String value) =>
      value.isNotEmpty && RegExp(r'^[a-z0-9:_-]{1,80}$').hasMatch(value);

  static bool _safeRoute(String value) =>
      const {'household/today', 'household/reminders'}.contains(value);
}

class NativeNotificationEvent {
  const NativeNotificationEvent({required this.payload, this.actionId});

  final NativeReminderPayload payload;
  final String? actionId;
}

abstract final class NativeReminderPolicy {
  static const defaultHour = 20;
  static const defaultMinute = 0;
  static const genericTitle = 'FINANCIEL PILOTE';
  static const genericBody = 'Vous avez un rappel à consulter.';

  static DateTime notYet({
    required DateTime nowUtc,
    required String timezone,
  }) => ReminderSnoozePolicy.decide(
    choice: ReminderSnoozeChoice.notYet,
    nowUtc: nowUtc,
    timezone: timezone,
  ).untilUtc;

  static bool isPrivacySafeText(String value) {
    final normalized = value.toLowerCase();
    const forbidden = <String>[
      'solde',
      'compte',
      'montant',
      'mad',
      'cycle',
      'symptôme',
      'symptome',
      'note privée',
      'flux',
    ];
    return forbidden.every((term) => !normalized.contains(term));
  }
}

abstract interface class NativeNotificationPort {
  Future<bool> requestPermission();
  Future<void> scheduleDaily({
    required int id,
    required NativeReminderPayload payload,
    int hour = NativeReminderPolicy.defaultHour,
    int minute = NativeReminderPolicy.defaultMinute,
  });
  Future<void> scheduleOnce({
    required int id,
    required DateTime atUtc,
    required NativeReminderPayload payload,
  });
  Future<void> cancel(int id);
  Future<void> cancelAll();
}
