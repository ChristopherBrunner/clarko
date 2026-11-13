import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/splash_screen.dart';
import 'services/notification_service.dart';
import 'services/storage.dart';
import 'services/widget_service.dart';
import 'state/app_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final notifications = NotificationService.instance;
  await notifications.init();

  final state = AppState(Storage());
  // Re-sync reminders whenever the schedule changes (including initial load).
  state.onScheduleChanged = notifications.syncSchedule;
  // Redraw the home widget after any state change (it reads the saved state).
  state.onStateChanged =
      () => WidgetService.refresh(dark: state.effectiveDark);
  // A dose ticked off in the app no longer needs its reminder in the tray.
  state.onDoseTaken = notifications.dismissReminder;
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
    // (notification actions, the home widget, or a new day). A day change
    // while the app stays open is handled by AppState's own new-day timer.
    if (lifecycle == AppLifecycleState.resumed) {
      widget.state.reloadLog();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        return MaterialApp(
          title: 'Clarko',
          debugShowCheckedModeBanner: false,
          theme: _buildTheme(Brightness.light),
          darkTheme: _buildTheme(Brightness.dark),
          themeMode: widget.state.themeMode,
          home: SplashScreen(state: widget.state),
        );
      },
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2FA66A), // Clarko green
      brightness: brightness,
    );
    final isLight = brightness == Brightness.light;
    // Icons/text contrasting the surface: dark on light, light on dark.
    final overlayIcons = isLight ? Brightness.dark : Brightness.light;
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        // Blend into the background — no standalone coloured bar.
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: overlayIcons,
          statusBarBrightness: brightness,
          systemNavigationBarColor: scheme.surface,
          systemNavigationBarIconBrightness: overlayIcons,
          systemNavigationBarContrastEnforced: false,
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
