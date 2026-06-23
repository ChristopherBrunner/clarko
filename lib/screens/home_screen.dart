import 'package:flutter/material.dart';

import '../models/dose.dart';
import '../state/app_state.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final doses = state.enabledDoses;
        final theme = Theme.of(context);
        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'Clarko',
              style: TextStyle(fontFamily: 'Clarko', fontSize: 28),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Edit schedule',
                onPressed: () {
                  Navigator.of(context).push(_settingsRoute(state));
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StreakCard(
                streak: state.streak,
                takenToday: state.takenTodayCount,
                totalToday: doses.length,
              ),
              const SizedBox(height: 16),
              Text(
                "Today's doses",
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (doses.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('No doses scheduled. Tap the gear to add one.'),
                )
              else
                ...doses.map((dose) => _DoseCard(
                      dose: dose,
                      taken: state.isTaken(dose),
                      onToggle: () => state.toggleTaken(dose),
                    )),
            ],
          ),
        );
      },
    );
  }
}

/// Fast, smooth slide-up + fade transition for the settings screen, so it feels
/// responsive instead of the heavier default platform transition.
Route<void> _settingsRoute(AppState state) {
  return PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 240),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, __, ___) => SettingsScreen(state: state),
    transitionsBuilder: (_, animation, __, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.06),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({
    required this.streak,
    required this.takenToday,
    required this.totalToday,
  });

  final int streak;
  final int takenToday;
  final int totalToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final active = streak > 0;
    final dayWord = streak == 1 ? 'day' : 'days';

    // Warm "on fire" palette only once a streak is actually reached;
    // otherwise stay neutral so it doesn't look achieved when it isn't.
    final Color background = active
        ? (isDark ? const Color(0xFF4A2E12) : const Color(0xFFFFE6C2))
        : theme.colorScheme.surfaceContainerHighest;
    final Color foreground = active
        ? (isDark ? const Color(0xFFFFD8A8) : const Color(0xFF7A4A12))
        : theme.colorScheme.onSurfaceVariant;
    final Color iconColor =
        active ? const Color(0xFFFF7043) : theme.disabledColor;

    return Card(
      color: background,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(
              active
                  ? Icons.local_fire_department
                  : Icons.local_fire_department_outlined,
              size: 44,
              color: iconColor,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    active ? '$streak $dayWord in a row' : 'No streak yet',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: foreground,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    totalToday == 0
                        ? 'Nothing scheduled today'
                        : '$takenToday of $totalToday taken today',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: foreground),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DoseCard extends StatelessWidget {
  const _DoseCard({
    required this.dose,
    required this.taken,
    required this.onToggle,
  });

  final Dose dose;
  final bool taken;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 1,
      color: taken ? theme.colorScheme.primaryContainer : theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: taken
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: taken ? 2 : 1,
        ),
      ),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(
                dose.id == 'night'
                    ? Icons.nightlight_round
                    : Icons.wb_sunny_outlined,
                size: 28,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dose.label, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      '${dose.time.format(context)}  ·  ${dose.dosageLabel}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                taken ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 32,
                color: taken
                    ? theme.colorScheme.primary
                    : theme.disabledColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
