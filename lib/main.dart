import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import 'screens/home_screen.dart';
import 'services/notification_service.dart';
import 'services/storage.dart';
import 'services/widget_service.dart';
import 'state/app_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final notifications = NotificationService.instance;
  await notifications.init();

  // Route home-widget button taps to the background interaction handler.
  await HomeWidget.registerInteractivityCallback(widgetInteractionCallback);

  final state = AppState(Storage());
  // Re-sync reminders whenever the schedule changes (including initial load).
  state.onScheduleChanged = notifications.syncSchedule;
  // Refresh the home widget after any state change.
  state.onStateChanged = () =>
      WidgetService.render(state.enabledDoses, state.isTaken, state.streak);
  // Refresh state when a dose is marked taken from a notification action.
  notifications.onMarkTaken = (_) => state.reloadLog();

  await state.load();
  await notifications.requestPermissions();

  runApp(ClarkoApp(state: state));
}

class ClarkoApp extends StatefulWidget {
  const ClarkoApp({super.key, required this.state});

  final AppState state;

  @override
  State<ClarkoApp> createState() => _ClarkoAppState();
}

class _ClarkoAppState extends State<ClarkoApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    // Pick up taken-state changes made while we were backgrounded
    // (notification actions, the home widget, or a new day).
    if (lifecycle == AppLifecycleState.resumed) {
      widget.state.reloadLog();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Clarko',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home: HomeScreen(state: widget.state),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: Colors.teal,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 2,
        titleTextStyle: TextStyle(
          color: scheme.onPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
      cardTheme: CardTheme(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }
}
