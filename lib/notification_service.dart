import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:ui';

class NotificationService {
  static final NotificationService instance = NotificationService._internal();

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  
  // Callback to notify the app when medication state changes via notification
  VoidCallback? onMedicationStateChanged;

  Future<void> init() async {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation(await _getTimezone()));

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          onDidReceiveBackgroundNotificationResponse,
    );

    // Request permissions
    final androidImplementation =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImplementation?.requestNotificationsPermission();
    await androidImplementation?.requestExactAlarmsPermission();
  }

  Future<void> scheduleDailyNotification(
      int id, String title, String body, DateTime scheduledTime) async {
    final tz.TZDateTime scheduledTZTime = _nextInstanceOfTime(scheduledTime);
    print(
        'Scheduling notification $id for: $scheduledTZTime in timezone ${tz.local}');

    await flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      scheduledTZTime,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_medication_channel',
          'Medication Reminders',
          channelDescription: 'Reminders to take your medication',
          importance: Importance.max,
          priority: Priority.high,
          actions: <AndroidNotificationAction>[
            AndroidNotificationAction(
              'MARK_AS_TAKEN_ACTION', // An ID for the action
              'Mark as Taken',
              showsUserInterface: false,
            ),
          ],
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: title, // Pass the title which contains the medication name
    );
  }

  tz.TZDateTime _nextInstanceOfTime(DateTime time) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, time.hour, time.minute);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }

  Future<void> cancelNotification(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id);
  }

  Future<void> showTestNotification() async {
    const AndroidNotificationDetails androidNotificationDetails =
        AndroidNotificationDetails(
      'test_channel',
      'Test Notifications',
      channelDescription: 'Channel for testing notifications',
      importance: Importance.max,
      priority: Priority.high,
    );
    const NotificationDetails notificationDetails =
        NotificationDetails(android: androidNotificationDetails);

    await flutterLocalNotificationsPlugin.show(
        99, // A static ID for the test notification
        'Test Notification',
        'If you see this, notifications are working!',
        notificationDetails);
  }

  Future<String> _getTimezone() async {
    return await FlutterTimezone.getLocalTimezone();
  }
}

@pragma('vm:entry-point')
void onDidReceiveBackgroundNotificationResponse(
    NotificationResponse response) async {
  // Handle the notification tap event in the background.
  // IMPORTANT: a 'pragma' is required for this function to be found by the plugin.
  // And we need to manually initialize the plugin registration.
  DartPluginRegistrant.ensureInitialized();

  if (response.payload != null && response.actionId == 'MARK_AS_TAKEN_ACTION') {
    print('Background action tapped: ${response.payload}');
    // We need to initialize SharedPreferences in this background isolate.
    final prefs = await SharedPreferences.getInstance();
    final payload = response.payload;
    if (payload == null) return;

    // Extract medication name from the title payload
    // e.g., "Time for your Morning Dose!" -> "Morning Dose"
    String? medName;
    if (payload.contains("Morning Dose")) medName = "Morning Dose";
    if (payload.contains("Evening Dose")) medName = "Evening Dose";
    if (medName == null) return;

    // Create the key for today's dose
    final now = DateTime.now();
    final key = '${medName}_${now.year}-${now.month}-${now.day}';

    await prefs.setBool(key, true);
    
    // Note: We can't call the callback from background isolate,
    // but the app will reload state when it resumes (handled in didChangeAppLifecycleState)
  }
}

void onDidReceiveNotificationResponse(NotificationResponse response) async {
  // Handle notification tap when app is in foreground/background but not terminated.
  print('Notification response received - actionId: ${response.actionId}, payload: ${response.payload}');
  
  if (response.actionId == 'MARK_AS_TAKEN_ACTION' && response.payload != null) {
    print('Foreground action tapped: ${response.payload}');
    final prefs = await SharedPreferences.getInstance();
    final payload = response.payload;
    if (payload == null) {
      print('Payload is null, returning');
      return;
    }

    // Extract medication name from the title payload
    // e.g., "Time for your Morning Dose!" -> "Morning Dose"
    String? medName;
    if (payload.contains("Morning Dose")) medName = "Morning Dose";
    if (payload.contains("Evening Dose")) medName = "Evening Dose";
    
    print('Extracted medication name: $medName');
    if (medName == null) {
      print('Could not extract medication name from payload: $payload');
      return;
    }

    // Create the key for today's dose
    final now = DateTime.now();
    final key = '${medName}_${now.year}-${now.month}-${now.day}';
    print('Setting key $key to true');

    await prefs.setBool(key, true);
    print('SharedPreferences updated successfully');
    
    // Notify the app to update UI - ensure it runs on the main isolate
    final callback = NotificationService.instance.onMedicationStateChanged;
    if (callback != null) {
      print('Calling callback to update UI');
      // Use scheduleMicrotask to ensure it runs on the main isolate
      scheduleMicrotask(() {
        callback();
      });
    } else {
      print('Warning: onMedicationStateChanged callback is null!');
    }
  } else if (response.actionId == null) {
    // User tapped the notification itself (not the action button)
    print('Notification tapped (not action button)');
  }
}
