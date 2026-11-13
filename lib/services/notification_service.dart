import 'dart:isolate';
import 'dart:ui' show Color, DartPluginRegistrant, IsolateNameServer;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/day.dart';
import '../models/dose.dart';
import 'storage.dart';
import 'widget_service.dart';

// Android freezes a channel's sound when the channel is first created, so a
// different sound needs a new channel id (and the old channel removed).
const _channelId = 'dose_reminders_v2';
const _retiredChannelIds = ['dose_reminders'];
const _channelName = 'Dose reminders';
const _markTakenAction = 'mark_taken';

/// A short, soft two-note chime: android/app/src/main/res/raw/clarko_chime.wav
/// (swap that file to change the sound, then bump [_channelId]). It is looked
/// up by name at runtime, so res/raw/keep.xml must keep it in release builds.
const _reminderSound = RawResourceAndroidNotificationSound('clarko_chime');

/// Clarko green — tints the small icon and action text of the reminder.
const _brandColor = Color(0xFF2FA66A);

/// Name under which the app's UI isolate listens for "the log was changed by
/// a reminder action". Action buttons are always handled in a background
/// isolate — even while the app is open on screen — so without this the open
/// app would keep showing (and later save) a stale log.
const _logChangedPortName = 'clarko.reminder_log_changed';

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

  // The tap counts for the day the reminder fired, which is not necessarily
  // today: last night's reminder answered the next morning is about yesterday.
  var day = clarkoDay(now);
  for (final dose in doses) {
    if (dose.id == doseId) day = dose.reminderDay(now);
  }
  log.setTaken(doseId, day, true);
  await storage.saveLog(log);

  // Tell the app, if it is running, to pick the change up right away.
  IsolateNameServer.lookupPortByName(_logChangedPortName)?.send(doseId);

  // Refresh the home widget so the taken-state shows there too. Never let a
  // widget hiccup undo the (already persisted) log write.
  try {
    await WidgetService.refresh();
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

  /// Small native helper (see MainActivity) for things the notifications
  /// plugin can't do — currently: clearing a shown reminder without also
  /// cancelling its daily schedule.
  static const _native = MethodChannel('clarko/reminders');

  /// Called on the UI isolate when a "Mark as taken" action is handled while
  /// the app is alive, so state can refresh.
  void Function(String doseId)? onMarkTaken;

  ReceivePort? _logChangedPort;

  /// Listens for reminder actions handled by the background isolate (see
  /// [_logChangedPortName]) and forwards them to [onMarkTaken].
  void _listenForBackgroundChanges() {
    _logChangedPort?.close();
    final port = ReceivePort();
    _logChangedPort = port;
    // Replace any mapping left behind by a previous run of the UI isolate.
    IsolateNameServer.removePortNameMapping(_logChangedPortName);
    IsolateNameServer.registerPortWithName(port.sendPort, _logChangedPortName);
    port.listen((message) {
      if (message is String) onMarkTaken?.call(message);
    });
  }

  Future<void> init() async {
    _listenForBackgroundChanges();
    tz.initializeTimeZones();
    try {
      final localName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localName));
    } catch (e) {
      debugPrint('Could not resolve local timezone: $e');
    }

    // The icon is looked up by name at runtime, so res/raw/keep.xml must keep
    // it from being stripped out of release builds.
    const android = AndroidInitializationSettings('@drawable/ic_notification');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onForegroundResponse,
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
    );

    // Drop channels from earlier versions so they don't linger in the system
    // notification settings (reminders are rescheduled on the current one).
    final platform = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    for (final id in _retiredChannelIds) {
      await platform?.deleteNotificationChannel(id);
    }
  }

  void _onForegroundResponse(NotificationResponse response) {
    if (response.actionId == _markTakenAction && response.payload != null) {
      // Persists the taken-state; the app is then told to refresh through the
      // same port the background isolate uses.
      _markTakenInStorage(response.payload!);
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

  /// Clears [dose]'s reminder from the notification tray if it is showing
  /// (e.g. the dose was just ticked off in the app instead of on the
  /// notification). The daily schedule itself is left untouched.
  Future<void> dismissReminder(Dose dose) async {
    try {
      await _native.invokeMethod<void>('dismiss', {'id': notificationId(dose.id)});
    } catch (e) {
      debugPrint('Could not dismiss reminder: $e');
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
      color: _brandColor,
      sound: _reminderSound,
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
      notificationId(dose.id),
      reminderTitle(dose),
      reminderBody(dose),
      _nextInstanceOf(dose.hour, dose.minute),
      _details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: dose.id,
    );
  }

  /// e.g. "☀️ Morning dose" / "🌙 Night dose".
  static String reminderTitle(Dose dose) =>
      '${dose.isNight ? '🌙' : '☀️'} ${dose.label} dose';

  /// e.g. "Time for 500mg + 250mg (750mg)".
  static String reminderBody(Dose dose) => dose.tablets.isEmpty
      ? 'Time to take your medication'
      : 'Time for ${dose.dosageLabel}';

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
  /// survives reordering and app restarts. The native side derives the same
  /// id (`ClarkoStore.reminderNotificationId`) — keep the two in sync.
  static int notificationId(String doseId) {
    var hash = 0;
    for (final code in doseId.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return hash % 100000;
  }
}
