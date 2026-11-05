import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/platform/native_notification_contract.dart';
import 'package:noyau_app/core/platform/native_notification_adapter.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:noyau_app/core/platform/platform_link_contract.dart';

void main() {
  test('native timezone accepts Android GMT and keeps named zones', () {
    tz_data.initializeTimeZones();
    expect(resolveNativeTimezone('GMT').name, 'UTC');
    expect(
      resolveNativeTimezone('Africa/Casablanca').name,
      'Africa/Casablanca',
    );
    expect(resolveNativeTimezone('Unknown/DeviceZone').name, 'UTC');
  });

  group('P1 deep-link contract', () {
    test('accepts only the permanent scheme and allow-listed destinations', () {
      expect(
        PlatformLinkContract.parse(
          Uri.parse('com.financielpilote.app://open?destination=imports'),
        )?.value,
        'imports',
      );
      expect(
        PlatformLinkContract.parse(
          Uri.parse(
            'com.financielpilote.app://open?destination=private-account',
          ),
        ),
        isNull,
      );
      expect(
        PlatformLinkContract.parse(Uri.parse('https://example.test/open')),
        isNull,
      );
    });

    test('keeps invitation data opaque and rejects malformed links', () {
      final intent = PlatformLinkContract.parse(
        Uri.parse('com.financielpilote.app://invite?code=opaque_code-123'),
      );
      expect(intent?.kind, PlatformLinkKind.invitation);
      expect(intent?.value, 'opaque_code-123');
      expect(
        PlatformLinkContract.parse(
          Uri.parse('com.financielpilote.app://invite'),
        ),
        isNull,
      );
    });
  });

  group('P1 native reminder contract', () {
    test('Pas encore is exactly fifteen minutes through canonical policy', () {
      final now = DateTime.utc(2026, 11, 5, 19, 45);
      expect(
        NativeReminderPolicy.notYet(nowUtc: now, timezone: 'Africa/Casablanca'),
        now.add(const Duration(minutes: 15)),
      );
    });

    test('system notification text is generic and privacy safe', () {
      expect(
        NativeReminderPolicy.isPrivacySafeText(
          NativeReminderPolicy.genericBody,
        ),
        isTrue,
      );
      expect(
        NativeReminderPolicy.isPrivacySafeText('Solde 1 000 MAD'),
        isFalse,
      );
      expect(
        NativeReminderPolicy.isPrivacySafeText('Symptôme enregistré'),
        isFalse,
      );
    });

    test('payload contains only allow-listed route and opaque key', () {
      const payload = NativeReminderPayload(
        reminderKey: 'daily_entry',
        route: 'household/reminders',
      );
      expect(
        NativeReminderPayload.decode(payload.encode())?.route,
        'household/reminders',
      );
      expect(
        NativeReminderPayload.decode('v1|x|money/private-account'),
        isNull,
      );
      expect(
        NativeReminderPayload.decode(
          'v1|daily-entry:native|household/reminders',
        )?.reminderKey,
        'daily-entry:native',
      );
    });
  });
}
