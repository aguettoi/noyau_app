import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'native_notification_contract.dart';

class NativeNotificationAdapter implements NativeNotificationPort {
  NativeNotificationAdapter._();

  static final instance = NativeNotificationAdapter._();

  final _plugin = FlutterLocalNotificationsPlugin();
  final _responses = StreamController<NativeNotificationEvent>.broadcast();
  bool _initialized = false;

  Stream<NativeNotificationEvent> get responses => _responses.stream;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;
    tz_data.initializeTimeZones();
    final timezone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(resolveNativeTimezone(timezone.identifier));

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_financiel_pilote'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
      windows: WindowsInitializationSettings(
        appName: 'FINANCIEL PILOTE',
        appUserModelId: 'com.financielpilote.app',
        guid: 'e37fb3bf-85f2-4f79-a7fe-52fa7ae795cf',
      ),
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _handleResponse,
    );
    _initialized = true;
  }

  void _handleResponse(NotificationResponse response) {
    final payload = NativeReminderPayload.decode(response.payload);
    if (payload == null) return;
    _responses.add(
      NativeNotificationEvent(payload: payload, actionId: response.actionId),
    );
  }

  @override
  Future<bool> requestPermission() async {
    await initialize();
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return await _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.requestNotificationsPermission() ??
            false;
      case TargetPlatform.iOS:
        return await _plugin
                .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin
                >()
                ?.requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      default:
        return true;
    }
  }

  NotificationDetails get _details => const NotificationDetails(
    android: AndroidNotificationDetails(
      'financiel_pilote_reminders',
      'Rappels FINANCIEL PILOTE',
      channelDescription: 'Rappels personnels configurés dans l’application',
      importance: Importance.high,
      priority: Priority.high,
      visibility: NotificationVisibility.private,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction('done', 'Fait', showsUserInterface: true),
        AndroidNotificationAction(
          'not_yet',
          'Pas encore',
          showsUserInterface: true,
        ),
      ],
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );

  @override
  Future<void> scheduleDaily({
    required int id,
    required NativeReminderPayload payload,
    int hour = NativeReminderPolicy.defaultHour,
    int minute = NativeReminderPolicy.defaultMinute,
  }) async {
    await initialize();
    if (kIsWeb) return;
    final now = tz.TZDateTime.now(tz.local);
    var target = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!target.isAfter(now)) target = target.add(const Duration(days: 1));
    await _plugin.zonedSchedule(
      id: id,
      title: NativeReminderPolicy.genericTitle,
      body: NativeReminderPolicy.genericBody,
      scheduledDate: target,
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload.encode(),
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  @override
  Future<void> scheduleOnce({
    required int id,
    required DateTime atUtc,
    required NativeReminderPayload payload,
  }) async {
    await initialize();
    if (kIsWeb) return;
    await _plugin.zonedSchedule(
      id: id,
      title: NativeReminderPolicy.genericTitle,
      body: NativeReminderPolicy.genericBody,
      scheduledDate: tz.TZDateTime.from(atUtc.toUtc(), tz.local),
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload.encode(),
    );
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<void> cancelAll() => _plugin.cancelAll();
}

@visibleForTesting
tz.Location resolveNativeTimezone(String identifier) {
  final normalized = identifier.trim();
  if (normalized.isEmpty ||
      normalized.toUpperCase() == 'GMT' ||
      normalized.toUpperCase() == 'UTC' ||
      normalized.toUpperCase() == 'ETC/GMT' ||
      normalized.toUpperCase() == 'ETC/UTC') {
    return tz.UTC;
  }
  try {
    return tz.getLocation(normalized);
  } on Object {
    return tz.UTC;
  }
}
