import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/dose.dart';
import 'storage.dart';
import 'widget_service.dart';

const _channelId = 'dose_reminders';
const _channelName = 'Dose reminders';
const _markTakenAction = 'mark_taken';

/// Handles "Mark as taken" taps that arrive while the app is not in the
/// foreground. Runs in a background isolate, so it talks to storage directly
/// rather than going through [AppState].
@pragma('vm:entry-point')
void notificationBackgroundHandler(NotificationResponse response) async {
  if (response.actionId == _markTakenAction && response.payload != null) {
    // This runs in a background isolate; plugins (shared_preferences,
    // home_widget) aren't registered automatically here.
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    await _markTakenInStorage(response.payload!);
  }
}

Future<void> _markTakenInStorage(String doseId) async {
  final storage = Storage();
  final doses = await storage.loadSchedule();
  final log = await storage.loadLog();
  final now = DateTime.now();
  log.setTaken(doseId, now, true);
  await storage.saveLog(log);

  // Refresh the home widget so the taken-state shows there too. Never let a
  // widget hiccup undo the (already persisted) log write.
  try {
    final enabled = doses.where((d) => d.enabled).toList();
    await WidgetService.render(
      enabled,
      (d) => log.isTaken(d.id, now),
      log.currentStreak(doses, now),
    );
  } catch (e) {
    debugPrint('Widget refresh after mark-taken failed: $e');
  }
}

/// Schedules and manages the daily dose reminders.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Called on the UI isolate when a "Mark as taken" action is handled while
  /// the app is alive, so state can refresh.
  void Function(String doseId)? onMarkTaken;

  Future<void> init() async {
    tz.initializeTimeZones();
    try {
      final localName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localName));
    } catch (e) {
      debugPrint('Could not resolve local timezone: $e');
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onForegroundResponse,
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
    );
  }

  void _onForegroundResponse(NotificationResponse response) {
    if (response.actionId == _markTakenAction && response.payload != null) {
      final doseId = response.payload!;
      // Persist the taken-state, then let the app refresh its UI.
      _markTakenInStorage(doseId).then((_) => onMarkTaken?.call(doseId));
    }
  }

  /// Requests notification + exact-alarm permissions (Android 13+ / 12+).
  /// Returns whether notifications are permitted.
  Future<bool> requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    final granted = await android.requestNotificationsPermission() ?? false;
    await android.requestExactAlarmsPermission();
    return granted;
  }

  /// Reschedules reminders to match [doses]: cancels everything and schedules
  /// one daily reminder per enabled dose.
  Future<void> syncSchedule(List<Dose> doses) async {
    await _plugin.cancelAll();
    for (final dose in doses) {
      if (!dose.enabled) continue;
      await _scheduleDose(dose);
    }
  }

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Reminders to take your medication',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      actions: [
        AndroidNotificationAction(
          _markTakenAction,
          'Mark as taken',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    ),
  );

  Future<void> _scheduleDose(Dose dose) async {
    await _plugin.zonedSchedule(
      _notificationId(dose.id),
      'Time for your ${dose.label} dose',
      '${dose.dosageLabel} · tap to open Clarko',
      _nextInstanceOf(dose.hour, dose.minute),
      _details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: dose.id,
    );
  }

  tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  /// Deterministic, stable notification id derived from the dose id so it
  /// survives reordering and app restarts.
  static int _notificationId(String doseId) {
    var hash = 0;
    for (final code in doseId.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return hash % 100000;
  }
}
